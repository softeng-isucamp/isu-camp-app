import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

enum RoomCategory {
  room,
  laboratory,
  office,
  restroom,
  administrative,
  faculty,
  classroom,
  studyArea,
  facility,
  parking,
}

enum RouteType {
  shortest,
  comfortableShaded,
}

class WalkingRouteStep {
  final String instruction;
  final double distanceMeters;
  final LatLng? coordinate;

  const WalkingRouteStep({
    required this.instruction,
    required this.distanceMeters,
    required this.coordinate,
  });

  factory WalkingRouteStep.fromJson(Map<String, dynamic> json) {
    final rawCoordinate = json['coordinate'];
    LatLng? coordinate;
    if (rawCoordinate is List && rawCoordinate.length >= 2) {
      coordinate = LatLng(
        (rawCoordinate[0] as num).toDouble(),
        (rawCoordinate[1] as num).toDouble(),
      );
    }

    return WalkingRouteStep(
      instruction: json['instruction'] as String? ?? 'Follow the route',
      distanceMeters: (json['distanceMeters'] as num?)?.toDouble() ?? 0,
      coordinate: coordinate,
    );
  }

  String get distance => '${distanceMeters.round()} m';
}

class WalkingRoute {
  final RouteType type;
  final double distanceMeters;
  final double estimatedMinutes;
  final List<LatLng> points;
  final String startNodeName;
  final List<WalkingRouteStep> steps;

  WalkingRoute.fromJson(Map<String, dynamic> json)
      : type = RouteType.values.byName(json['type'] as String),
        distanceMeters = (json['distanceMeters'] as num).toDouble(),
        estimatedMinutes = (json['estimatedMinutes'] as num).toDouble(),
        startNodeName = json['startNodeName'] as String,
        points = (json['pathPoints'] as List)
            .map((p) =>
                LatLng((p[0] as num).toDouble(), (p[1] as num).toDouble()))
            .toList(),
        steps = ((json['steps'] as List?) ?? const [])
            .map((step) => WalkingRouteStep.fromJson(
                  Map<String, dynamic>.from(step as Map),
                ))
            .toList();

  List<String> get instructions =>
      steps.map((step) => step.instruction).toList(growable: false);

  String get distance => '${distanceMeters.round()} m';
  String get time => '${estimatedMinutes.ceil()} min';
  String get arrivalTime {
    final arrival =
        DateTime.now().add(Duration(seconds: (estimatedMinutes * 60).round()));
    return '${arrival.hour.toString().padLeft(2, '0')}:${arrival.minute.toString().padLeft(2, '0')}';
  }
}

enum TransportMode {
  car,
  motorcycle,
  bicycle,
  walking,
}

enum NavigationOriginType {
  currentLocation,
  campusCenter,
  mainGate,
  campusLocation,
}

class NavigationOrigin {
  final String id;
  final String label;
  final LatLng coordinate;
  final NavigationOriginType type;

  const NavigationOrigin({
    required this.id,
    required this.label,
    required this.coordinate,
    required this.type,
  });
}

class CampusRoom {
  final String id;
  final String title;
  final RoomCategory category;
  final String floor;
  final String description;
  final String keywords;
  final IconData icon;

  const CampusRoom({
    required this.id,
    required this.title,
    required this.category,
    required this.floor,
    this.description = '',
    this.keywords = '',
    required this.icon,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'category': category.name,
        'floor': floor,
        'description': description,
        'keywords': keywords,
      };

  factory CampusRoom.fromJson(Map<String, dynamic> json) => CampusRoom(
        id: json['id'] ?? '',
        title: json['title'] ?? '',
        category: RoomCategory.values.firstWhere(
          (e) => e.name == json['category'],
          orElse: () => RoomCategory.classroom,
        ),
        floor: json['floor'] ?? '1st Floor',
        description: json['description'] ?? '',
        keywords: json['keywords'] ?? '',
        icon: Icons.meeting_room_outlined,
      );
}

class NavigationStep {
  final String instruction;
  final String distance;
  final IconData icon;
  final LatLng coordinate;

  const NavigationStep({
    required this.instruction,
    required this.distance,
    required this.icon,
    required this.coordinate,
  });
}

class CampusRoute {
  final RouteType type;
  final String title;
  final String subtitle;
  final String distance;
  final String estimatedTime;
  final String arrivalTime;
  final IconData icon;
  final List<LatLng> pathPoints;
  final List<NavigationStep> steps;

  const CampusRoute({
    required this.type,
    required this.title,
    required this.subtitle,
    required this.distance,
    required this.estimatedTime,
    this.arrivalTime = '9:46 am',
    required this.icon,
    required this.pathPoints,
    this.steps = const [],
  });

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'title': title,
        'subtitle': subtitle,
        'distance': distance,
        'estimatedTime': estimatedTime,
        'arrivalTime': arrivalTime,
        'pathPoints': pathPoints
            .map((p) => {'lat': p.latitude, 'lng': p.longitude})
            .toList(),
      };
}

class CampusBuilding {
  final String id;
  final String name;
  final String acronym;
  final String category;
  final String description;
  final String keywords;
  final LatLng coordinate;
  final String? imageUrl;
  final bool isParking;
  final bool hasShadedPath;
  final List<CampusRoom> rooms;
  final List<CampusRoute> routes;
  final List<LatLng> polygonCoordinates;

  const CampusBuilding({
    required this.id,
    required this.name,
    required this.acronym,
    required this.category,
    required this.description,
    this.keywords = '',
    required this.coordinate,
    this.imageUrl,
    this.isParking = false,
    this.hasShadedPath = false,
    this.rooms = const [],
    this.routes = const [],
    this.polygonCoordinates = const [],
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'acronym': acronym,
        'category': category,
        'description': description,
        'keywords': keywords,
        'latitude': coordinate.latitude,
        'longitude': coordinate.longitude,
        'imageUrl': imageUrl,
        'isParking': isParking,
        'hasShadedPath': hasShadedPath,
        'rooms': rooms.map((r) => r.toJson()).toList(),
        'routes': routes.map((r) => r.toJson()).toList(),
        'polygonCoordinates': polygonCoordinates
            .map((point) => [point.latitude, point.longitude])
            .toList(),
      };

  factory CampusBuilding.fromJson(Map<String, dynamic> json) => CampusBuilding(
        id: json['id'] ?? '',
        name: json['name'] ?? '',
        acronym: json['acronym'] ?? '',
        category: json['category'] ?? 'Academic Building',
        description: json['description'] ?? '',
        keywords: json['keywords'] ?? '',
        coordinate: LatLng(
          (json['latitude'] as num?)?.toDouble() ?? 16.7118,
          (json['longitude'] as num?)?.toDouble() ?? 121.6888,
        ),
        imageUrl: json['imageUrl'],
        isParking: json['isParking'] ?? false,
        hasShadedPath: json['hasShadedPath'] ?? false,
        polygonCoordinates: (json['polygonCoordinates'] as List<dynamic>? ?? [])
            .map((point) => LatLng(
                (point[0] as num).toDouble(), (point[1] as num).toDouble()))
            .toList(),
        rooms: (json['rooms'] as List<dynamic>?)
                ?.map((r) => CampusRoom.fromJson(r))
                .toList() ??
            [],
      );
}
