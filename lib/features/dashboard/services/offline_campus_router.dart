import 'dart:collection';
import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../models/campus_models.dart';

/// Computes the same two walking choices as the campus API from a saved graph.
class OfflineCampusRouter {
  static List<List<LatLng>> mapPathways(Map<String, dynamic> graph) {
    final nodes = <String, LatLng>{};
    for (final node in _rows(graph, 'nodes')) {
      final point = _coordinate(node['latitude'], node['longitude']);
      if (_active(node['status']) && point != null) {
        nodes['${node['node_id']}'] = point;
      }
    }
    final allowed = _rows(graph, 'modes')
        .where((row) => '${row['mode']}'.toLowerCase() == 'walking')
        .map((row) => '${row['pathway_id']}').toSet();
    final pointsByPath = <String, List<MapEntry<int, LatLng>>>{};
    for (final point in _rows(graph, 'points')) {
      final coordinate = _coordinate(point['latitude'], point['longitude']);
      if (_active(point['status']) && coordinate != null) {
        pointsByPath.putIfAbsent('${point['pathway_id']}', () => []).add(
            MapEntry((point['sequence_no'] as num).toInt(), coordinate));
      }
    }
    final result = <List<LatLng>>[];
    for (final path in _rows(graph, 'pathways')) {
      final id = '${path['pathway_id']}';
      if (!allowed.contains(id) || !_active(path['status'])) continue;
      final start = nodes['${path['source_node_id']}'];
      final end = nodes['${path['destination_node_id']}'];
      if (start == null || end == null) continue;
      final middle = (pointsByPath[id] ?? <MapEntry<int, LatLng>>[])
        ..sort((a, b) => a.key.compareTo(b.key));
      result.add([start, ...middle.map((point) => point.value), end]);
    }
    return result;
  }

  static List<WalkingRoute> routes({
    required Map<String, dynamic> graph,
    required NavigationOrigin origin,
    required CampusBuilding destination,
  }) {
    final nodes = <String, Map<String, dynamic>>{};
    for (final raw in _rows(graph, 'nodes')) {
      final node = Map<String, dynamic>.from(raw);
      if (!_active(node['status'])) continue;
      final point = _coordinate(node['latitude'], node['longitude']);
      if (point != null) {
        node['_point'] = point;
        nodes['${node['node_id']}'] = node;
      }
    }

    final allowed = _rows(graph, 'modes')
        .where((row) => '${row['mode']}'.toLowerCase() == 'walking')
        .map((row) => '${row['pathway_id']}')
        .toSet();
    final shapeByPath = <String, List<MapEntry<int, LatLng>>>{};
    for (final point in _rows(graph, 'points')) {
      if (!_active(point['status'])) continue;
      final coordinate = _coordinate(point['latitude'], point['longitude']);
      if (coordinate != null) {
        shapeByPath.putIfAbsent('${point['pathway_id']}', () => []).add(
            MapEntry((point['sequence_no'] as num).toInt(), coordinate));
      }
    }

    final edges = <String, List<_Arc>>{for (final id in nodes.keys) id: []};
    for (final path in _rows(graph, 'pathways')) {
      final id = '${path['pathway_id']}';
      final a = '${path['source_node_id']}';
      final b = '${path['destination_node_id']}';
      final direction = '${path['direction'] ?? ''}'
          .toLowerCase()
          .replaceAll(RegExp(r'[\s_-]+'), '');
      if (!allowed.contains(id) ||
          !nodes.containsKey(a) ||
          !nodes.containsKey(b) ||
          !_active(path['status']) ||
          (direction != 'oneway' && direction != 'twoway')) continue;
      final start = nodes[a]!['_point'] as LatLng;
      final end = nodes[b]!['_point'] as LatLng;
      final shape = (shapeByPath[id] ?? <MapEntry<int, LatLng>>[])
        ..sort((x, y) => x.key.compareTo(y.key));
      var middle = shape.map((entry) => entry.value).toList();
      if (middle.isNotEmpty &&
          _meters(start, middle.last) + _meters(end, middle.first) <
              _meters(start, middle.first) + _meters(end, middle.last)) {
        middle = middle.reversed.toList();
      }
      final points = <LatLng>[];
      for (final point in [start, ...middle, end]) {
        if (points.isEmpty || points.last != point) points.add(point);
      }
      final distance = _lineLength(points);
      if (distance <= 0) continue;
      final shade = '${path['shade'] ?? 'unknown'}'.trim().toLowerCase();
      final penalty = switch (shade) {
        'fully shaded' => 0.0,
        'mostly shaded' => .25,
        'partial shade' => .5,
        _ => 1.0,
      };
      final edge = _Edge(
        id: id,
        name: '${path['name'] ?? 'Campus pathway'}',
        distance: distance,
        penalty: penalty,
        points: points,
      );
      edges[a]!.add(_Arc(b, edge));
      if (direction == 'twoway') {
        edges[b]!.add(_Arc(a, edge.reversed()));
      }
    }

    final targets = nodes.entries
        .where((entry) =>
            '${entry.value['building_id']}' == destination.id &&
            '${entry.value['node_type']}'.toLowerCase() == 'entrance')
        .map((entry) => entry.key)
        .toSet();
    if (targets.isEmpty) throw const OfflineRouteException(
        'This destination has no saved walking entrance. Connect to update the campus pack.');

    Set<String> starts;
    switch (origin.type) {
      case NavigationOriginType.campusLocation:
        starts = nodes.entries
            .where((entry) =>
                '${entry.value['building_id']}' == origin.id &&
                '${entry.value['node_type']}'.toLowerCase() == 'entrance')
            .map((entry) => entry.key)
            .toSet();
        break;
      case NavigationOriginType.mainGate:
        starts = nodes.entries
            .where((entry) => const {'gate', 'main gate', 'isu main gate'}
                .contains('${entry.value['name'] ?? ''}'.trim().toLowerCase()))
            .map((entry) => entry.key)
            .toSet();
        if (starts.length != 1) {
          throw const OfflineRouteException(
              'The saved campus graph does not identify one main gate. Connect and update the campus pack.');
        }
        break;
      default:
        final candidates = edges.entries
            .where((entry) => entry.value.isNotEmpty)
            .map((entry) => entry.key)
            .toList();
        if (candidates.isEmpty) throw const OfflineRouteException(
            'The saved campus pack has no walking paths. Connect and update it.');
        candidates.sort((a, b) => _meters(origin.coordinate,
                nodes[a]!['_point'] as LatLng)
            .compareTo(_meters(origin.coordinate, nodes[b]!['_point'] as LatLng)));
        if (_meters(origin.coordinate, nodes[candidates.first]!['_point'] as LatLng) > 200) {
          throw const OfflineRouteException(
              'No saved walking path is within 200 m. Choose a campus building or the main gate.');
        }
        starts = {candidates.first};
    }
    if (starts.isEmpty) throw const OfflineRouteException(
        'This starting point has no saved walking entrance. Connect to update the campus pack.');
    return [
      _solve(nodes, edges, starts, targets, shaded: false),
      _solve(nodes, edges, starts, targets, shaded: true),
    ];
  }

