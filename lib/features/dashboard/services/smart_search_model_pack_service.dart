import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Pinned artifacts for the optional E5 offline search experiment.
///
/// The model is deliberately downloaded as part of the offline pack instead
/// of being included in every application install (~235 MB compressed at the
/// source). The hashes are upstream Git LFS SHA-256 values for this revision.
class SmartSearchModelPackService {
  static const downloadFailureMessage =
      'Download interrupted. Check your connection, then tap to retry.';
  static const revision = '614241f622f53c4eeff9890bdc4f31cfecc418b3';
  static const modelSha256 =
      '4654c156f3e4171abc9c716cdb771bf9116455d15ac1aab364aeeede0e3205b0';
  static const tokenizerSha256 =
      '0b44a9d7b51c3c62626640cda0e2c2f70fdacdc25bbbd68038369d14ebdf4c39';
  static const modelSize = 235052531;
  static const tokenizerSize = 17082730;
  static const _repository = 'https://huggingface.co/intfloat/'
      'multilingual-e5-small/resolve/$revision/onnx/';
  static const _modelFile = 'model_O4.onnx';
  static const _tokenizerFile = 'tokenizer.json';

  final http.Client _client;

  SmartSearchModelPackService({http.Client? client})
      : _client = client ?? http.Client();

  static String userFacingDownloadError(Object _error) =>
      downloadFailureMessage;

  Future<Directory> _directory() async {
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory('${documents.path}/smart_search_e5_v1');
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  Future<SmartSearchModelPack?> installed() async {
    final directory = await _directory();
    final model = File('${directory.path}/$_modelFile');
    final tokenizer = File('${directory.path}/$_tokenizerFile');
    final metadata = File('${directory.path}/pack.json');
    if (!await model.exists() ||
        !await tokenizer.exists() ||
        !await metadata.exists()) return null;
    try {
      final manifest =
          jsonDecode(await metadata.readAsString()) as Map<String, dynamic>;
      if (manifest['revision'] != revision ||
          await model.length() != modelSize ||
          await tokenizer.length() != tokenizerSize ||
          await _sha256File(model) != modelSha256 ||
          await _sha256File(tokenizer) != tokenizerSha256) return null;
      return SmartSearchModelPack(
        revision: revision,
        modelPath: model.path,
        tokenizerPath: tokenizer.path,
        storedBytes: modelSize + tokenizerSize,
      );
    } catch (_) {
      return null;
    }
  }

  Future<SmartSearchModelPack> install({
    void Function(int received, int total)? onProgress,
  }) async {
    final directory = await _directory();
    var received = 0;
    final model = await _downloadVerified(
      directory,
      _modelFile,
      modelSize,
      modelSha256,
      (bytes) {
        received += bytes;
        onProgress?.call(received, modelSize + tokenizerSize);
      },
    );
    final tokenizer = await _downloadVerified(
      directory,
      _tokenizerFile,
      tokenizerSize,
      tokenizerSha256,
      (bytes) {
        received += bytes;
        onProgress?.call(received, modelSize + tokenizerSize);
      },
    );
    final temporaryMetadata = File('${directory.path}/pack.json.tmp');
    await temporaryMetadata.writeAsString(jsonEncode({
      'revision': revision,
      'modelSha256': modelSha256,
      'tokenizerSha256': tokenizerSha256,
      'license': 'MIT',
      'source': 'intfloat/multilingual-e5-small',
      'modelCard': 'https://huggingface.co/intfloat/multilingual-e5-small',
      'pinnedRepository':
          'https://huggingface.co/intfloat/multilingual-e5-small/tree/$revision',
      'attribution': 'intfloat/multilingual-e5-small; MIT licensed',
      'runtime': 'ONNX Runtime; local CPU inference',
    }));
    await temporaryMetadata.rename('${directory.path}/pack.json');
    return SmartSearchModelPack(
      revision: revision,
      modelPath: model.path,
      tokenizerPath: tokenizer.path,
      storedBytes: modelSize + tokenizerSize,
    );
  }

  Future<File> _downloadVerified(
      Directory directory,
      String filename,
      int expectedSize,
      String expectedHash,
      void Function(int) progress) async {
    final destination = File('${directory.path}/$filename');
    if (await destination.exists() &&
        await destination.length() == expectedSize &&
        await _sha256File(destination) == expectedHash) return destination;

    final temporary = File('${directory.path}/$filename.part');
    if (await temporary.exists()) await temporary.delete();
    final request = http.Request('GET', Uri.parse('$_repository$filename'));
    final response = await _client.send(request).timeout(
          const Duration(minutes: 5),
        );
    if (response.statusCode != 200) {
      throw Exception('Could not download the offline smart search model.');
    }
    final sink = temporary.openWrite();
    var count = 0;
    try {
      await for (final chunk in response.stream.timeout(
        const Duration(minutes: 2),
      )) {
        count += chunk.length;
        if (count > expectedSize) {
          throw Exception('The smart search model download is oversized.');
        }
        sink.add(chunk);
        progress(chunk.length);
      }
      await sink.flush();
      await sink.close();
      if (count != expectedSize ||
          await _sha256File(temporary) != expectedHash) {
        throw Exception(
            'The smart search model download is incomplete or corrupt.');
      }
      return await temporary.rename(destination.path);
    } catch (_) {
      await sink.close();
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
  }

  Future<void> remove() async {
    final directory = await _directory();
    if (await directory.exists()) await directory.delete(recursive: true);
  }

  Future<void> close() async => _client.close();

  static Future<String> _sha256File(File file) async {
    return await sha256
        .bind(file.openRead())
        .first
        .then((digest) => digest.toString());
  }
}

class SmartSearchModelPack {
  final String revision;
  final String modelPath;
  final String tokenizerPath;
  final int storedBytes;

  const SmartSearchModelPack({
    required this.revision,
    required this.modelPath,
    required this.tokenizerPath,
    required this.storedBytes,
  });
}
