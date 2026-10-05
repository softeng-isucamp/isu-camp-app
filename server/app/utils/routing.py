"""Campus transport graph routing. All weights are nonnegative; no database writes."""
import heapq
import math
import re

from app.utils.campus_data import coordinate

SHADE_PENALTIES = {"fully shaded": 0, "mostly shaded": .25,
                   "partial shade": .5, "unshaded": 1, "unknown": 1}

# Nominal campus travel estimates in meters/minute, not live traffic speeds.
MODE_SPEEDS = {"walking": 80, "car": 350, "motorcycle": 450, "bicycle": 220}
MODE_LABELS = {"walking": "Walking", "car": "Car", "motorcycle": "Motorcycle", "bicycle": "Bicycle"}
MODE_ALIASES = {"walking": "walking", "walk": "walking", "pedestrian": "walking",
                "car": "car", "motorcycle": "motorcycle", "motorbike": "motorcycle",
                "motor": "motorcycle", "bicycle": "bicycle", "bike": "bicycle",
                "cycling": "bicycle", "vehicle": "vehicle"}


def pathway_allows_mode(value, mode):
    label = MODE_ALIASES.get(str(value or "").strip().lower())
    # The current admin dataset uses Vehicle as an umbrella for wheeled modes.
    # Specific car/motorcycle/bicycle labels remain specific when provided.
    return label == mode or (label == "vehicle" and mode in ("car", "motorcycle", "bicycle"))


class RoutingError(ValueError):
    pass


def meters(a, b):
    lat1, lat2 = math.radians(a[0]), math.radians(b[0])
    dlat, dlng = lat2 - lat1, math.radians(b[1] - a[1])
    h = math.sin(dlat / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlng / 2) ** 2
    return 6371000 * 2 * math.asin(min(1, math.sqrt(h)))


def project_on_path(position, geometry):
    """Return closest point and the remaining directed path from that point."""
    scale = math.cos(math.radians(position[0]))
    best = None
    for index, (a, b) in enumerate(zip(geometry, geometry[1:])):
        dx, dy = (b[1] - a[1]) * scale, b[0] - a[0]
        px, py = (position[1] - a[1]) * scale, position[0] - a[0]
        square = dx * dx + dy * dy
        fraction = max(0, min(1, (px * dx + py * dy) / square)) if square else 0
        point = (a[0] + dy * fraction, a[1] + (b[1] - a[1]) * fraction)
        distance = meters(position, point)
        if best is None or distance < best[0]:
            best = distance, point, [point, *geometry[index + 1:]]
    return best


