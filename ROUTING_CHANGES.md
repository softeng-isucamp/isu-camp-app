# Campus navigation changes

This change connects the existing starting-point and destination flow to Supabase. No database records or schema were changed.

## Files

- `server/app/utils/routing.py`: directed transport graph, pathway permissions, current-location snapping and two Dijkstra computations.
- `server/app/routes/campus.py`: new `POST /campus/routes`, validated input, paginated reads and error responses. Existing buildings endpoint remains.
- `lib/features/dashboard/services/campus_service.dart`: calls the new endpoint with origin type/coordinates, optional origin building ID and destination building ID.
- `lib/features/dashboard/models/campus_models.dart`: `WalkingRoute` response model with actual distance, estimated minutes, points and starting-node name.
- `lib/features/dashboard/widgets/navigation_sheets.dart`: mode icons fetch routes for car, motorcycle, bicycle or walking. Route cards have loading, retry and no-route states. Older requests cannot replace a newer selected mode.
- `lib/features/dashboard/screens/map_view_screen.dart`: selected route is passed to preview/HUD; map draws returned pathway points, replacing the mock curve. The start marker uses the resolved network node.
- `server/tests/test_routing.py`: routing algorithm and data-rule tests.
- `test/features/dashboard/widgets/walking_routes_test.dart`: route selection, metrics, unavailable mode and no-route tests.
- `test/features/dashboard/map_view_screen_test.dart`: updates an outdated code-label expectation to match the user's existing building-name label.

## Data and rules

Tables: `route_node`, `pathway`, `pathway_allowed_mode`, `path_point`.

Only active nodes/pathways/points and pathways permitting the selected mode are used. The current database labels are `Walking` and `Vehicle`; `Vehicle` permits car, motorcycle and bicycle. Specific transport labels, when present, permit only that mode. Walking-only paths are excluded for wheeled modes. One-way adds a source-to-destination edge; two-way also adds a reverse edge with reversed geometry. Unknown directions are excluded. Nodes without `building_id` remain valid junctions.

Shortest weight: computed pathway length from route nodes and ordered path points.

Shaded weight: computed pathway length multiplied by `(1 + penalty)` using `pathway.shade`:

| Shade | Penalty |
|---|---:|
| Fully Shaded | 0 |
| Mostly Shaded | 0.25 |
| Partial Shade | 0.50 |
| Unshaded | 1 |
| Unknown, null or unrecognized | 1 |

Actual distance is returned separately from weighted cost. Distance is calculated from ordered geometry. Nominal ETA speeds in meters/minute are walking 80, car 350, motorcycle 450 and bicycle 220; these are estimates without live traffic. The database `distance_m` and `estimated_minutes` values are not read for routing.

Building starts/destinations use active entrance nodes associated through `building_id`. Multiple entrances are considered in the graph search. Missing or disconnected entrances produce an explicit no-route response.

Main Gate resolves a uniquely named active node (`Gate`, `Main Gate`, or `ISU Main Gate`). Current Location and Campus Center snap to the nearest permitted pathway within 200 meters, including its interior, while respecting direction. The mapped route starts at that point; guidance asks the user to join the path when necessary.

Points are sorted by `sequence_no` and oriented source-to-destination. When a pathway has no points, its endpoint coordinates form its geometry. Both alternatives may be identical.

## Verified against live data

- Read-only audit on October 4, 2026: from Main Gate, walking reaches 13 of 15 buildings with entrance nodes.
- Car, motorcycle and bicycle each reach 2 of 15 from Main Gate under the current `Vehicle` permissions. The others require connected vehicle pathways in the admin data. No database records were changed.

## Scope limits

All four modes support live route progress, remaining distance and ETA, junction guidance, rerouting after sustained deviation, GPS signal/accuracy status, retry and automatic arrival after two accurate nearby fixes. The arrival simulator has been removed. GPS integration tests cover each mode, route failures and recovery. Routes end at mapped building entrances; indoor room routing and live traffic are not provided. Physical campus verification is still needed.

Restart FastAPI and fully restart Flutter after applying these changes. No migrations are required.
