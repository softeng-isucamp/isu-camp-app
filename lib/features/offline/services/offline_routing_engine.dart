library;

import 'dart:math' as math;

/// Offline port of the backend campus router (`server/app/utils/routing.py`).
///
/// It consumes the same `route_node` / `pathway` / `pathway_allowed_mode` /
/// `path_point` rows the backend reads and returns the same JSON shape, so
/// `WalkingRoute.fromJson` parses an offline route exactly like a live one.
/// Keep both implementations in step: a change to one needs the other.

const Map<String, double> _shadePenalties = {
  'fully shaded': 0,
  'mostly shaded': .25,
  'partial shade': .5,
  'unshaded': 1,
  'unknown': 1,
};

/// Nominal campus travel estimates in meters/minute, not live traffic speeds.
const Map<String, double> _modeSpeeds = {
  'walking': 80,
  'car': 350,
  'motorcycle': 450,
  'bicycle': 220,
};

const Map<String, String> _modeLabels = {
  'walking': 'Walking',
  'car': 'Car',
  'motorcycle': 'Motorcycle',
  'bicycle': 'Bicycle',
};

const Map<String, String> _modeAliases = {
  'walking': 'walking',
  'walk': 'walking',
  'pedestrian': 'walking',
  'car': 'car',
  'motorcycle': 'motorcycle',
  'motorbike': 'motorcycle',
  'motor': 'motorcycle',
  'bicycle': 'bicycle',
  'bike': 'bicycle',
  'cycling': 'bicycle',
  'vehicle': 'vehicle',
};

class OfflineRoutingException implements Exception {
  final String message;
  const OfflineRoutingException(this.message);

  @override
  String toString() => message;
}

/// The current admin dataset uses Vehicle as an umbrella for wheeled modes.
/// Specific car/motorcycle/bicycle labels remain specific when provided.
bool pathwayAllowsMode(Object? value, String mode) {
  final label = _modeAliases[(value?.toString() ?? '').trim().toLowerCase()];
  return label == mode ||
      (label == 'vehicle' &&
          (mode == 'car' || mode == 'motorcycle' || mode == 'bicycle'));
}

double metersBetween(List<double> a, List<double> b) {
  final lat1 = a[0] * math.pi / 180;
  final lat2 = b[0] * math.pi / 180;
  final deltaLat = lat2 - lat1;
  final deltaLng = (b[1] - a[1]) * math.pi / 180;
  final h = math.pow(math.sin(deltaLat / 2), 2) +
      math.cos(lat1) * math.cos(lat2) * math.pow(math.sin(deltaLng / 2), 2);
  return 6371000 * 2 * math.asin(math.min(1, math.sqrt(h)));
}

List<double>? parseCoordinate(Object? latitude, Object? longitude) {
  final lat = latitude is num
      ? latitude.toDouble()
      : double.tryParse(latitude?.toString() ?? '');
  final lng = longitude is num
      ? longitude.toDouble()
      : double.tryParse(longitude?.toString() ?? '');
  if (lat == null || lng == null || !lat.isFinite || !lng.isFinite) return null;
  if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
  return [lat, lng];
}

class _Projection {
  final double distance;
  final List<double> point;
  final List<List<double>> remaining;
  const _Projection(this.distance, this.point, this.remaining);
}

/// Closest point on [geometry] to [position], plus the path still ahead of it.
_Projection? projectOnPath(List<double> position, List<List<double>> geometry) {
  final scale = math.cos(position[0] * math.pi / 180);
  _Projection? best;
  for (var index = 0; index < geometry.length - 1; index++) {
    final a = geometry[index];
    final b = geometry[index + 1];
    final dx = (b[1] - a[1]) * scale;
    final dy = b[0] - a[0];
    final px = (position[1] - a[1]) * scale;
    final py = position[0] - a[0];
    final square = dx * dx + dy * dy;
    final fraction =
        square == 0 ? 0.0 : ((px * dx + py * dy) / square).clamp(0.0, 1.0);
    final point = [a[0] + dy * fraction, a[1] + (b[1] - a[1]) * fraction];
    final distance = metersBetween(position, point);
    if (best == null || distance < best.distance) {
      best = _Projection(distance, point,
          [point, ...geometry.sublist(index + 1).map((p) => List<double>.of(p))]);
    }
  }
  return best;
}

