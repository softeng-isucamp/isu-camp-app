import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dart_sentencepiece_tokenizer/dart_sentencepiece_tokenizer.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import '../models/campus_models.dart';
import 'smart_search_model_pack_service.dart';

/// One ranked result always points to a known Building ID. Indoor Location
/// evidence is included in its parent Building passage because outdoor routes
/// currently target Buildings.
class SmartSearchResult {
  final CampusBuilding building;
  final double score;

  const SmartSearchResult({required this.building, required this.score});

  String get typedId => 'building:${building.id}';
}

typedef DeterministicCampusSearch = List<CampusBuilding> Function(String query);

/// Embedding seam kept injectable so the ranking/fallback behavior can be
/// checked without loading a 235 MB model in widget/service tests.
abstract interface class CampusTextEmbedder {
  Future<void> load(SmartSearchModelPack pack);
  Future<List<double>> embed(String text, {required String prefix});
  Future<void> close();
}

class SmartSearchService {
  final CampusTextEmbedder _embedder;
  bool _ready = false;
  SmartSearchModelPack? _pack;
  String? _indexCatalogHash;
  Future<Map<String, List<double>>>? _indexFuture;

  SmartSearchService({CampusTextEmbedder? embedder})
      : _embedder = embedder ?? E5OnnxEmbedder();

  bool get isReady => _ready;

  Future<void> load(SmartSearchModelPack pack) async {
    try {
      await _embedder.load(pack);
      _pack = pack;
      _ready = true;
    } catch (_) {
      _ready = false;
      rethrow;
    }
  }

  /// Ranks only provided catalog records. If model loading or inference fails,
  /// the caller's established literal search remains authoritative.
  Future<List<CampusBuilding>> search({
    required String query,
    required List<CampusBuilding> catalog,
    required DeterministicCampusSearch deterministicFallback,
  }) async {
    final normalizedQuery = query.trim();
    if (!_ready || normalizedQuery.isEmpty || catalog.isEmpty) {
      return deterministicFallback(normalizedQuery);
    }
    try {
      final passages = await _loadOrBuildPassageIndex(catalog);
      final queryVector = await _embedder.embed(
        normalizedQuery,
        prefix: 'query: ',
      );
      final results = <SmartSearchResult>[];
      for (final building in catalog) {
        final vector = passages[building.id];
        if (vector == null || vector.length != queryVector.length) continue;
        results.add(SmartSearchResult(
          building: building,
          score: _dot(queryVector, vector),
        ));
      }
      if (results.isEmpty) return deterministicFallback(normalizedQuery);
      results.sort((left, right) => right.score.compareTo(left.score));
      return results.map((result) => result.building).toList(growable: false);
    } catch (_) {
      return deterministicFallback(normalizedQuery);
    }
  }

  Future<Map<String, List<double>>> _loadOrBuildPassageIndex(
      List<CampusBuilding> catalog) async {
    final pack = _pack;
    if (pack == null) throw StateError('The E5 pack is not loaded.');
    final packDirectory = File(pack.modelPath);
    final indexFile = File('${packDirectory.parent.path}/passage-index.json');
    final catalogJson = jsonEncode(catalog
        .map((building) => {
              'id': building.id,
              'passage': _passage(building),
            })
        .toList());
    final catalogHash = sha256.convert(utf8.encode(catalogJson)).toString();
    if (_indexCatalogHash == catalogHash && _indexFuture != null) {
      return _indexFuture!;
    }
    _indexCatalogHash = catalogHash;
    final pending = _readOrBuildPassageIndex(
      indexFile,
      catalogHash,
      catalog,
    );
    _indexFuture = pending;
    try {
      return await pending;
    } catch (_) {
      if (_indexCatalogHash == catalogHash) {
        _indexFuture = null;
        _indexCatalogHash = null;
      }
      rethrow;
    }
  }

  Future<Map<String, List<double>>> _readOrBuildPassageIndex(
    File indexFile,
    String catalogHash,
    List<CampusBuilding> catalog,
  ) async {
    if (await indexFile.exists()) {
      try {
        final saved =
            jsonDecode(await indexFile.readAsString()) as Map<String, dynamic>;
        if (saved['revision'] == SmartSearchModelPackService.revision &&
            saved['catalogSha256'] == catalogHash) {
          return (saved['vectors'] as Map<String, dynamic>).map((id, row) =>
              MapEntry(id,
                  (row as List).cast<num>().map((n) => n.toDouble()).toList()));
        }
      } catch (_) {
        // Rebuild a missing, stale, or damaged derived index.
      }
    }

    final vectors = <String, List<double>>{};
    for (final building in catalog) {
      vectors[building.id] = await _embedder.embed(
        _passage(building),
        prefix: 'passage: ',
      );
    }
    final temporary = File('${indexFile.path}.$catalogHash.tmp');
    await temporary.writeAsString(jsonEncode({
      'revision': SmartSearchModelPackService.revision,
      'catalogSha256': catalogHash,
      'vectors': vectors,
    }));
    await temporary.rename(indexFile.path);
    return vectors;
  }

