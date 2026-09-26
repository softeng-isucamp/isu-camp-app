import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../auth/services/auth_service.dart';
import '../models/campus_models.dart';

const _storageKey = 'campus_pack_v1';

class CampusPack {
  final String version;
  final int size;
  final int storedBytes;
  final List<CampusBuilding> buildings;
  final Map<String, dynamic>? routingGraph;

  CampusPack(this.version, this.size, this.storedBytes, this.buildings,
      {this.routingGraph});
}

class CampusPackService {
  final http.Client _client;
  final String baseUrl;

  CampusPackService({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        baseUrl = baseUrl ?? AuthService.baseUrl;

  Future<CampusPack?> installed() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null) return null;
    try {
      final saved = jsonDecode(raw) as Map<String, dynamic>;
      final content = base64Decode(saved['content'] as String);
      final expected = saved['sha256'] as String;
      if (saved['schemaVersion'] != 1 ||
          content.length != saved['size'] ||
          sha256.convert(content).toString() != expected) {
        return null;
      }
      final catalog = jsonDecode(utf8.decode(content)) as Map<String, dynamic>;
      final buildings = (catalog['buildings'] as List)
          .map((row) =>
              CampusBuilding.fromJson(Map<String, dynamic>.from(row as Map)))
          .toList();
      return CampusPack(
          expected, content.length, utf8.encode(raw).length, buildings,
          routingGraph: catalog['routingGraph'] is Map
              ? Map<String, dynamic>.from(catalog['routingGraph'] as Map)
              : null);
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> latestManifest() async {
    final response = await _client
        .get(Uri.parse('$baseUrl/campus/pack/manifest'))
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200)
      throw Exception('Could not check the campus pack.');
    final manifest = jsonDecode(response.body) as Map<String, dynamic>;
    final minClientSchema = manifest['minClientSchema'];
    final maxClientSchema = manifest['maxClientSchema'];
    if (manifest['schemaVersion'] != 1 ||
        minClientSchema is! int ||
        maxClientSchema is! int ||
        minClientSchema > 1 ||
        maxClientSchema < 1 ||
        minClientSchema > maxClientSchema) {
      throw Exception('This campus pack needs a newer app version.');
    }
    final files = manifest['files'] as List;
    if (files.length != 1 || (files.single as Map)['path'] != 'catalog.json') {
      throw Exception('This campus pack is not supported by this app.');
    }
    return manifest;
  }

  Future<CampusPack> install(
      {void Function(int received, int total)? onProgress}) async {
    final manifest = await latestManifest();
    final file =
        Map<String, dynamic>.from((manifest['files'] as List).single as Map);
    final size = file['size'] as int;
    final checksum = file['sha256'] as String;
    final path = file['url'] as String;
    if (size <= 0 ||
        size > 25 * 1024 * 1024 ||
        checksum != manifest['catalogVersion'] ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(checksum) ||
        !path.startsWith('/campus/pack/catalog?')) {
      throw Exception('The campus pack manifest is invalid.');
    }
    final base = Uri.parse(baseUrl);
    final response = await _client
        .send(http.Request('GET', base.resolve(path)))
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200)
      throw Exception(
          'The campus pack changed or the download failed. Try again.');
    final builder = BytesBuilder(copy: false);
    await for (final chunk
        in response.stream.timeout(const Duration(seconds: 20))) {
      builder.add(chunk);
      if (builder.length > size)
        throw Exception('The campus pack is larger than expected.');
      onProgress?.call(builder.length, size);
    }
    final content = builder.takeBytes();
    if (content.length != size ||
        sha256.convert(content).toString() != checksum) {
      throw Exception('The campus pack is incomplete or corrupt. Try again.');
    }
    final catalog = jsonDecode(utf8.decode(content)) as Map<String, dynamic>;
    final buildings = (catalog['buildings'] as List)
        .map((row) =>
            CampusBuilding.fromJson(Map<String, dynamic>.from(row as Map)))
        .toList();
    if (buildings.isEmpty)
      throw Exception('The campus pack has no searchable buildings.');
    final prefs = await SharedPreferences.getInstance();
    final saved = jsonEncode({
      'schemaVersion': 1,
      'size': size,
      'sha256': checksum,
      'content': base64Encode(content),
    });
    if (!await prefs.setString(_storageKey, saved)) {
      throw Exception('Could not save the campus pack on this device.');
    }
    return CampusPack(
      checksum,
      size,
      utf8.encode(saved).length,
      buildings,
      routingGraph: catalog['routingGraph'] is Map
          ? Map<String, dynamic>.from(catalog['routingGraph'] as Map)
          : null,
    );
  }

  Future<void> remove() async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.remove(_storageKey))
      throw Exception('Could not remove the campus pack.');
  }

  void close() => _client.close();
}
