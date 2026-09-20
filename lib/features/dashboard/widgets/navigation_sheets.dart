import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import '../models/campus_models.dart';
import '../services/campus_service.dart';

IconData routeModeIcon(TransportMode mode) {
  switch (mode) {
    case TransportMode.car:
      return Icons.directions_car;
    case TransportMode.motorcycle:
      return Icons.two_wheeler;
    case TransportMode.bicycle:
      return Icons.pedal_bike;
    case TransportMode.walking:
      return Icons.directions_walk;
  }
}

IconData routeInstructionIcon(String instruction) {
  final normalized = instruction.toLowerCase();
  if (normalized.contains('left')) return Icons.turn_left;
  if (normalized.contains('right')) return Icons.turn_right;
  if (normalized.contains('arrive') || normalized.contains('destination')) {
    return Icons.location_on;
  }
  return Icons.arrow_upward;
}

// Frontend-only route estimate. Replace this helper with backend route values.
class RouteMetricsHelper {
  static int getBaseDistance(
    NavigationOrigin origin,
    CampusBuilding building,
  ) {
    final meters = const Distance().as(
      LengthUnit.Meter,
      origin.coordinate,
      building.coordinate,
    );
    return meters < 30 ? 30 : meters.round();
  }

  static String getDistanceString(
    NavigationOrigin origin,
    CampusBuilding building,
    RouteType routeType,
    TransportMode mode,
  ) {
    int base = getBaseDistance(origin, building);
    if (routeType == RouteType.comfortableShaded) {
      base = (base * 1.18).round();
    }
    if (mode == TransportMode.car) {
      base = (base * 1.25).round();
    } else if (mode == TransportMode.motorcycle) {
      base = (base * 1.15).round();
    }
    return '${base}m';
  }

  static String getHeadingInstruction(
    NavigationOrigin origin,
    CampusBuilding building,
  ) {
    final latitudeChange =
        building.coordinate.latitude - origin.coordinate.latitude;
    final longitudeChange =
        building.coordinate.longitude - origin.coordinate.longitude;
    final vertical = latitudeChange >= 0 ? 'North' : 'South';
    final horizontal = longitudeChange >= 0 ? 'east' : 'west';

    if (latitudeChange.abs() > longitudeChange.abs() * 2) {
      return 'Head $vertical';
    }
    if (longitudeChange.abs() > latitudeChange.abs() * 2) {
      return 'Head ${horizontal[0].toUpperCase()}${horizontal.substring(1)}';
    }
    return 'Head $vertical$horizontal';
  }

  static String getTimeString(
    NavigationOrigin origin,
    CampusBuilding building,
    RouteType routeType,
    TransportMode mode,
  ) {
    int base = getBaseDistance(origin, building);
    if (routeType == RouteType.comfortableShaded) {
      base = (base * 1.18).round();
    }

    int minutes;
    switch (mode) {
      case TransportMode.walking:
        minutes = (base / 80).ceil();
        return '$minutes mins';
      case TransportMode.bicycle:
        minutes = (base / 220).ceil();
        return '${minutes < 1 ? 1 : minutes} mins';
      case TransportMode.motorcycle:
        minutes = (base / 450).ceil();
        return '${minutes < 1 ? 1 : minutes} mins';
      case TransportMode.car:
        minutes = (base / 350).ceil();
        return '${minutes < 1 ? 1 : minutes} mins';
    }
  }

  static String getArrivalTime(
    NavigationOrigin origin,
    CampusBuilding building,
    RouteType routeType,
    TransportMode mode,
  ) {
    int base = getBaseDistance(origin, building);
    if (routeType == RouteType.comfortableShaded) {
      base = (base * 1.18).round();
    }

    int minutes;
    switch (mode) {
      case TransportMode.walking:
        minutes = (base / 80).ceil();
        break;
      case TransportMode.bicycle:
        minutes = (base / 220).ceil();
        break;
      case TransportMode.motorcycle:
        minutes = (base / 450).ceil();
        break;
      case TransportMode.car:
        minutes = (base / 350).ceil();
        break;
    }
    final now = DateTime.now().add(Duration(minutes: minutes));
    final hour =
        now.hour > 12 ? now.hour - 12 : (now.hour == 0 ? 12 : now.hour);
    final minuteStr = now.minute.toString().padLeft(2, '0');
    final period = now.hour >= 12 ? 'pm' : 'am';
    return '$hour:$minuteStr $period';
  }
}

