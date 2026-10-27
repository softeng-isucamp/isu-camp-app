import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../auth/services/auth_service.dart';
import '../../offline/services/offline_pack_service.dart';
import '../models/campus_models.dart';

class CampusService {
  /// True when the request never reached the backend, so the downloaded pack
  /// can answer instead. A real HTTP response is always reported as it came.
  /// package:http wraps a failed socket in a ClientException on every
  /// platform, so this covers native and browser clients alike.
  static bool _isUnreachable(Object error) =>
      error is TimeoutException || error is http.ClientException;

  static Future<List<WalkingRoute>> fetchRoutes(
      NavigationOrigin origin, CampusBuilding destination,
      {TransportMode mode = TransportMode.walking}) async {
    try {
      final response = await http
          .post(
            Uri.parse('${AuthService.baseUrl}/campus/routes'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'mode': mode.name,
              'destinationBuildingId': destination.id,
              'origin': {
                'type': origin.type.name,
                'buildingId': origin.type == NavigationOriginType.campusLocation
                    ? origin.id
                    : null,
                'latitude': origin.coordinate.latitude,
                'longitude': origin.coordinate.longitude
              },
            }),
          )
          .timeout(const Duration(seconds: 30));
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200) {
        throw Exception(data['detail'] is String
            ? data['detail']
            : 'Unable to load routes for this transport mode.');
      }
      return (data['routes'] as List)
          .map((r) => WalkingRoute.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (error) {
      if (!_isUnreachable(error) || !OfflinePackService.instance.status.isReady) {
        rethrow;
      }
      // Same graph, same algorithm, computed on this device.
      return OfflinePackService.instance
          .offlineRoutes(origin: origin, destination: destination, mode: mode);
    }
  }

  static Future<List<CampusBuilding>> fetchBuildings() async {
    try {
      final response = await http
          .get(
            Uri.parse('${AuthService.baseUrl}/campus/buildings'),
          )
          // Photo bytes load separately; this request only fetches map metadata.
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw Exception('Could not load campus locations.');
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return (data['buildings'] as List<dynamic>)
          .map((row) => CampusBuilding.fromJson(row as Map<String, dynamic>))
          .toList();
    } catch (error) {
      final downloaded = OfflinePackService.instance.buildings;
      if (!_isUnreachable(error) || downloaded == null) rethrow;
      return downloaded;
    }
  }
}
