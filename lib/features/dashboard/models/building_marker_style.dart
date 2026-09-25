import 'package:flutter/material.dart';

import 'campus_models.dart';

class BuildingMarkerStyle {
  const BuildingMarkerStyle({required this.icon, required this.color});

  final IconData icon;
  final Color color;
}

BuildingMarkerStyle buildingMarkerStyle(CampusBuilding building) {
  final identity =
      '${building.category} ${building.name} ${building.acronym}'.toLowerCase();

  if (building.isParking || identity.contains('parking')) {
    return const BuildingMarkerStyle(
      icon: Icons.local_parking,
      color: Color(0xFF2563EB),
    );
  }
  if (_containsAny(identity, const ['infirmary', 'clinic', 'health'])) {
    return const BuildingMarkerStyle(
      icon: Icons.local_hospital,
      color: Color(0xFFDC2626),
    );
  }
  if (_containsAny(identity, const ['library', 'learning resource'])) {
    return const BuildingMarkerStyle(
      icon: Icons.local_library,
      color: Color(0xFF7C3AED),
    );
  }
  if (_containsAny(identity, const ['laboratory', 'lab'])) {
    return const BuildingMarkerStyle(
      icon: Icons.science,
      color: Color(0xFF0891B2),
    );
  }
  if (_containsAny(
      identity, const ['osas', 'student service', 'student affairs'])) {
    return const BuildingMarkerStyle(
      icon: Icons.support_agent,
      color: Color(0xFFEA580C),
    );
  }
  if (_containsAny(identity, const ['administration', 'admin building'])) {
    return const BuildingMarkerStyle(
      icon: Icons.account_balance,
      color: Color(0xFF0F751B),
    );
  }
  if (_containsAny(identity, const ['canteen', 'cafeteria', 'food'])) {
    return const BuildingMarkerStyle(
      icon: Icons.restaurant,
      color: Color(0xFFD97706),
    );
  }
  if (_containsAny(identity, const ['gym', 'sports', 'athletic'])) {
    return const BuildingMarkerStyle(
      icon: Icons.sports_basketball,
      color: Color(0xFFEA580C),
    );
  }
  if (_containsAny(identity, const ['dorm', 'hostel', 'residence'])) {
    return const BuildingMarkerStyle(
      icon: Icons.bed,
      color: Color(0xFF4F46E5),
    );
  }
  if (_containsAny(identity, const ['security', 'guard', 'police'])) {
    return const BuildingMarkerStyle(
      icon: Icons.local_police,
      color: Color(0xFF334155),
    );
  }
  if (_containsAny(identity, const ['gate', 'entrance'])) {
    return const BuildingMarkerStyle(
      icon: Icons.sensor_door,
      color: Color(0xFF0F751B),
    );
  }
  if (_containsAny(identity, const ['chapel', 'church'])) {
    return const BuildingMarkerStyle(
      icon: Icons.church,
      color: Color(0xFF7C2D12),
    );
  }
  if (_containsAny(identity, const ['restroom', 'comfort room'])) {
    return const BuildingMarkerStyle(
      icon: Icons.wc,
      color: Color(0xFF475569),
    );
  }
  if (_containsAny(identity, const ['college', 'academic', 'school'])) {
    return const BuildingMarkerStyle(
      icon: Icons.school,
      color: Color(0xFF0F751B),
    );
  }
  return const BuildingMarkerStyle(
    icon: Icons.apartment,
    color: Color(0xFF0F751B),
  );
}

bool _containsAny(String value, List<String> candidates) {
  return candidates.any(value.contains);
}