// =========================================================================
// 1. BUILDING DETAILS MODAL SHEET (Design Mockup Image 5)
// =========================================================================
class BuildingDetailsSheet extends StatelessWidget {
  final CampusBuilding building;
  final VoidCallback onDirectionsTap;
  final ValueChanged<CampusRoom> onRoomDirectionsTap;
  final VoidCallback? onClose;

  const BuildingDetailsSheet({
    super.key,
    required this.building,
    required this.onDirectionsTap,
    required this.onRoomDirectionsTap,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.70,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag Handle & Top Header Row
            Center(
              child: Container(
                width: 44,
                height: 4,
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'BUILDING DETAILS',
                  style: GoogleFonts.montserrat(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade600,
                    letterSpacing: 0.5,
                  ),
                ),
                if (onClose != null)
                  GestureDetector(
                    onTap: onClose,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close,
                        size: 18,
                        color: Colors.black54,
                      ),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 10),

            // Building Image with rounded corners
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                height: 160,
                width: double.infinity,
                color: Colors.grey.shade200,
                child: Image.asset(
                  building.imageUrl ?? 'assets/images/Appdev_background1.png',
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Center(
                    child: Icon(
                      building.isParking ? Icons.local_parking : Icons.school,
                      size: 54,
                      color: const Color(0xFF0F751B),
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 14),

            // Title & Subtitle + Green "DIRECTIONS" Button Row
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        building.name,
                        style: GoogleFonts.montserrat(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF0F4D20),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        building.category,
                        style: GoogleFonts.montserrat(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: onDirectionsTap,
                  icon: const Icon(Icons.directions,
                      size: 16, color: Colors.white),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F5A28),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 11,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 2,
                  ),
                  label: Text(
                    'DIRECTIONS',
                    style: GoogleFonts.montserrat(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),

            if (building.description.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                building.description,
                style: GoogleFonts.montserrat(
                  fontSize: 12,
                  color: Colors.grey.shade700,
                  height: 1.4,
                ),
              ),
            ],

            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 14),

            // Rooms & Laboratories Section (Scrollable)
            Row(
              children: [
                const Icon(
                  Icons.meeting_room_outlined,
                  size: 18,
                  color: Color(0xFF0F5A28),
                ),
                const SizedBox(width: 8),
                Text(
                  'Rooms & Facilities (${building.rooms.length})',
                  style: GoogleFonts.montserrat(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF0F4D20),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            if (building.rooms.isNotEmpty)
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: building.rooms.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final room = building.rooms[index];
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7FAF8),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFF0F751B).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            room.icon,
                            color: const Color(0xFF0F751B),
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                room.title,
                                style: GoogleFonts.montserrat(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                room.floor,
                                style: GoogleFonts.montserrat(
                                  fontSize: 11,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFECC700)
                                    .withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                room.category.name.toUpperCase(),
                                style: GoogleFonts.montserrat(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.brown.shade800,
                                ),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () => onRoomDirectionsTap(room),
                              icon: const Icon(Icons.directions, size: 16),
                              label: const Text('Get directions'),
                              style: TextButton.styleFrom(
                                foregroundColor: const Color(0xFF0F5A28),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                visualDensity: VisualDensity.compact,
                                textStyle: GoogleFonts.montserrat(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Text(
                  'No interior rooms or offices in this facility.',
                  style: GoogleFonts.montserrat(
                    fontSize: 11.5,
                    color: Colors.grey.shade600,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// =========================================================================
// 2. CHOOSE STARTING POINT
// =========================================================================
class ChooseStartingPointSheet extends StatefulWidget {
  final CampusBuilding destination;
  final CampusRoom? destinationRoom;
  final List<NavigationOrigin> origins;
  final NavigationOrigin selectedOrigin;
  final bool hasSelectedOrigin;
  final bool isLocating;
  final String? locationStatus;
  final bool isCurrentLocationInsideCampus;
  final Future<void> Function() onUseCurrentLocation;
  final ValueChanged<NavigationOrigin> onOriginSelected;
  final VoidCallback onBack;
  final VoidCallback onCancel;
  final VoidCallback onContinue;

  const ChooseStartingPointSheet({
    super.key,
    required this.destination,
    this.destinationRoom,
    required this.origins,
    required this.selectedOrigin,
    required this.hasSelectedOrigin,
    required this.isLocating,
    required this.locationStatus,
    required this.isCurrentLocationInsideCampus,
    required this.onUseCurrentLocation,
    required this.onOriginSelected,
    required this.onBack,
    required this.onCancel,
    required this.onContinue,
  });

  @override
  State<ChooseStartingPointSheet> createState() =>
      _ChooseStartingPointSheetState();
}

class _ChooseStartingPointSheetState extends State<ChooseStartingPointSheet> {
  bool _showBuildings = false;
  bool _attemptedCurrentLocation = false;

  List<NavigationOrigin> get _buildings => widget.origins
      .where((origin) => origin.type == NavigationOriginType.campusLocation)
      .toList();

  Widget _optionTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool selected = false,
    String? subtitle,
    bool showError = false,
    Widget? trailing,
  }) {
    return Material(
      color: selected ? const Color(0xFFECFDF3) : const Color(0xFFF8FAF9),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: showError
                  ? Colors.red.shade400
                  : selected
                      ? const Color(0xFF0F751B)
                      : Colors.grey.shade200,
              width: selected || showError ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color:
                    showError ? Colors.red.shade600 : const Color(0xFF0F751B),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: GoogleFonts.montserrat(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: GoogleFonts.montserrat(
                          fontSize: 10.5,
                          color: showError
                              ? Colors.red.shade700
                              : Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              trailing ??
                  Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: selected
                        ? const Color(0xFF0F751B)
                        : Colors.grey.shade400,
                  ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.72,
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 44,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            children: [
              TextButton.icon(
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back, size: 18),
                label: const Text('Back'),
              ),
              const Spacer(),
              TextButton(
                onPressed: widget.onCancel,
                child: const Text('Cancel'),
              ),
            ],
          ),
          Text(
            'CHOOSE STARTING POINT',
            style: GoogleFonts.montserrat(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: const Color(0xFF0B351E),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.destinationRoom == null
                ? 'Going to ${widget.destination.name}'
                : 'Going to ${widget.destinationRoom!.title} '
                    '(${widget.destinationRoom!.floor}) via '
                    '${widget.destination.name} entrance',
            style: GoogleFonts.montserrat(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _optionTile(
                  icon: widget.isLocating ? Icons.gps_fixed : Icons.my_location,
                  label: 'Use My Current Location',
                  selected: widget.hasSelectedOrigin &&
                      widget.selectedOrigin.type ==
                          NavigationOriginType.currentLocation,
                  showError: _attemptedCurrentLocation &&
                      !widget.isLocating &&
                      !widget.isCurrentLocationInsideCampus,
                  subtitle: widget.isLocating
                      ? 'Detecting your location...'
                      : _attemptedCurrentLocation &&
                              widget.locationStatus != null
                          ? widget.locationStatus
                          : 'Available only while you are inside ISU Echague.',
                  onTap: () async {
                    setState(() {
                      _attemptedCurrentLocation = true;
                      _showBuildings = false;
                    });
                    await widget.onUseCurrentLocation();
                  },
                ),
                const SizedBox(height: 8),
                _optionTile(
                  icon: Icons.apartment,
                  label: 'Others',
                  subtitle: 'Choose another campus building.',
                  onTap: () => setState(() => _showBuildings = !_showBuildings),
                  trailing: Icon(
                    _showBuildings ? Icons.expand_less : Icons.expand_more,
                    color: const Color(0xFF0F751B),
                  ),
                ),
                if (_showBuildings) ...[
                  const SizedBox(height: 8),
                  if (_buildings.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'No other campus buildings are available.',
                        style: GoogleFonts.montserrat(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    )
                  else
                    for (var index = 0; index < _buildings.length; index++) ...[
                      if (index > 0) const SizedBox(height: 8),
                      _optionTile(
                        icon: Icons.location_on_outlined,
                        label: _buildings[index].label,
                        selected: widget.hasSelectedOrigin &&
                            widget.selectedOrigin.id == _buildings[index].id,
                        onTap: () {
                          widget.onOriginSelected(_buildings[index]);
                          setState(() => _showBuildings = false);
                        },
                      ),
                    ],
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: widget.hasSelectedOrigin ? widget.onContinue : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F5A28),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                'Continue to Route Options',
                style: GoogleFonts.montserrat(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =========================================================================
// 3. CHOOSE ROUTE MODAL SHEET (Design Mockup Images 1 & 3)
// =========================================================================
class ChooseRouteSheet extends StatefulWidget {
  final CampusBuilding destination;
  final CampusRoom? destinationRoom;
  final NavigationOrigin origin;
  final RouteType initialRouteType;
  final TransportMode initialTransportMode;
  final VoidCallback onBack;
  final VoidCallback onCancel;
  final ValueChanged<TransportMode>? onTransportModeChanged;
  final Function(WalkingRoute route, TransportMode selectedMode) onViewRoute;

  const ChooseRouteSheet({
    super.key,
    required this.destination,
    this.destinationRoom,
    required this.origin,
    this.initialRouteType = RouteType.comfortableShaded,
    this.initialTransportMode = TransportMode.walking,
    required this.onBack,
    required this.onCancel,
    this.onTransportModeChanged,
    required this.onViewRoute,
  });

  @override
  State<ChooseRouteSheet> createState() => _ChooseRouteSheetState();
}

class _ChooseRouteSheetState extends State<ChooseRouteSheet> {
  late TransportMode _selectedMode;
  late RouteType _selectedRoute;
  List<WalkingRoute> _routes = [];
  bool _loading = true;
  String? _error;

  Future<void> _loadRoutes() async {
    setState(() {
      _loading = true;
      _error = null;
      _routes = [];
    });
    try {
      final routes =
          await CampusService.fetchRoutes(widget.origin, widget.destination);
      if (!mounted) return;
      setState(() {
        _routes = routes;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _selectedMode = widget.initialTransportMode;
    _selectedRoute = widget.initialRouteType;
    _loadRoutes();
  }

  @override
  Widget build(BuildContext context) {
    final shortest =
        _routes.where((r) => r.type == RouteType.shortest).firstOrNull;
    final shaded =
        _routes.where((r) => r.type == RouteType.comfortableShaded).firstOrNull;
    final shortestDist = shortest?.distance ?? '—';
    final shortestTime = shortest?.time ?? '—';
    final comfortableDist = shaded?.distance ?? '—';
    final comfortableTime = shaded?.time ?? '—';
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFE5E7EB),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top Dark Green Header Box: Route Modes & Origin/Destination Box
          Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
            decoration: const BoxDecoration(
              color: Color(0xFF0B351E),
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Transport Mode Selector Icons
                Row(
                  children: [
                    Text(
                      'Route Modes',
                      style: GoogleFonts.montserrat(
                        fontSize: 11.5,
                        color: Colors.white70,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 14),
                    _buildModeIcon(TransportMode.car),
                    const SizedBox(width: 12),
                    _buildModeIcon(TransportMode.motorcycle),
                    const SizedBox(width: 12),
                    _buildModeIcon(TransportMode.bicycle),
                    const SizedBox(width: 12),
                    _buildModeIcon(TransportMode.walking),
                  ],
                ),

                const SizedBox(height: 14),

                // Origin & Destination Container
                Row(
                  children: [
                    Column(
                      children: [
                        Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0xFF22C55E),
                              width: 3.5,
                            ),
                          ),
                        ),
                        Container(
                          width: 2,
                          height: 28,
                          color: Colors.white38,
                        ),
                        const Icon(
                          Icons.location_on,
                          color: Colors.grey,
                          size: 18,
                        ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        children: [
                          Container(
                            height: 36,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            alignment: Alignment.centerLeft,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  widget.origin.label,
                                  style: GoogleFonts.montserrat(
                                    fontSize: 13,
                                    fontStyle: FontStyle.italic,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                                const Icon(
                                  Icons.chevron_right,
                                  size: 18,
                                  color: Colors.grey,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            height: 36,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            alignment: Alignment.centerLeft,
                            child: Text(
                              widget.destination.name,
                              style: GoogleFonts.montserrat(
                                fontSize: 13,
                                fontStyle: FontStyle.italic,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Bottom Content: CHOOSE ROUTE Options
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: widget.onBack,
                      child: Row(
                        children: [
                          const Icon(
                            Icons.arrow_back,
                            size: 18,
                            color: Color(0xFF0F4D20),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Back',
                            style: GoogleFonts.montserrat(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF0F4D20),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: widget.onCancel,
                      child: const Text('Cancel'),
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                Text(
                  'CHOOSE ROUTE',
                  style: GoogleFonts.montserrat(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.6,
                    color: const Color(0xFF0B351E),
                  ),
                ),

                if (widget.destinationRoom != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${widget.destinationRoom!.title} • ${widget.destinationRoom!.floor}. '
                    'Mapped route ends at the building entrance.',
                    style: GoogleFonts.montserrat(
                      fontSize: 11,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
                const SizedBox(height: 16),

                if (_selectedMode != TransportMode.walking)
                  const Text('Routing is currently available for Walking only.')
                else if (_loading)
                  const Center(child: CircularProgressIndicator())
                else if (_error != null) ...[
                  Text(_error!),
                  TextButton(
                      onPressed: _loadRoutes, child: const Text('Retry')),
                ],
                if (_selectedMode == TransportMode.walking &&
                    !_loading &&
                    _error == null) ...[
                  Text(
                      'Route starts at ${shortest?.startNodeName ?? "walking node"}. Distance is along the mapped paths.'),
                  // Option 1: Shortest Route Card
                  _buildRouteCard(
                    type: RouteType.shortest,
                    title: 'Shortest Route',
                    subtitle: 'Most Direct Path',
                    distance: shortestDist,
                    walkTime: shortestTime,
                    icon: Icons.bolt,
                    iconColor: const Color(0xFFECC700),
                  ),

                  const SizedBox(height: 12),

                  // Option 2: Shaded Path Card (Shaded)
                  _buildRouteCard(
                    type: RouteType.comfortableShaded,
                    title: 'Shaded Path',
                    subtitle: 'Prefers shaded pathways',
                    distance: comfortableDist,
                    walkTime: comfortableTime,
                    icon: Icons.cloud_outlined,
                    iconColor: const Color(0xFF0F5A28),
                  ),

                  const SizedBox(height: 20),
                ], // Walking route cards
                // "View Route" Button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _selectedMode != TransportMode.walking ||
                            _loading ||
                            _error != null ||
                            _routes.isEmpty
                        ? null
                        : () => widget.onViewRoute(
                            _routes.firstWhere((r) => r.type == _selectedRoute),
                            _selectedMode),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F5A28),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 2,
                    ),
                    child: Text(
                      'View Route',
                      style: GoogleFonts.montserrat(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeIcon(TransportMode mode) {
    final isSelected = _selectedMode == mode;
    return GestureDetector(
      onTap: () {
        setState(() => _selectedMode = mode);
        widget.onTransportModeChanged?.call(mode);
      },
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white24 : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(
          routeModeIcon(mode),
          color: isSelected ? Colors.white : Colors.white60,
          size: 20,
        ),
      ),
    );
  }

  Widget _buildRouteCard({
    required RouteType type,
    required String title,
    required String subtitle,
    required String distance,
    required String walkTime,
    required IconData icon,
    required Color iconColor,
  }) {
    final isSelected = _selectedRoute == type;

    return GestureDetector(
      onTap: () => setState(() => _selectedRoute = type),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? const Color(0xFF1B62D4) : Colors.transparent,
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: iconColor, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.montserrat(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: GoogleFonts.montserrat(
                          fontSize: 11.5,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFF1B62D4)
                          : Colors.grey.shade400,
                      width: 2,
                    ),
                  ),
                  child: isSelected
                      ? Center(
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0xFF1B62D4),
                            ),
                          ),
                        )
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  'Distance: ',
                  style: GoogleFonts.montserrat(
                    fontSize: 11.5,
                    color: Colors.grey.shade700,
                  ),
                ),
                Text(
                  distance,
                  style: GoogleFonts.montserrat(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(width: 18),
                Text(
                  'Est. Time: ',
                  style: GoogleFonts.montserrat(
                    fontSize: 11.5,
                    color: Colors.grey.shade700,
                  ),
                ),
                Text(
                  walkTime,
                  style: GoogleFonts.montserrat(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// =========================================================================
// 3. ROUTE DETAILS MODAL SHEET (Design Mockup Image 4)
// =========================================================================
class RouteDetailsSheet extends StatelessWidget {
  final CampusBuilding destination;
  final CampusRoom? destinationRoom;
  final WalkingRoute route;
  final NavigationOrigin origin;
  final RouteType selectedRouteType;
  final TransportMode selectedTransportMode;
  final VoidCallback onBack;
  final VoidCallback onCancel;
  final VoidCallback onPreviewRoute;
  final VoidCallback onStartNavigation;

  const RouteDetailsSheet({
    super.key,
    required this.route,
    required this.destination,
    this.destinationRoom,
    required this.origin,
    required this.selectedRouteType,
    this.selectedTransportMode = TransportMode.walking,
    required this.onBack,
    required this.onCancel,
    required this.onPreviewRoute,
    required this.onStartNavigation,
  });

  @override
  Widget build(BuildContext context) {
    final isShortest = selectedRouteType == RouteType.shortest;
    final title = isShortest ? 'Shortest Route' : 'Shaded Path';
    final subtitle =
        isShortest ? 'Most Direct Path' : 'Prefers shaded pathways';

    final distance = route.distance;
    final estTime = route.time;
    final arrivalTime = route.arrivalTime;

    final icon = isShortest ? Icons.bolt : Icons.cloud_outlined;
    final iconColor =
        isShortest ? const Color(0xFFECC700) : const Color(0xFF0F5A28);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: onBack,
              child: Row(
                children: [
                  const Icon(
                    Icons.arrow_back,
                    size: 18,
                    color: Color(0xFF0F4D20),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Back',
                    style: GoogleFonts.montserrat(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF0F4D20),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            Text(
              'ROUTE DETAILS',
              style: GoogleFonts.montserrat(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.6,
                color: const Color(0xFF0B351E),
              ),
            ),

            if (destinationRoom != null) ...[
              const SizedBox(height: 8),
              Text(
                '${destinationRoom!.title} • ${destinationRoom!.floor}. '
                'Walking route ends at ${destination.name} entrance.',
                style: GoogleFonts.montserrat(
                  fontSize: 11,
                  color: Colors.grey.shade700,
                ),
              ),
            ],
            const SizedBox(height: 16),

            // Origin to Destination Timeline
            Row(
              children: [
                Column(
                  children: [
                    Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF22C55E),
                          width: 4,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      origin.label.toUpperCase(),
                      style: GoogleFonts.montserrat(
                        fontSize: 8.5,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
                Expanded(
                  child: Container(
                    height: 2,
                    margin: const EdgeInsets.only(bottom: 12),
                    color: Colors.grey.shade400,
                  ),
                ),
                Column(
                  children: [
                    const Icon(
                      Icons.location_on,
                      color: Colors.grey,
                      size: 20,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      destination.acronym.toUpperCase(),
                      style: GoogleFonts.montserrat(
                        fontSize: 8.5,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 18),

            // Selected Route Info Card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                    child: Icon(icon, color: iconColor, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: GoogleFonts.montserrat(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                            color: Colors.black87,
                          ),
                        ),
                        Text(
                          subtitle,
                          style: GoogleFonts.montserrat(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Distance: $distance',
                          style: GoogleFonts.montserrat(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Est: $estTime',
                        style: GoogleFonts.montserrat(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Time of\nArrival: $arrivalTime',
                        textAlign: TextAlign.right,
                        style: GoogleFonts.montserrat(
                          fontSize: 10.5,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 22),

            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: onPreviewRoute,
                      icon: const Icon(Icons.route),
                      label: const Text('Preview'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF0F5A28),
                        side: const BorderSide(color: Color(0xFF0F5A28)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ),
                if (origin.type == NavigationOriginType.currentLocation) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        onPressed: onStartNavigation,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0F5A28),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 2,
                        ),
                        child: Text(
                          'Start',
                          style: GoogleFonts.montserrat(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            if (origin.type != NavigationOriginType.currentLocation) ...[
              const SizedBox(height: 8),
              const Text(
                'Preview only. Choose My Current Location to start navigation.',
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: onCancel,
                child: Text(
                  'Cancel Directions',
                  style: GoogleFonts.montserrat(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =========================================================================
// 4. STEP-BY-STEP ROUTE PREVIEW
// =========================================================================
class RoutePreviewHud extends StatelessWidget {
  final WalkingRoute route;
  final RouteType selectedRouteType;
  final WalkingRouteStep step;
  final int currentStepIndex;
  final int totalSteps;
  final VoidCallback onBack;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  const RoutePreviewHud({
    super.key,
    required this.route,
    required this.selectedRouteType,
    required this.step,
    required this.currentStepIndex,
    required this.totalSteps,
    required this.onBack,
    required this.onPrevious,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final isArrival = onNext == null;
    final routeTypeLabel = selectedRouteType == RouteType.shortest
        ? 'Shortest Route'
        : 'Shaded Path';
    final routeSubtitle = selectedRouteType == RouteType.shortest
        ? 'Most Direct Path'
        : 'Prefers shaded pathways';
    final routeIcon = selectedRouteType == RouteType.shortest
        ? Icons.bolt
        : Icons.cloud_outlined;
    final routeIconColor = selectedRouteType == RouteType.shortest
        ? const Color(0xFFECC700)
        : const Color(0xFF0F751B);

    return Stack(
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: EdgeInsets.fromLTRB(12, topPadding + 6, 16, 16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.98),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 12,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Back to route details',
                      onPressed: onBack,
                      icon: const Icon(
                        Icons.arrow_back,
                        color: Color(0xFF0B351E),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Route Preview',
                        style: GoogleFonts.montserrat(
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF0B351E),
                        ),
                      ),
                    ),
                    Text(
                      '${currentStepIndex + 1}/$totalSteps',
                      style: GoogleFonts.montserrat(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF0F751B),
                      ),
                    ),
                  ],
                ),
                const Divider(color: Color(0xFFDDE7E0), height: 18),
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEAF7EE),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        routeInstructionIcon(step.instruction),
                        color: const Color(0xFF0F751B),
                        size: 30,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            step.instruction,
                            style: GoogleFonts.montserrat(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF0B351E),
                            ),
                          ),
                          if (step.distanceMeters > 0) ...[
                            const SizedBox(height: 3),
                            Text(
                              step.distance,
                              style: GoogleFonts.montserrat(
                                fontSize: 13,
                                color: const Color(0xFF52705E),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 20,
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 15, 18, 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.98),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFDDE7E0)),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 14,
                  offset: Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(13),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 7,
                            ),
                          ],
                        ),
                        child: Icon(
                          routeIcon,
                          color: routeIconColor,
                          size: 30,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              routeTypeLabel,
                              style: GoogleFonts.montserrat(
                                color: const Color(0xFF1F1F1F),
                                fontSize: 14.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              routeSubtitle,
                              style: GoogleFonts.montserrat(
                                color: Colors.grey.shade600,
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Distance: ${route.distance}',
                              style: GoogleFonts.montserrat(
                                color: const Color(0xFF1F1F1F),
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'Est: ${route.time}',
                            style: GoogleFonts.montserrat(
                              color: const Color(0xFF1F1F1F),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Time of\nArrival: ${route.arrivalTime}',
                            textAlign: TextAlign.right,
                            style: GoogleFonts.montserrat(
                              color: Colors.grey.shade600,
                              fontSize: 10.5,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Divider(color: Color(0xFFDDE7E0), height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton.filled(
                      tooltip: 'Previous step',
                      onPressed: onPrevious,
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFFEAF7EE),
                        disabledBackgroundColor: const Color(0xFFF0F3F1),
                      ),
                      icon: const Icon(Icons.chevron_left),
                      color: const Color(0xFF0F751B),
                      disabledColor: Colors.grey.shade400,
                    ),
                    Text(
                      isArrival
                          ? 'Destination reached'
                          : 'Step ${currentStepIndex + 1} of $totalSteps',
                      style: GoogleFonts.montserrat(
                        color: const Color(0xFF0B351E),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    IconButton.filled(
                      tooltip: 'Next step',
                      onPressed: onNext,
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFF0F751B),
                        disabledBackgroundColor: const Color(0xFFF0F3F1),
                      ),
                      icon: const Icon(Icons.chevron_right),
                      color: Colors.white,
                      disabledColor: Colors.grey.shade400,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// =========================================================================
// 5. ACTIVE TURN-BY-TURN NAVIGATION HUD (Design Mockup Image 2)
// =========================================================================
class ActiveNavigationHud extends StatelessWidget {
  final CampusBuilding destination;
  final CampusRoom? destinationRoom;
  final WalkingRoute route;
  final NavigationOrigin origin;
  final RouteType selectedRouteType;
  final TransportMode selectedTransportMode;
  final VoidCallback onEndRoute;
  final VoidCallback onSimulateArrival;

  const ActiveNavigationHud({
    super.key,
    required this.route,
    required this.destination,
    this.destinationRoom,
    required this.origin,
    required this.selectedRouteType,
    required this.selectedTransportMode,
    required this.onEndRoute,
    required this.onSimulateArrival,
  });

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final distance = route.distance;
    final time = route.time;
    final heading = 'Follow the highlighted walking path';

    return Stack(
      children: [
        // 1. Top Turn-by-Turn Guidance Banner
        Positioned(
          top: topPadding + 10,
          left: 16,
          right: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF374151).withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.arrow_upward,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        heading,
                        style: GoogleFonts.montserrat(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        distance,
                        style: GoogleFonts.montserrat(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // 2. Floating Compass / Arrival Simulator Button
        Positioned(
          right: 18,
          bottom: 230,
          child: GestureDetector(
            onTap: onSimulateArrival,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Transform.rotate(
                angle: 0.5,
                child: const Icon(
                  Icons.navigation,
                  color: Color(0xFF0F751B),
                  size: 26,
                ),
              ),
            ),
          ),
        ),

        // 3. Bottom Dark Status Card
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 34),
            decoration: const BoxDecoration(
              color: Color(0xFF262626),
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black38,
                  blurRadius: 16,
                  offset: Offset(0, -4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Destination',
                            style: GoogleFonts.montserrat(
                              fontSize: 11.5,
                              color: Colors.grey.shade400,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            destinationRoom == null
                                ? destination.name
                                : '${destinationRoom!.title} '
                                    '(${destinationRoom!.floor}) via '
                                    '${destination.name} entrance',
                            style: GoogleFonts.montserrat(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'From ${origin.label}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.montserrat(
                              fontSize: 10.5,
                              color: Colors.grey.shade400,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          time.split(' ').first,
                          style: GoogleFonts.montserrat(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF22C55E),
                          ),
                        ),
                        Text(
                          'min',
                          style: GoogleFonts.montserrat(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF22C55E),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // Green Progress Bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: 0.65,
                    minHeight: 4,
                    backgroundColor: Colors.grey.shade700,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Color(0xFF22C55E),
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // Red "End Route" Button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: onEndRoute,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFDC2626),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 2,
                    ),
                    child: Text(
                      'End Route',
                      style: GoogleFonts.montserrat(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// =========================================================================
// 5. ARRIVAL HUD: "You've Arrived!" (New Mockup Screen)
// =========================================================================
class ArrivalHud extends StatelessWidget {
  final CampusBuilding destination;
  final CampusRoom? destinationRoom;
  final VoidCallback onFinish;

  const ArrivalHud({
    super.key,
    required this.destination,
    this.destinationRoom,
    required this.onFinish,
  });

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Stack(
      children: [
        // 1. Top "You've Arrived!" Banner Card
        Positioned(
          top: topPadding + 10,
          left: 16,
          right: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF374151).withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.location_on,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        destinationRoom == null
                            ? "You've Arrived!"
                            : 'Arrived at building entrance',
                        style: GoogleFonts.montserrat(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        destinationRoom == null
                            ? destination.name
                            : '${destination.name} • '
                                '${destinationRoom!.title}, '
                                '${destinationRoom!.floor}',
                        style: GoogleFonts.montserrat(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // 2. Bottom "Finish" Green Button
        Positioned(
          bottom: 30,
          left: 40,
          right: 40,
          child: SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: onFinish,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F5A28),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 3,
              ),
              child: Text(
                'Finish',
                style: GoogleFonts.montserrat(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