class _Edge {
  final String pathwayId;
  final String name;
  final double distanceMeters;
  final double estimatedMinutes;
  final double penalty;
  final List<List<double>> points;

  const _Edge({
    required this.pathwayId,
    required this.name,
    required this.distanceMeters,
    required this.estimatedMinutes,
    required this.penalty,
    required this.points,
  });

  _Edge replacing({
    required List<List<double>> points,
    required double distanceMeters,
    required double estimatedMinutes,
  }) =>
      _Edge(
        pathwayId: pathwayId,
        name: name,
        distanceMeters: distanceMeters,
        estimatedMinutes: estimatedMinutes,
        penalty: penalty,
        points: points,
      );
}

/// Smallest-cost-first queue for the Dijkstra search below.
class _CostQueue {
  final List<(double, String)> _entries = [];

  bool get isEmpty => _entries.isEmpty;

  void add(double cost, String node) {
    _entries.add((cost, node));
    var child = _entries.length - 1;
    while (child > 0) {
      final parent = (child - 1) ~/ 2;
      if (_compare(_entries[child], _entries[parent]) >= 0) break;
      final swap = _entries[parent];
      _entries[parent] = _entries[child];
      _entries[child] = swap;
      child = parent;
    }
  }

  (double, String) removeFirst() {
    final first = _entries.first;
    final last = _entries.removeLast();
    if (_entries.isEmpty) return first;
    _entries[0] = last;
    var parent = 0;
    while (true) {
      final left = parent * 2 + 1;
      final right = left + 1;
      var smallest = parent;
      if (left < _entries.length &&
          _compare(_entries[left], _entries[smallest]) < 0) {
        smallest = left;
      }
      if (right < _entries.length &&
          _compare(_entries[right], _entries[smallest]) < 0) {
        smallest = right;
      }
      if (smallest == parent) return first;
      final swap = _entries[parent];
      _entries[parent] = _entries[smallest];
      _entries[smallest] = swap;
      parent = smallest;
    }
  }

  int _compare((double, String) a, (double, String) b) {
    final byCost = a.$1.compareTo(b.$1);
    return byCost != 0 ? byCost : a.$2.compareTo(b.$2);
  }
}

class OfflineRoutingEngine {
  /// [graph] is the `graph` object of a downloaded offline bundle.
  OfflineRoutingEngine(Map<String, dynamic> graph)
      : _nodeRows = _rows(graph['nodes']),
        _pathwayRows = _rows(graph['pathways']),
        _modeRows = _rows(graph['modes']),
        _pointRows = _rows(graph['points']);

  final List<Map<String, dynamic>> _nodeRows;
  final List<Map<String, dynamic>> _pathwayRows;
  final List<Map<String, dynamic>> _modeRows;
  final List<Map<String, dynamic>> _pointRows;

  static List<Map<String, dynamic>> _rows(Object? value) =>
      (value as List<dynamic>? ?? const [])
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList(growable: false);

  static String _text(Object? value) =>
      (value?.toString() ?? '').trim().toLowerCase();

