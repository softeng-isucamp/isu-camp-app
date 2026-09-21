"""Walking graph routing. All weights are nonnegative; no database writes."""
import heapq
import math
import re

from app.utils.campus_data import coordinate

SHADE_PENALTIES = {"fully shaded": 0, "mostly shaded": .25,
                   "partial shade": .5, "unshaded": 1, "unknown": 1}


class RoutingError(ValueError):
    pass


def meters(a, b):
    lat1, lat2 = math.radians(a[0]), math.radians(b[0])
    dlat, dlng = lat2 - lat1, math.radians(b[1] - a[1])
    h = math.sin(dlat / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlng / 2) ** 2
    return 6371000 * 2 * math.asin(min(1, math.sqrt(h)))


def build_graph(nodes, pathways, modes, points):
    """The walking adjacency lists, derived from the campus tables alone.

    Split out of walking_routes so the result survives across requests: the
    network changes rarely, while origin and destination change every call.
    The return value is shared and read from several threads at once, so
    routes_for only ever reads it.
    """
    nodes = {str(n["node_id"]): dict(n, position=coordinate(n.get("latitude"), n.get("longitude")))
             for n in nodes if str(n.get("status", "")).lower() == "active"}
    nodes = {k: n for k, n in nodes.items() if n["position"] is not None}
    allowed = {str(m["pathway_id"]) for m in modes if str(m.get("mode", "")).lower() == "walking"}
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
                "estimatedMinutes": length / 80,
                "penalty": SHADE_PENALTIES.get(str(p.get("shade", "unknown")).strip().lower(), 1),
                "name": p.get("name") or "Campus pathway", "points": geometry}
        graph[a].append((b, edge))
        if direction == "twoway":
            graph[b].append((a, dict(edge, points=list(reversed(geometry)))))
    return nodes, graph


def routes_for(nodes, graph, request):
    """The shortest and the most shaded walking route for one request.

    Reads the shared graph from build_graph without mutating it.
    """
    if request.get("mode", "walking") != "walking":
        raise RoutingError("Routing is currently available for Walking only.")
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
        candidates = [k for k in graph if graph[k]]
        if pos is None or not candidates:
            raise RoutingError("No walking starting point is available.")
        nearest = min(candidates, key=lambda k: meters(pos, nodes[k]["position"]))
        if meters(pos, nodes[nearest]["position"]) > 200:
            raise RoutingError("No walking node within 200 m. Choose a campus building or the main gate.")
        starts = {nearest}

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
            raise RoutingError("No connected walking route to this building is available.")
        edges, cursor = [], found
        while cursor in previous:
            cursor, edge = previous[cursor]
            edges.append(edge)
        edges.reverse()
        route_points = [nodes[cursor]["position"]]
        for edge in edges:
            route_points.extend(p for p in edge["points"] if p != route_points[-1])
        return {"type": "comfortableShaded" if shaded else "shortest",
                "distanceMeters": sum(e["distanceMeters"] for e in edges),
                "estimatedMinutes": sum(e["estimatedMinutes"] for e in edges),
                "weightedCost": costs[found], "pathwayIds": [e["pathwayId"] for e in edges],
                "pathPoints": route_points, "startNodeId": cursor, "endNodeId": found,
                "startNodeName": nodes[cursor].get("name") or nodes[cursor].get("node_name") or "Walking node",
                "steps": [{"instruction": "Follow " + e["name"], "distanceMeters": e["distanceMeters"],
                           "coordinate": e["points"][0]} for e in edges]}
    return {"routes": [solve(False), solve(True)]}


def walking_routes(nodes, pathways, modes, points, request):
    """Build the graph and solve in one call, for callers holding raw rows."""
    return routes_for(*build_graph(nodes, pathways, modes, points), request)
