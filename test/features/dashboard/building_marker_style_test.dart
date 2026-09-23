import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isu_camp_app/features/dashboard/models/building_marker_style.dart';
import 'package:isu_camp_app/features/dashboard/models/campus_models.dart';
import 'package:latlong2/latlong.dart';

void main() {
  CampusBuilding building({
    required String name,
    String category = 'Building',
    bool isParking = false,
  }) {
    return CampusBuilding(
      id: name,
      name: name,
      acronym: '',
      category: category,
      description: '',
      coordinate: const LatLng(16.72, 121.69),
      isParking: isParking,
    );
  }

  test('uses semantic icons for recognizable campus locations', () {
    expect(buildingMarkerStyle(building(name: 'University Infirmary')).icon,
        Icons.local_hospital);
    expect(buildingMarkerStyle(building(name: 'Main Library')).icon,
        Icons.local_library);
    expect(buildingMarkerStyle(building(name: 'Science Laboratory')).icon,
        Icons.science);
    expect(buildingMarkerStyle(building(name: 'Main Gate')).icon,
        Icons.sensor_door);
  });

  test('parking flag wins and unknown locations use a clean fallback', () {
    expect(
      buildingMarkerStyle(building(name: 'North Lot', isParking: true)).icon,
      Icons.local_parking,
    );
    expect(buildingMarkerStyle(building(name: 'New Facility')).icon,
        Icons.apartment);
  });
}