  static String _passage(CampusBuilding building) => [
        building.name,
        building.acronym,
        building.category,
        building.description,
        building.keywords,
        ...building.rooms.expand((room) => [
              room.title,
              room.category.name,
              room.description,
              room.keywords,
              room.floor,
              building.name,
            ]),
      ].where((part) => part.trim().isNotEmpty).join(' | ');

  static double _dot(List<double> left, List<double> right) {
    var value = 0.0;
    for (var index = 0; index < left.length; index++) {
      value += left[index] * right[index];
    }
    return value;
  }

  Future<void> close() async {
    _ready = false;
    _pack = null;
    _indexCatalogHash = null;
    _indexFuture = null;
    await _embedder.close();
  }
}

/// ONNX Runtime CPU implementation for Android and other supported Flutter
/// platforms. E5's graph returns token states, so this applies its documented
/// attention-mask mean pooling and L2 normalization in Dart.
class E5OnnxEmbedder implements CampusTextEmbedder {
  final OnnxRuntime _runtime;
  OrtSession? _session;
  SentencePieceTokenizer? _tokenizer;
  SmartSearchModelPack? pack;

  E5OnnxEmbedder({OnnxRuntime? runtime}) : _runtime = runtime ?? OnnxRuntime();

  @override
  Future<void> load(SmartSearchModelPack modelPack) async {
    await close();
    final session = await _runtime.createSession(modelPack.modelPath);
    try {
      final tokenizer = await TokenizerJsonLoader.fromJsonFile(
        modelPack.tokenizerPath,
      );
      tokenizer.enableTruncation(
        maxLength: 512,
        direction: SpTruncationDirection.right,
      );
      if (!session.inputNames.contains('input_ids') ||
          !session.inputNames.contains('attention_mask') ||
          session.outputNames.isEmpty) {
        throw StateError('The E5 ONNX input/output signature is unsupported.');
      }
      _session = session;
      _tokenizer = tokenizer;
      pack = modelPack;
    } catch (_) {
      await session.close();
      rethrow;
    }
  }

  @override
  Future<List<double>> embed(String text, {required String prefix}) async {
    final session = _session;
    final tokenizer = _tokenizer;
    if (session == null || tokenizer == null) {
      throw StateError('The E5 model is not loaded.');
    }
    final encoded = tokenizer.encode('$prefix$text');
    final ids = encoded.ids.map((id) => id.toInt()).toList();
    if (ids.isEmpty)
      throw ArgumentError.value(text, 'text', 'must not be empty');
    final mask = List<int>.filled(ids.length, 1);
    final inputs = <String, OrtValue>{
      'input_ids': await OrtValue.fromList(
        Int64List.fromList(ids),
        [1, ids.length],
      ),
      'attention_mask': await OrtValue.fromList(
        Int64List.fromList(mask),
        [1, mask.length],
      ),
    };
    if (session.inputNames.contains('token_type_ids')) {
      inputs['token_type_ids'] = await OrtValue.fromList(
        Int64List(ids.length),
        [1, ids.length],
      );
    }
    Map<String, OrtValue> outputs = const {};
    try {
      outputs = await session.run(inputs);
      final tensor = outputs[session.outputNames.first];
      if (tensor == null) throw StateError('The E5 model returned no output.');
      final flat = (await tensor.asFlattenedList()).cast<num>();
      final dimensions = 384;
      if (flat.length != ids.length * dimensions) {
        throw StateError('Unexpected E5 token embedding shape.');
      }
      final mean = List<double>.filled(dimensions, 0);
      for (var token = 0; token < ids.length; token++) {
        for (var dimension = 0; dimension < dimensions; dimension++) {
          mean[dimension] += flat[token * dimensions + dimension].toDouble();
        }
      }
      for (var index = 0; index < mean.length; index++) {
        mean[index] /= ids.length;
      }
      final norm =
          math.sqrt(mean.fold<double>(0, (sum, value) => sum + value * value));
      if (norm == 0 || !norm.isFinite) {
        throw StateError('The E5 model returned an invalid embedding.');
      }
      return mean.map((value) => value / norm).toList(growable: false);
    } finally {
      for (final tensor in inputs.values) {
        await tensor.dispose();
      }
      for (final tensor in outputs.values) {
        await tensor.dispose();
      }
    }
  }

  @override
  Future<void> close() async {
    final current = _session;
    _session = null;
    _tokenizer = null;
    pack = null;
    if (current != null) await current.close();
  }
}
