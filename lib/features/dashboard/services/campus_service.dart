import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;

import '../../auth/services/auth_service.dart';
import '../models/campus_models.dart';
import 'campus_pack_service.dart';
import 'offline_campus_router.dart';

class CampusService {
  static Future<List<WalkingRoute>> fetchRoutes(
      NavigationOrigin origin, CampusBuilding destination) async {
    final pack = await CampusPackService().installed();
    if (pack?.routingGraph != null) {
      try {
        return OfflineCampusRouter.routes(
          graph: pack!.routingGraph!,
          origin: origin,
          destination: destination,
        );
      } on OfflineRouteException {
        // A newer online graph may have fixed a missing or disconnected path.
        if (!await _hasNetwork()) rethrow;
      }
    } else if (!await _hasNetwork()) {
      throw const OfflineRouteException(
          'Walking routes are not included in this saved campus pack. Connect to update it.');
    }
    final response = await http
        .post(
          Uri.parse('${AuthService.baseUrl}/campus/routes'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'mode': 'walking',
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
          : 'Unable to load walking routes.');
    }
    return (data['routes'] as List)
        .map((r) => WalkingRoute.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  static Future<bool> _hasNetwork() async {
    try {
      final result = await Connectivity().checkConnectivity();
      return result.any((connection) => connection != ConnectivityResult.none);
    } catch (_) {
      // Keep existing behavior on platforms where the connectivity plugin is unavailable.
      return true;
    }
  }

  static Future<List<CampusBuilding>> fetchBuildings() async {
    final pack = await CampusPackService().installed();
    if (pack != null) return pack.buildings;
    final response = await http
        .get(
          Uri.parse('${AuthService.baseUrl}/campus/buildings'),
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw Exception('Could not load campus locations.');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return (data['buildings'] as List<dynamic>)
        .map((row) => CampusBuilding.fromJson(row as Map<String, dynamic>))
        .toList();
  }
}
