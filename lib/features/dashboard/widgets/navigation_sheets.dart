import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import '../models/campus_models.dart';
import '../models/navigation_progress.dart';
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

String routeModeLabel(TransportMode mode) => switch (mode) {
      TransportMode.car => 'Car',
      TransportMode.motorcycle => 'Motorcycle',
      TransportMode.bicycle => 'Bicycle',
      TransportMode.walking => 'Walking',
    };

class LocationPhoto extends StatelessWidget {
  final String? imageUrl;
  const LocationPhoto({super.key, this.imageUrl});

  @override
  Widget build(BuildContext context) {
    final source = imageUrl?.trim();
    Widget placeholder() => const ColoredBox(
          color: Color(0xFFF0F4F1),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.image_outlined, size: 44, color: Color(0xFF0F5A28)),
                SizedBox(height: 8),
                Text('Photo unavailable'),
              ],
            ),
          ),
        );
    if (source == null || source.isEmpty) return placeholder();
    if (source.startsWith('data:')) {
      try {
        return Image.memory(
          UriData.parse(source).contentAsBytes(),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => placeholder(),
        );
      } on FormatException {
        return placeholder();
      }
    }
    final uri = Uri.tryParse(source);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      return Image.network(
        source,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, progress) => progress == null
            ? child
            : const Center(child: CircularProgressIndicator()),
        errorBuilder: (_, __, ___) => placeholder(),
      );
    }
    return Image.asset(source,
        fit: BoxFit.cover, errorBuilder: (_, __, ___) => placeholder());
  }
}

class IndoorLocationDetailsDialog extends StatelessWidget {
  final CampusBuilding building;
  final CampusRoom room;
  const IndoorLocationDetailsDialog({
    super.key,
    required this.building,
    required this.room,
  });