  /// Returns `{'routes': [shortest, comfortableShaded]}` in the backend's shape.
  Map<String, dynamic> routes(Map<String, dynamic> request) {
    final mode = (request['mode'] as String?) ?? 'walking';
    final speed = _modeSpeeds[mode];
    if (speed == null) {
      throw const OfflineRoutingException('Unsupported transport mode.');
    }
    final label = _modeLabels[mode]!;

    final nodes = <String, Map<String, dynamic>>{};
    for (final row in _nodeRows) {
      if (_text(row['status']) != 'active') continue;
      final position = parseCoordinate(row['latitude'], row['longitude']);
      if (position == null) continue;
      nodes[row['node_id'].toString()] = {...row, 'position': position};
    }

    final allowed = _modeRows
        .where((row) => pathwayAllowsMode(row['mode'], mode))
        .map((row) => row['pathway_id'].toString())
        .toSet();

    final shapes = <String, List<(int, List<double>)>>{};
    for (final row in _pointRows) {
      if (_text(row['status']) != 'active') continue;
      final position = parseCoordinate(row['latitude'], row['longitude']);
      if (position == null) continue;
      shapes
          .putIfAbsent(row['pathway_id'].toString(), () => [])
          .add(((row['sequence_no'] as num).toInt(), position));
    }

    final graph = {for (final id in nodes.keys) id: <(String, _Edge)>[]};
    for (final row in _pathwayRows) {
      final pathwayId = row['pathway_id'].toString();
      final source = row['source_node_id'].toString();
      final destination = row['destination_node_id'].toString();
      // Direction labels may use spaces, underscores, or hyphens in the table.
      final direction =
          _text(row['direction']).replaceAll(RegExp(r'[\s_-]+'), '');
      if (!allowed.contains(pathwayId) ||
          !nodes.containsKey(source) ||
          !nodes.containsKey(destination) ||
          _text(row['status']) != 'active' ||
          (direction != 'oneway' && direction != 'twoway')) {
        continue;
      }

      final start = nodes[source]!['position'] as List<double>;
      final end = nodes[destination]!['position'] as List<double>;
      final shape = (shapes[pathwayId] ?? [])
          .toList()
        ..sort((a, b) => a.$1.compareTo(b.$1));
      var points = shape.map((entry) => entry.$2).toList();
      if (points.isNotEmpty &&
          metersBetween(start, points.last) + metersBetween(end, points.first) <
              metersBetween(start, points.first) +
                  metersBetween(end, points.last)) {
        points = points.reversed.toList();
      }

      final geometry = <List<double>>[];
      for (final position in [start, ...points, end]) {
        if (geometry.isEmpty ||
            geometry.last[0] != position[0] ||
            geometry.last[1] != position[1]) {
          geometry.add(position);
        }
      }
      final length = _pathLength(geometry);
      if (length <= 0) continue;

      final edge = _Edge(
        pathwayId: pathwayId,
        name: (row['name'] as String?) ?? 'Campus pathway',
        distanceMeters: length,
        estimatedMinutes: length / speed,
        penalty: _shadePenalties[_text(row['shade'])] ?? 1,
        points: geometry,
      );
      graph[source]!.add((destination, edge));
      if (direction == 'twoway') {
        graph[destination]!.add((
          source,
          edge.replacing(
            points: geometry.reversed.toList(),
            distanceMeters: length,
            estimatedMinutes: length / speed,
          )
        ));
      }
    }

    final destinationId = request['destinationBuildingId'].toString();
    final targets = nodes.entries
        .where((entry) =>
            entry.value['building_id'] != null &&
            entry.value['building_id'].toString() == destinationId &&
            _text(entry.value['node_type']) == 'entrance')
        .map((entry) => entry.key)
        .toSet();
    if (targets.isEmpty) {
      throw const OfflineRoutingException(
          'This building has no active entrance linked to the routing network.');
    }

    final origin = Map<String, dynamic>.from(request['origin'] as Map);
    final kind = origin['type'] as String?;
    Set<String> starts;
    if (kind == 'campusLocation') {
      final originBuilding = origin['buildingId'].toString();
      starts = nodes.entries
          .where((entry) =>
              entry.value['building_id'] != null &&
              entry.value['building_id'].toString() == originBuilding &&
              _text(entry.value['node_type']) == 'entrance')
          .map((entry) => entry.key)
          .toSet();
      if (starts.isEmpty) {
        throw const OfflineRoutingException(
            'The starting building has no active entrance linked to the routing network.');
      }
    } else if (kind == 'mainGate') {
      starts = nodes.entries
          .where((entry) => const {'gate', 'main gate', 'isu main gate'}
              .contains(_text(entry.value['name'])))
          .map((entry) => entry.key)
          .toSet();
      if (starts.length != 1) {
        throw const OfflineRoutingException(
            'The main gate could not be identified uniquely in the routing network.');
      }
    } else {
      final position = parseCoordinate(origin['latitude'], origin['longitude']);
      final candidates = <(String, _Edge, _Projection)>[];
      if (position != null) {
        for (final source in graph.keys) {
          for (final (destination, edge) in graph[source]!) {
            final projection = projectOnPath(position, edge.points);
            if (projection != null) {
              candidates.add((destination, edge, projection));
            }
          }
        }
      }
      if (candidates.isEmpty) {
        throw OfflineRoutingException(
            'No ${label.toLowerCase()} starting point is available on permitted pathways.');
      }
      final nearest = candidates.reduce((a, b) =>
          a.$3.distance <= b.$3.distance ? a : b);
      if (nearest.$3.distance > 200) {
        throw OfflineRoutingException(
            'No permitted ${label.toLowerCase()} pathway within 200 m. Choose a campus building or the main gate.');
      }
      // Snap to a pathway interior without routing back to a distant node.
      // Only the directions already allowed by the dataset are connected.
      const startId = '__current_location__';
      nodes[startId] = {
        'position': nearest.$3.point,
        'name': nearest.$2.name,
      };
      graph[startId] = [];
      for (final (destination, edge, projection) in candidates) {
        if (edge.pathwayId != nearest.$2.pathwayId) continue;
        final length = _pathLength(projection.remaining);
        graph[startId]!.add((
          destination,
          edge.replacing(
            points: projection.remaining,
            distanceMeters: length,
            estimatedMinutes: length / speed,
          )
        ));
      }
      starts = {startId};
    }

    return {
      'routes': [
        _solve(nodes, graph, starts, targets, mode, label, shaded: false),
        _solve(nodes, graph, starts, targets, mode, label, shaded: true),
      ]
    };
  }

