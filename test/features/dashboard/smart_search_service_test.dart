import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:isu_camp_app/features/dashboard/models/campus_models.dart';
import 'package:isu_camp_app/features/dashboard/services/smart_search_model_pack_service.dart';
import 'package:isu_camp_app/features/dashboard/services/smart_search_service.dart';
import 'package:latlong2/latlong.dart';

class _UnusedEmbedder implements CampusTextEmbedder {
  @override
  Future<void> load(SmartSearchModelPack pack) async {}

  @override
  Future<List<double>> embed(String text, {required String prefix}) async =>
      throw StateError('The model should not run in this test.');

  @override
  Future<void> close() async {}
}

class _FakeEmbedder implements CampusTextEmbedder {
  int passageCalls = 0;

  @override
  Future<void> load(SmartSearchModelPack pack) async {}

  @override
  Future<List<double>> embed(String text, {required String prefix}) async {
    if (prefix == 'passage: ') {
      passageCalls++;
      return text.contains('Library') ? [1, 0] : [0, 1];
    }
    return [1, 0];
  }

  @override
  Future<void> close() async {}
}

class _FailingEmbedder implements CampusTextEmbedder {
  @override
  Future<void> load(SmartSearchModelPack pack) async {}

  @override
  Future<List<double>> embed(String text, {required String prefix}) async =>
      throw StateError('inference failure');

  @override
  Future<void> close() async {}
}

CampusBuilding _building(String id, {String? name}) => CampusBuilding(
      id: id,
      name: name ?? 'Building $id',
      acronym: 'B$id',
      category: 'Academic Building',
      description: '',
      coordinate: const LatLng(16.72, 121.69),
    );

void main() {
  test('uses deterministic search when the model is not loaded', () async {
    final service = SmartSearchService(embedder: _UnusedEmbedder());
    final buildings = [_building('1')];
    var receivedQuery = '';

    final results = await service.search(
      query: '  Library  ',
      catalog: buildings,
      deterministicFallback: (query) {
        receivedQuery = query;
        return buildings;
      },
    );

    expect(receivedQuery, 'Library');
    expect(results, same(buildings));
    expect(service.isReady, isFalse);
  });

  test('pins the audited upstream E5 revision and artifact digests', () {
    expect(SmartSearchModelPackService.revision,
        '614241f622f53c4eeff9890bdc4f31cfecc418b3');
    expect(SmartSearchModelPackService.modelSize, 235052531);
    expect(SmartSearchModelPackService.tokenizerSize, 17082730);
    expect(SmartSearchModelPackService.modelSha256,
        '4654c156f3e4171abc9c716cdb771bf9116455d15ac1aab364aeeede0e3205b0');
    expect(SmartSearchModelPackService.tokenizerSha256,
        '0b44a9d7b51c3c62626640cda0e2c2f70fdacdc25bbbd68038369d14ebdf4c39');
  });

  test('shows a safe retry message instead of raw network error details', () {
    final error = Exception(
      'ClientConnection closed while receiving data, '
      'uri=https://cdn.example/model?signature=private',
    );

    final message = SmartSearchModelPackService.userFacingDownloadError(error);

    expect(message, SmartSearchModelPackService.downloadFailureMessage);
    expect(message, isNot(contains('cdn.example')));
    expect(message, isNot(contains('signature')));
  });

  test('ranks only known Buildings and reuses the derived passage index',
      () async {
    final directory = await Directory.systemTemp.createTemp('smart-search-');
    addTearDown(() => directory.delete(recursive: true));
    final embedder = _FakeEmbedder();
    final service = SmartSearchService(embedder: embedder);
    await service.load(SmartSearchModelPack(
      revision: SmartSearchModelPackService.revision,
      modelPath: '${directory.path}/model.onnx',
      tokenizerPath: '${directory.path}/tokenizer.json',
      storedBytes: 0,
    ));
    final catalog = [
      _building('1', name: 'Library'),
      _building('2', name: 'Auditorium'),
    ];

    final first = await service.search(
      query: 'study',
      catalog: catalog,
      deterministicFallback: (_) => throw StateError('Unexpected fallback'),
    );
    final second = await service.search(
      query: 'study',
      catalog: catalog,
      deterministicFallback: (_) => throw StateError('Unexpected fallback'),
    );

    expect(first.map((building) => building.id), ['1', '2']);
    expect(second.map((building) => building.id), ['1', '2']);
    expect(embedder.passageCalls, 2);
    await service.close();
  });

  test('falls back to deterministic results after model inference fails',
      () async {
    final directory = await Directory.systemTemp.createTemp('smart-search-');
    addTearDown(() => directory.delete(recursive: true));
    final service = SmartSearchService(embedder: _FailingEmbedder());
    await service.load(SmartSearchModelPack(
      revision: SmartSearchModelPackService.revision,
      modelPath: '${directory.path}/model.onnx',
      tokenizerPath: '${directory.path}/tokenizer.json',
      storedBytes: 0,
    ));
    final buildings = [_building('1')];
    final results = await service.search(
      query: 'library',
      catalog: buildings,
      deterministicFallback: (_) => buildings,
    );

    expect(results, same(buildings));
    await service.close();
  });
}