def campus_routes(nodes, pathways, modes, points, request):
    mode = request.get("mode", "walking")
    if mode not in MODE_SPEEDS:
        raise RoutingError("Unsupported transport mode.")
    speed = MODE_SPEEDS[mode]
    label = MODE_LABELS[mode]
    nodes = {str(n["node_id"]): dict(n, position=coordinate(n.get("latitude"), n.get("longitude")))
             for n in nodes if str(n.get("status", "")).lower() == "active"}
    nodes = {k: n for k, n in nodes.items() if n["position"] is not None}
    allowed = {str(m["pathway_id"]) for m in modes if pathway_allows_mode(m.get("mode"), mode)}
    grouped = {}
    for p in points:
        if str(p.get("status", "")).lower() == "active":
            pos = coordinate(p.get("latitude"), p.get("longitude"))
            if pos is not None:
                grouped.setdefault(str(p["pathway_id"]), []).append((int(p["sequence_no"]), pos))
    graph = {k: [] for k in nodes}
    for p in pathways:
        pid = str(p["pathway_id"])
        a, b = str(p["source_node_id"]), str(p["destination_node_id"])
        # Direction labels may use spaces, underscores, or hyphens in the table.
        direction = re.sub(r"[\s_-]+", "", str(p.get("direction") or "").strip().lower())
        if (pid not in allowed or a not in nodes or b not in nodes or
                str(p.get("status", "")).lower() != "active" or
                direction not in ("oneway", "twoway")):
            continue
        start, end = nodes[a]["position"], nodes[b]["position"]
        shape = [pos for _, pos in sorted(grouped.get(pid, []), key=lambda item: item[0])]
        if shape and meters(start, shape[-1]) + meters(end, shape[0]) < meters(start, shape[0]) + meters(end, shape[-1]):
            shape.reverse()
        geometry = []
        for pos in [start, *shape, end]:
            if not geometry or pos != geometry[-1]:
                geometry.append(pos)
        length = sum(meters(x, y) for x, y in zip(geometry, geometry[1:]))
        if length <= 0:
            continue
        edge = {"pathwayId": pid, "distanceMeters": length,
                "estimatedMinutes": length / speed,
                "penalty": SHADE_PENALTIES.get(str(p.get("shade", "unknown")).strip().lower(), 1),
                "name": p.get("name") or "Campus pathway", "points": geometry}
        graph[a].append((b, edge))
        if direction == "twoway":
            graph[b].append((a, dict(edge, points=list(reversed(geometry)))))

    targets = {k for k, n in nodes.items() if n.get("building_id") is not None
               and str(n["building_id"]) == str(request["destinationBuildingId"])
               and str(n.get("node_type", "")).lower() == "entrance"}
    if not targets:
        raise RoutingError("This building has no active entrance linked to the routing network.")
    origin = request["origin"]
    kind = origin["type"]
    if kind == "campusLocation":
        starts = {k for k, n in nodes.items() if n.get("building_id") is not None
                  and str(n["building_id"]) == str(origin.get("buildingId"))
                  and str(n.get("node_type", "")).lower() == "entrance"}
        if not starts:
            raise RoutingError("The starting building has no active entrance linked to the routing network.")
    elif kind == "mainGate":
        starts = {k for k, n in nodes.items() if str(n.get("name") or "").strip().lower()
                  in ("gate", "main gate", "isu main gate")}
        if len(starts) != 1:
            raise RoutingError("The main gate could not be identified uniquely in the routing network.")
    else:
        pos = coordinate(origin.get("latitude"), origin.get("longitude"))
        candidates = [(source, dest, edge, project_on_path(pos, edge['points']))
                      for source in graph for dest, edge in graph[source]] if pos is not None else []
        if not candidates:
            raise RoutingError(f"No {label.lower()} starting point is available on permitted pathways.")
        _, _, nearest_edge, nearest = min(candidates, key=lambda item: item[3][0])
        if nearest[0] > 200:
            raise RoutingError(f"No permitted {label.lower()} pathway within 200 m. Choose a campus building or the main gate.")
        # Snap to a pathway interior without routing back to a distant node.
        # Only the directions already allowed by the database are connected.
        start_id = '__current_location__'
        nodes[start_id] = dict(position=nearest[1], name=nearest_edge['name'])
        graph[start_id] = []
        for _, dest, edge, projection in candidates:
            if edge['pathwayId'] != nearest_edge['pathwayId']:
                continue
            geometry = projection[2]
            length = sum(meters(a, b) for a, b in zip(geometry, geometry[1:]))
            graph[start_id].append((dest, dict(edge, points=geometry,
                distanceMeters=length, estimatedMinutes=length / speed)))
        starts = {start_id}

    def solve(shaded):
        costs = {k: 0.0 for k in starts}
        previous = {}
        queue = [(0.0, k) for k in sorted(starts)]
        heapq.heapify(queue)
        found = None
        while queue:
            cost, node = heapq.heappop(queue)
            if cost != costs[node]:
                continue
            if node in targets:
                found = node
                break
            for dest, edge in graph[node]:
                updated = cost + edge["distanceMeters"] * (1 + edge["penalty"] if shaded else 1)
                if updated < costs.get(dest, math.inf):
                    costs[dest] = updated
                    previous[dest] = (node, edge)
                    heapq.heappush(queue, (updated, dest))
        if found is None:
            raise RoutingError(f"No connected {label.lower()} route to this building is available on permitted pathways.")
        edges, cursor = [], found
        while cursor in previous:
            cursor, edge = previous[cursor]
            edges.append(edge)
        edges.reverse()
        route_points = [nodes[cursor]["position"]]
        for edge in edges:
            route_points.extend(p for p in edge["points"] if p != route_points[-1])
        return {"type": "comfortableShaded" if shaded else "shortest", "mode": mode,
                "distanceMeters": sum(e["distanceMeters"] for e in edges),
                "estimatedMinutes": sum(e["estimatedMinutes"] for e in edges),
                "weightedCost": costs[found], "pathwayIds": [e["pathwayId"] for e in edges],
                "pathPoints": route_points, "startNodeId": cursor, "endNodeId": found,
                "startNodeName": nodes[cursor].get("name") or nodes[cursor].get("node_name") or "Route starting point",
                "steps": [{"instruction": "Follow " + e["name"], "distanceMeters": e["distanceMeters"],
                           "coordinate": e["points"][0]} for e in edges]}
    return {"routes": [solve(False), solve(True)]}


def walking_routes(nodes, pathways, modes, points, request):
    """Compatibility entry point for existing callers."""
    return campus_routes(nodes, pathways, modes, points, request)