  static WalkingRoute _solve(
      Map<String, Map<String, dynamic>> nodes,
      Map<String, List<_Arc>> edges,
      Set<String> starts,
      Set<String> targets,
      {required bool shaded}) {
    final costs = <String, double>{for (final node in starts) node: 0};
    final previous = <String, (String, _Edge)>{};
    final queue = SplayTreeMap<double, Queue<String>>();
    void add(String node, double cost) =>
        queue.putIfAbsent(cost, Queue<String>.new).add(node);
    for (final node in starts) add(node, 0);
    String? found;
    while (queue.isNotEmpty) {
      final first = queue.firstKey()!;
      final node = queue[first]!.removeFirst();
      if (queue[first]!.isEmpty) queue.remove(first);
      if (costs[node] != first) continue;
      if (targets.contains(node)) { found = node; break; }
      for (final arc in edges[node] ?? const <_Arc>[]) {
        final cost = first + arc.edge.distance *
            (shaded ? 1 + arc.edge.penalty : 1);
        if (cost < (costs[arc.to] ?? double.infinity)) {
          costs[arc.to] = cost;
          previous[arc.to] = (node, arc.edge);
          add(arc.to, cost);
        }
      }
    }
    if (found == null) throw const OfflineRouteException(
        'No connected saved walking route reaches this destination. Connect and update the campus pack.');
    final pathEdges = <_Edge>[];
    var cursor = found;
    while (previous.containsKey(cursor)) {
      final link = previous[cursor]!;
      pathEdges.add(link.$2);
      cursor = link.$1;
    }
    final orderedEdges = pathEdges.reversed.toList();
    final points = <LatLng>[nodes[cursor]!['_point'] as LatLng];
    for (final edge in orderedEdges) {
      points.addAll(edge.points.where((point) => point != points.last));
    }
    final distance = orderedEdges.fold<double>(0, (sum, edge) => sum + edge.distance);
    final json = <String, dynamic>{
      'type': shaded ? 'comfortableShaded' : 'shortest',
      'distanceMeters': distance,
      'estimatedMinutes': distance / 80,
      'startNodeName': nodes[cursor]!['name'] ?? 'Walking node',
      'pathPoints': points.map((point) => [point.latitude, point.longitude]).toList(),
      'steps': orderedEdges.map((edge) => {
        'instruction': 'Follow ${edge.name}',
        'distanceMeters': edge.distance,
        'coordinate': [edge.points.first.latitude, edge.points.first.longitude],
      }).toList(),
    };
    return WalkingRoute.fromJson(json);
  }

  static List<Map<String, dynamic>> _rows(Map<String, dynamic> graph, String key) =>
      ((graph[key] as List?) ?? const [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();

  static bool _active(dynamic value) =>
      '${value ?? ''}'.trim().toLowerCase() == 'active';

  static LatLng? _coordinate(dynamic latitude, dynamic longitude) {
    if (latitude is! num || longitude is! num) return null;
    if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) return null;
    return LatLng(latitude.toDouble(), longitude.toDouble());
  }

  static double _lineLength(List<LatLng> points) =>
      [for (var i = 1; i < points.length; i++) _meters(points[i - 1], points[i])]
          .fold<double>(0, (sum, length) => sum + length);

  static double _meters(LatLng a, LatLng b) {
    final lat1 = a.latitude * math.pi / 180;
    final lat2 = b.latitude * math.pi / 180;
    final dlat = lat2 - lat1;
    final dlng = (b.longitude - a.longitude) * math.pi / 180;
    final h = math.pow(math.sin(dlat / 2), 2) +
        math.cos(lat1) * math.cos(lat2) * math.pow(math.sin(dlng / 2), 2);
    return 6371000 * 2 * math.asin(math.min(1, math.sqrt(h)));
  }
}

class OfflineRouteException implements Exception {
  final String message;
  const OfflineRouteException(this.message);
  @override
  String toString() => message;
}

class _Arc {
  final String to;
  final _Edge edge;
  const _Arc(this.to, this.edge);
}

class _Edge {
  final String id;
  final String name;
  final double distance;
  final double penalty;
  final List<LatLng> points;
  const _Edge({required this.id, required this.name, required this.distance,
    required this.penalty, required this.points});
  _Edge reversed() => _Edge(id: id, name: name, distance: distance,
      penalty: penalty, points: points.reversed.toList());
}