  @override
  Widget build(BuildContext context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 480,
            maxHeight: MediaQuery.sizeOf(context).height * 0.85,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 20, right: 8, top: 8),
                child: Row(children: [
                  const Expanded(
                      child: Text('LOCATION DETAILS',
                          style: TextStyle(fontWeight: FontWeight.bold))),
                  IconButton(
                    tooltip: 'Close details',
                    onPressed: () => Navigator.pop(context, false),
                    icon: const Icon(Icons.close),
                  ),
                ]),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(
                            height: 180,
                            width: double.infinity,
                            child: LocationPhoto(
                              imageUrl: room.imageUrl,
                            )),
                      ),
                      const SizedBox(height: 16),
                      Text(room.title,
                          style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F5A28))),
                      const SizedBox(height: 12),
                      Text('Building: ${building.name}'),
                      const SizedBox(height: 6),
                      Text('Floor: ${room.floor}'),
                      const SizedBox(height: 6),
                      Text('Room name: ${room.title}'),
                      if (room.description?.isNotEmpty ?? false) ...[
                        const SizedBox(height: 12),
                        Text(room.description!),
                      ],
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () => Navigator.pop(context, true),
                          icon: const Icon(Icons.directions),
                          label: const Text('Get Directions'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0F5A28),
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
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
                child: LocationPhoto(imageUrl: building.imageUrl),
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
                              onPressed: () async {
                                final navigate = await showDialog<bool>(
                                  context: context,
                                  builder: (_) => IndoorLocationDetailsDialog(
                                    building: building,
                                    room: room,
                                  ),
                                );
                                if (navigate == true && context.mounted) {
                                  onRoomDirectionsTap(room);
                                }
                              },
                              icon: const Icon(Icons.info_outline, size: 16),
                              label: const Text('Details'),
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
  final bool hasSelectedOrigin;
  final List<NavigationOrigin> origins;
  final bool isLocating;
  final String? locationStatus;
  final bool isCurrentLocationInsideCampus;
  final Future<void> Function()? onUseCurrentLocation;
  final ValueChanged<NavigationOrigin>? onOriginSelected;
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
    this.hasSelectedOrigin = true,
    this.origins = const [],
    this.isLocating = false,
    this.locationStatus,
    this.isCurrentLocationInsideCampus = false,
    this.onUseCurrentLocation,
    this.onOriginSelected,
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
  final TextEditingController _originSearchController = TextEditingController();
  late TransportMode _selectedMode;
  late RouteType _selectedRoute;
  List<WalkingRoute> _routes = [];
  bool _loading = true;
  String? _error;
  bool _showOriginPicker = false;
  bool _showBuildings = false;
  bool _isEditingOrigin = false;
  bool _attemptedCurrentLocation = false;
  int _routeRequestVersion = 0;

  List<NavigationOrigin> get _matchingBuildings {
    final query = _isEditingOrigin
        ? _originSearchController.text.trim().toLowerCase()
        : '';
    return widget.origins.where((origin) {
      if (origin.type != NavigationOriginType.campusLocation) return false;
      return query.isEmpty ||
          origin.label.toLowerCase().contains(query) ||
          (origin.acronym?.toLowerCase().contains(query) ?? false);
    }).toList();
  }

  @override
  void dispose() {
    _originSearchController.dispose();
    super.dispose();
  }

  void _restoreOriginField() {
    _originSearchController.text =
        widget.hasSelectedOrigin ? widget.origin.label : '';
    _isEditingOrigin = false;
    _showOriginPicker = false;
    _showBuildings = false;
    FocusScope.of(context).unfocus();
  }

  Future<void> _loadRoutes() async {
    final requestVersion = ++_routeRequestVersion;
    if (!widget.hasSelectedOrigin) {
      setState(() {
        _loading = false;
        _error = null;
        _routes = [];
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _routes = [];
    });
    try {
      final routes = await CampusService.fetchRoutes(
          widget.origin, widget.destination,
          mode: _selectedMode);
      if (!mounted || requestVersion != _routeRequestVersion) return;
      setState(() {
        _routes = routes;
        if (routes.isEmpty) {
          _error =
              'No ${routeModeLabel(_selectedMode).toLowerCase()} route is available on permitted pathways.';
        } else if (_selectedMode != TransportMode.walking) {
          _selectedRoute = RouteType.shortest;
        } else if (!routes.any((route) => route.type == _selectedRoute)) {
          _selectedRoute = routes.first.type;
        }
        _loading = false;
      });
    } catch (error) {
      if (!mounted || requestVersion != _routeRequestVersion) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _originSearchController.text =
        widget.hasSelectedOrigin ? widget.origin.label : '';
    _selectedMode = widget.initialTransportMode;
    _selectedRoute = widget.initialRouteType;
    _loadRoutes();
  }

  @override
  void didUpdateWidget(covariant ChooseRouteSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.hasSelectedOrigin != oldWidget.hasSelectedOrigin ||
        widget.origin.id != oldWidget.origin.id) {
      _originSearchController.text =
          widget.hasSelectedOrigin ? widget.origin.label : '';
      _isEditingOrigin = false;
    }
    final currentLocationMoved = widget.hasSelectedOrigin &&
        widget.origin.type == NavigationOriginType.currentLocation &&
        const Distance()(
              oldWidget.origin.coordinate,
              widget.origin.coordinate,
            ) >=
            20;
    if (widget.hasSelectedOrigin != oldWidget.hasSelectedOrigin ||
        widget.origin.id != oldWidget.origin.id ||
        currentLocationMoved ||
        widget.destination.id != oldWidget.destination.id) {
      if (widget.hasSelectedOrigin) {
        _showOriginPicker = false;
        _showBuildings = false;
      }
      _loadRoutes();
    }
  }

  Widget _originOption({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    String? subtitle,
    bool selected = false,
    bool error = false,
    Widget? trailing,
  }) {
    return Material(
      color: selected ? const Color(0xFFECFDF3) : Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(
            children: [
              Icon(icon,
                  size: 20,
                  color: error ? Colors.red : const Color(0xFF0F751B)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.montserrat(
                            fontSize: 12, fontWeight: FontWeight.w600)),
                    if (subtitle != null)
                      Text(subtitle,
                          style: GoogleFonts.montserrat(
                              fontSize: 10,
                              color:
                                  error ? Colors.red : Colors.grey.shade700)),
                  ],
                ),
              ),
              trailing ??
                  Icon(
                      selected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      size: 18,
                      color: selected ? const Color(0xFF0F751B) : Colors.grey),
            ],
          ),
        ),
      ),
    );
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
    return LayoutBuilder(builder: (context, constraints) {
      return SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(
              minHeight:
                  constraints.hasBoundedHeight ? constraints.maxHeight : 0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top Dark Green Header Box: Route Modes & Origin/Destination Box
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 12),
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
                decoration: const BoxDecoration(
                  color: Color(0xFF244B3E),
                  borderRadius: BorderRadius.all(Radius.circular(22)),
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

                    const SizedBox(height: 6),

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
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: TextField(
                                  key: const ValueKey('route-origin-field'),
                                  controller: _originSearchController,
                                  onTap: () => setState(() {
                                    _showOriginPicker = true;
                                    _originSearchController.selection =
                                        TextSelection(
                                      baseOffset: 0,
                                      extentOffset:
                                          _originSearchController.text.length,
                                    );
                                  }),
                                  onChanged: (query) => setState(() {
                                    _isEditingOrigin = true;
                                    _showOriginPicker = true;
                                    _showBuildings = query.trim().isNotEmpty;
                                  }),
                                  textInputAction: TextInputAction.search,
                                  maxLines: 1,
                                  style: GoogleFonts.montserrat(
                                    fontSize: 13,
                                    fontStyle: FontStyle.italic,
                                    color: Colors.grey.shade700,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: 'Your Location',
                                    hintStyle: GoogleFonts.montserrat(
                                      fontSize: 13,
                                      fontStyle: FontStyle.italic,
                                      color: Colors.grey.shade700,
                                    ),
                                    border: InputBorder.none,
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 9),
                                    suffixIconConstraints: const BoxConstraints(
                                        minWidth: 36, minHeight: 36),
                                    suffixIcon: IconButton(
                                      padding: EdgeInsets.zero,
                                      icon: const Icon(Icons.chevron_right,
                                          size: 18, color: Colors.grey),
                                      onPressed: () => setState(() {
                                        if (_showOriginPicker) {
                                          _restoreOriginField();
                                        } else {
                                          _showOriginPicker = true;
                                        }
                                      }),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                height: 36,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  widget.destination.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
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
                    if (_showOriginPicker) ...[
                      const SizedBox(height: 10),
                      _originOption(
                        icon: widget.isLocating
                            ? Icons.gps_fixed
                            : Icons.my_location,
                        label: 'Use My Current Location',
                        selected: widget.hasSelectedOrigin &&
                            widget.origin.type ==
                                NavigationOriginType.currentLocation,
                        error: _attemptedCurrentLocation &&
                            !widget.isLocating &&
                            !widget.isCurrentLocationInsideCampus,
                        subtitle: widget.isLocating
                            ? 'Detecting your location...'
                            : _attemptedCurrentLocation &&
                                    widget.locationStatus != null
                                ? widget.locationStatus
                                : 'Available only inside ISU Echague.',
                        onTap: () async {
                          setState(() {
                            _attemptedCurrentLocation = true;
                            _showBuildings = false;
                          });
                          FocusScope.of(context).unfocus();
                          await widget.onUseCurrentLocation?.call();
                          if (mounted &&
                              widget.hasSelectedOrigin &&
                              widget.origin.type ==
                                  NavigationOriginType.currentLocation) {
                            setState(_restoreOriginField);
                          }
                        },
                      ),
                      const SizedBox(height: 6),
                      _originOption(
                        icon: Icons.apartment,
                        label: 'Others',
                        subtitle: 'Choose another campus building.',
                        trailing: Icon(
                          _showBuildings
                              ? Icons.expand_less
                              : Icons.expand_more,
                          color: const Color(0xFF0F751B),
                        ),
                        onTap: () => setState(() {
                          _showBuildings = !_showBuildings;
                        }),
                      ),
                      if (_showBuildings) ...[
                        const SizedBox(height: 6),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 150),
                          child: ListView(
                            shrinkWrap: true,
                            children: [
                              for (final origin in _matchingBuildings)
                                Padding(
                                  padding: const EdgeInsets.only(top: 5),
                                  child: _originOption(
                                    icon: Icons.location_on_outlined,
                                    label: origin.label,
                                    selected: widget.hasSelectedOrigin &&
                                        widget.origin.id == origin.id,
                                    onTap: () {
                                      widget.onOriginSelected?.call(origin);
                                      setState(_restoreOriginField);
                                    },
                                  ),
                                ),
                              if (_matchingBuildings.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.all(10),
                                  child: Text(
                                    !_isEditingOrigin ||
                                            _originSearchController.text
                                                .trim()
                                                .isEmpty
                                        ? 'No other campus buildings are available.'
                                        : 'No buildings found.',
                                    style: GoogleFonts.montserrat(
                                        fontSize: 11,
                                        color: Colors.grey.shade700),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),

              // Keep a visible map gap between the origin panel and route chooser.
              Container(
                margin: const EdgeInsets.only(top: 28),
                decoration: const BoxDecoration(
                  color: Color(0xFFD9D9D9),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black26,
                        blurRadius: 5,
                        offset: Offset(0, -2)),
                  ],
                ),
                padding: EdgeInsets.fromLTRB(
                    20, 8, 20, 36 + MediaQuery.of(context).padding.bottom),
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

                    const SizedBox(height: 2),

                    Text(
                      _selectedMode == TransportMode.walking
                          ? 'CHOOSE ROUTE'
                          : 'ROUTE',
                      style: GoogleFonts.montserrat(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
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

                    if (!widget.hasSelectedOrigin || _isEditingOrigin)
                      Text(
                          'Choose a starting point to see ${routeModeLabel(_selectedMode).toLowerCase()} routes.')
                    else if (_loading)
                      const Center(child: CircularProgressIndicator())
                    else if (_error != null) ...[
                      Text(_error!),
                      TextButton(
                          onPressed: _loadRoutes, child: const Text('Retry')),
                    ],
                    if (widget.hasSelectedOrigin &&
                        !_isEditingOrigin &&
                        !_loading &&
                        _error == null) ...[
                      if (_selectedMode == TransportMode.walking) ...[
                        _buildRouteCard(
                          type: RouteType.shortest,
                          title: 'Shortest Route',
                          subtitle: 'Most Direct Path',
                          distance: shortestDist,
                          walkTime: shortestTime,
                          icon: Icons.thunderstorm_outlined,
                          iconColor: const Color(0xFFECC700),
                        ),

                        const SizedBox(height: 6),

                        // Option 2: Shaded Path Card (Shaded)
                        _buildRouteCard(
                          type: RouteType.comfortableShaded,
                          title: 'Shaded Path',
                          subtitle: 'Shaded, Wider',
                          distance: comfortableDist,
                          walkTime: comfortableTime,
                          icon: Icons.cloud_outlined,
                          iconColor: const Color(0xFF0F5A28),
                        ),
                      ] else ...[
                        _buildTransportSummary(shortest),
                      ],
                      const SizedBox(height: 48),
                    ],
                    // "View Route" Button
                    Center(
                        child: SizedBox(
                      width: 220,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: !widget.hasSelectedOrigin ||
                                _isEditingOrigin ||
                                _loading ||
                                _error != null ||
                                _routes.isEmpty
                            ? null
                            : () => widget.onViewRoute(
                                _routes.firstWhere(
                                    (r) => r.type == _selectedRoute),
                                _selectedMode),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF285500),
                          side: const BorderSide(color: Color(0xFF8BA55B)),
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
                    )),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  Widget _buildTransportSummary(WalkingRoute? route) {
    const green = Color(0xFF0F5A28);
    Widget metric(IconData icon, String value, String label) => Expanded(
          child: Row(
            children: [
              Icon(icon, color: green, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(value,
                        style: GoogleFonts.montserrat(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF0B351E))),
                    Text(label,
                        style: GoogleFonts.montserrat(
                            fontSize: 11, color: Colors.grey.shade600)),
                  ],
                ),
              ),
            ],
          ),
        );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD5E5D9)),
        boxShadow: const [
          BoxShadow(
              color: Color(0x090F5A28), blurRadius: 16, offset: Offset(0, 5)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFECF5EE),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(routeModeIcon(_selectedMode), color: green, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
                child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${routeModeLabel(_selectedMode)} route',
                    style: GoogleFonts.montserrat(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: green)),
                const SizedBox(height: 4),
                Text(
                    'Direct route to ${widget.destination.acronym.isNotEmpty ? widget.destination.acronym : widget.destination.name}',
                    style: GoogleFonts.montserrat(
                        fontSize: 12, color: Colors.grey.shade600)),
              ],
            )),
          ]),
          const SizedBox(height: 20),
          Row(children: [
            metric(Icons.route_outlined, route?.distance ?? '—', 'Distance'),
            const SizedBox(width: 12),
            metric(Icons.schedule, route?.time ?? '—', 'Estimated time'),
          ]),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Divider(height: 1, color: Color(0xFFE7EDE8)),
          ),
          Row(children: [
            const Icon(Icons.trip_origin, size: 16, color: green),
            const SizedBox(width: 8),
            Expanded(
                child: Text(
                    'From ${route?.startNodeName ?? "route starting point"}',
                    style: GoogleFonts.montserrat(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: green))),
          ]),
        ],
      ),
    );
  }

  Widget _buildModeIcon(TransportMode mode) {
    final isSelected = _selectedMode == mode;
    return GestureDetector(
      onTap: () {
        if (_selectedMode == mode) return;
        setState(() => _selectedMode = mode);
        widget.onTransportModeChanged?.call(mode);
        _loadRoutes();
      },
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white24 : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Tooltip(
          message: routeModeLabel(mode),
          child: Icon(
            routeModeIcon(mode),
            color: isSelected ? Colors.white : Colors.white60,
            size: 20,
          ),
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
            color: Colors.transparent,
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
                    color: const Color(0xFFEDEBEA),
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
                  'Est. Walk: ',
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
                '${routeModeLabel(selectedTransportMode)} route ends at ${destination.name} entrance.',
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
  final NavigationProgress? progress;
  final String? navigationStatus;
  final VoidCallback onRecenter;
  final VoidCallback? onRetryRoute;

  const ActiveNavigationHud({
    super.key,
    required this.route,
    required this.destination,
    this.destinationRoom,
    required this.origin,
    required this.selectedRouteType,
    required this.selectedTransportMode,
    required this.onEndRoute,
    this.progress,
    this.navigationStatus,
    required this.onRecenter,
    this.onRetryRoute,
  });

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final distance =
        '${(progress?.remainingMeters ?? route.distanceMeters).round()} m remaining';
    final time =
        '${(progress?.remainingMinutes ?? route.estimatedMinutes).ceil()} min';
    final heading = navigationStatus ??
        progress?.instruction ??
        'Waiting for an accurate GPS position';
    final arrival = DateTime.now().add(Duration(
        seconds: ((progress?.remainingMinutes ?? route.estimatedMinutes) * 60)
            .round()));
    final arrivalLabel =
        '${arrival.hour.toString().padLeft(2, '0')}:${arrival.minute.toString().padLeft(2, '0')}';

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
                  child: Icon(
                    routeInstructionIcon(heading),
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
                        '${(progress?.instructionMeters ?? route.distanceMeters).round()} m · $distance',
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

        // Recenter on the live location; arrival is detected from GPS.
        Positioned(
          right: 18,
          bottom: 230,
          child: GestureDetector(
            onTap: onRecenter,
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
                            '${routeModeLabel(selectedTransportMode)} · From ${origin.label} · Arrival $arrivalLabel',
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
                    value: progress?.fraction ?? 0,
                    minHeight: 4,
                    backgroundColor: Colors.grey.shade700,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Color(0xFF22C55E),
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                if (onRetryRoute != null)
                  TextButton.icon(
                    onPressed: onRetryRoute,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry route',
                        style: TextStyle(color: Colors.white)),
                  ),

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
