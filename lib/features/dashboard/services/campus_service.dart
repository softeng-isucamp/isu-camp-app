import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../auth/services/auth_service.dart';
import '../models/campus_models.dart';

class CampusService {
  static Future<List<WalkingRoute>> fetchRoutes(
      NavigationOrigin origin, CampusBuilding destination) async {
    final response = await http
        .post(
          AuthService.endpoint('/campus/routes'),
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

  static Future<List<CampusBuilding>> fetchBuildings() async {
    final response = await http
        .get(
          AuthService.endpoint('/campus/buildings'),
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
