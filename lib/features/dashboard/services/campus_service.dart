import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../auth/services/auth_service.dart';
import '../models/campus_models.dart';

class CampusService {
  static Future<List<WalkingRoute>> fetchRoutes(
      NavigationOrigin origin, CampusBuilding destination,
      {TransportMode mode = TransportMode.walking}) async {
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
  }

  static Future<List<CampusBuilding>> fetchBuildings() async {
    final response = await http
        .get(
          Uri.parse('${AuthService.baseUrl}/campus/buildings'),
        )
        // The campus response includes embedded building and room photos and
        // can take more than 20 seconds to download on a mobile connection.
        .timeout(const Duration(seconds: 60));
    if (response.statusCode != 200) {
      throw Exception('Could not load campus locations.');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return (data['buildings'] as List<dynamic>)
        .map((row) => CampusBuilding.fromJson(row as Map<String, dynamic>))
        .toList();
  }
}