  static double _pathLength(List<List<double>> geometry) {
    var total = 0.0;
    for (var index = 0; index < geometry.length - 1; index++) {
      total += metersBetween(geometry[index], geometry[index + 1]);
    }
    return total;
  }

  Map<String, dynamic> _solve(
    Map<String, Map<String, dynamic>> nodes,
    Map<String, List<(String, _Edge)>> graph,
    Set<String> starts,
    Set<String> targets,
    String mode,
    String label, {
    required bool shaded,
  }) {
    final costs = {for (final start in starts) start: 0.0};
    final previous = <String, (String, _Edge)>{};
    final queue = _CostQueue();
    for (final start in starts.toList()..sort()) {
      queue.add(0, start);
    }

    String? found;
    while (!queue.isEmpty) {
      final (cost, node) = queue.removeFirst();
      if (cost != costs[node]) continue;
      if (targets.contains(node)) {
        found = node;
        break;
      }
      for (final (destination, edge) in graph[node] ?? const <(String, _Edge)>[]) {
        final updated =
            cost + edge.distanceMeters * (shaded ? 1 + edge.penalty : 1);
        if (updated < (costs[destination] ?? double.infinity)) {
          costs[destination] = updated;
          previous[destination] = (node, edge);
          queue.add(updated, destination);
        }
      }
    }
    if (found == null) {
      throw OfflineRoutingException(
          'No connected ${label.toLowerCase()} route to this building is available on permitted pathways.');
    }

    final edges = <_Edge>[];
    var cursor = found;
    while (previous.containsKey(cursor)) {
      final step = previous[cursor]!;
      cursor = step.$1;
      edges.add(step.$2);
    }
    final path = edges.reversed.toList();

    final routePoints = <List<double>>[nodes[cursor]!['position'] as List<double>];
    for (final edge in path) {
      for (final point in edge.points) {
        final last = routePoints.last;
        if (point[0] != last[0] || point[1] != last[1]) routePoints.add(point);
      }
    }

    return {
      'type': shaded ? 'comfortableShaded' : 'shortest',
      'mode': mode,
      'distanceMeters':
          path.fold<double>(0, (sum, edge) => sum + edge.distanceMeters),
      'estimatedMinutes':
          path.fold<double>(0, (sum, edge) => sum + edge.estimatedMinutes),
      'weightedCost': costs[found],
      'pathwayIds': path.map((edge) => edge.pathwayId).toList(),
      'pathPoints': routePoints,
      'startNodeId': cursor,
      'endNodeId': found,
      'startNodeName':
          nodes[cursor]!['name'] ?? nodes[cursor]!['node_name'] ?? 'Route starting point',
      'steps': path
          .map((edge) => {
                'instruction': 'Follow ${edge.name}',
                'distanceMeters': edge.distanceMeters,
                'coordinate': edge.points.first,
              })
          .toList(),
    };
  }
}
