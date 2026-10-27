import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';

import '../../auth/services/user_session.dart';
import '../../offline/services/offline_pack_service.dart';
import '../../offline/services/offline_tile_provider.dart';
import '../../offline/widgets/offline_update_banner.dart';
import '../data/campus_dataset.dart';
import '../models/building_marker_style.dart';
import '../models/campus_models.dart';
import '../models/navigation_history.dart';
import '../models/navigation_camera.dart';
import '../models/navigation_heading.dart';
import '../models/navigation_progress.dart';
import '../models/route_trim.dart';
import '../services/campus_service.dart';
import '../services/campus_search.dart';
import '../services/navigation_history_service.dart';
import '../widgets/location_puck.dart';
import '../widgets/navigation_sheets.dart';
import 'user_info_screen.dart';

const Color navigationRouteBlue = Color(0xFF2563EB);
const double _initialCampusZoom = 16.8;

double buildingLabelOpacity(double zoom) =>
    ((zoom - 17.2) / 1.0).clamp(0.0, 1.0);

double buildingIconOpacity(double zoom, {bool isSelected = false}) =>
    isSelected ? 1.0 : ((zoom - 15.5) / 0.8).clamp(0.0, 1.0);

// Shared with the offline tile download so the cache covers the whole camera.
final LatLngBounds isuEchagueBounds = LatLngBounds(
  const LatLng(isuCampusSouth, isuCampusWest),
  const LatLng(isuCampusNorth, isuCampusEast),
);

const List<LatLng> isuEchagueMockBoundary = [
  LatLng(isuCampusSouth, isuCampusWest),
  LatLng(isuCampusSouth, isuCampusEast),
  LatLng(isuCampusNorth, isuCampusEast),
  LatLng(isuCampusNorth, isuCampusWest),
];

enum NavigationUiState {
  idle,
  buildingDetails,
  chooseRoute,
  routeDetails,
  routePreview,
  navigating,
  arrived,
}

class MapViewScreen extends StatefulWidget {
  const MapViewScreen({super.key, this.navigationClock});

  /// Injectable clock for GPS freshness and reroute cooldown tests.
  final DateTime Function()? navigationClock;

  @override
  State<MapViewScreen> createState() => _MapViewScreenState();
}

class _MapViewScreenState extends State<MapViewScreen> {
  DateTime get _navigationNow =>
      widget.navigationClock?.call() ?? DateTime.now();

  /// Whether the last GPS fix is recent enough to navigate or start from.
  bool get _hasFreshFix =>
      _lastPositionAt != null &&
      _navigationNow.difference(_lastPositionAt!) <=
          const Duration(seconds: 20);

  static const NavigationOrigin _defaultOrigin = NavigationOrigin(
    id: 'main_gate',
    label: 'ISU Main Gate',
    coordinate: isuMainGateNode,
    type: NavigationOriginType.mainGate,
  );
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final MapController _mapController = MapController();
  final ValueNotifier<double> _mapZoom = ValueNotifier(_initialCampusZoom);
  List<NavigationHistoryEntry> _recentHistory = [];

  NavigationUiState _navigationState = NavigationUiState.idle;
  CampusBuilding? _selectedBuilding;
  CampusRoom? _selectedRoom;
  WalkingRoute? _walkingRoute;
  NavigationOrigin _selectedOrigin = _defaultOrigin;
  RouteType _selectedRouteType = RouteType.comfortableShaded;
  TransportMode _selectedTransportMode = TransportMode.walking;
  String _selectedCategoryFilter = 'All';
  LatLng? _currentUserLocation;
  String? _locationStatus;
  bool _isLocating = false;
  bool _hasSelectedOrigin = false;
  bool _isLoadingBuildings = true;
  String? _buildingsError;
  bool _offlineUpdateDismissed = false;
  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<CompassEvent>? _compassSubscription;
  double? _movementHeading;
  // Smoothed compass heading; drives the location cone and walking arrow.
  final ValueNotifier<double?> _deviceHeading = ValueNotifier(null);
  // Where the navigation camera faces: the route ahead, not the phone.
  double? _cameraHeading;
  DateTime? _lastNavigationCameraUpdate;
  bool _followNavigationCamera = true;
  // Last GPS fix motion, used to move the camera smoothly between fixes.
  double _fixSpeed = 0;
  double? _fixCourse;
  DateTime? _fixReceivedAt;
  final ValueNotifier<double?> _navigationHeading = ValueNotifier(null);
  Timer? _followTimer;
  final ValueNotifier<LatLng?> _navigationPosition = ValueNotifier(null);
  RouteTrim? _routeTrim;
  final TravelOdometer _odometer = TravelOdometer();
  // The odometer when the latest reroute was requested from the user.
  double? _rerouteTravelled;
  int _previewStepIndex = 0;
  String? _historySessionId;
  Future<void> _historyWriteQueue = Future<void>.value();
  NavigationProgress? _liveProgress;
  double _gpsAccuracy = double.infinity;
  DateTime? _lastPositionAt;
  DateTime? _lastRerouteAt;
  Timer? _gpsWatchdog;
  bool _isRerouting = false;
  String? _navigationStatus;
  String? _routeError;
  int _navigationGeneration = 0;
  int _offRouteFixes = 0;
  int _arrivalFixes = 0;

  bool get _isNavigationActive =>
      _navigationState == NavigationUiState.routePreview ||
      _navigationState == NavigationUiState.navigating ||
      _navigationState == NavigationUiState.arrived;

  List<NavigationOrigin> get _availableOrigins => [
        if (_currentUserLocation != null)
          NavigationOrigin(
            id: 'current_location',
            label: 'My Current Location',
            coordinate: _currentUserLocation!,
            type: NavigationOriginType.currentLocation,
          ),
        ...isuCampusBuildings
            .where((building) => building.id != _selectedBuilding?.id)
            .map(
              (building) => NavigationOrigin(
                id: building.id,
                label: building.name,
                acronym: building.acronym,
                coordinate: building.coordinate,
                type: NavigationOriginType.campusLocation,
              ),
            ),
      ];

  List<LatLng> get _routePoints => _walkingRoute?.points ?? const [];

  /// The latest fix is accurate and fresh enough to guide by.
  bool get _hasUsableFix =>
      _gpsAccuracy.isFinite &&
      _gpsAccuracy <= 25 &&
      _gpsAccuracy >= 0 &&
      _hasFreshFix;

  /// While navigating, only the route still ahead of the user is drawn. A
  /// reroute brings a new point list, which starts a new trim. Positions from
  /// a fix guidance would ignore don't move the line.
  List<LatLng> _visibleRoutePoints(LatLng? position) {
    final points = _routePoints;
    if (_navigationState != NavigationUiState.navigating || position == null) {
      return points;
    }
    final travelled = _odometer.metersAt(_navigationNow);
    if (!identical(_routeTrim?.points, points)) {
      // A reroute starts where the user was when it was requested, which can
      // be well behind them by the time it arrives.
      _routeTrim = RouteTrim(points, _rerouteTravelled ?? travelled);
    }
    return _routeTrim!
        .ahead(position, travelled: travelled, advance: _hasUsableFix);
  }

  /// The destination stands out from the other buildings while a route to it
  /// is on the map.
  bool _highlightsDestination(CampusBuilding building) =>
      (_isNavigationActive ||
          _navigationState == NavigationUiState.routeDetails) &&
      building.id == _selectedBuilding?.id;

  /// Search and category filters never hide the destination of the route on
  /// the map.
  List<CampusBuilding> _withRouteDestination(List<CampusBuilding> buildings) {
    final destination = _selectedBuilding;
    if (destination == null ||
        !_highlightsDestination(destination) ||
        buildings.any((building) => building.id == destination.id)) {
      return buildings;
    }
    return [...buildings, destination];
  }

  bool get _showsTransportOriginMarker =>
      _navigationState == NavigationUiState.chooseRoute ||
      _navigationState == NavigationUiState.routeDetails ||
      _navigationState == NavigationUiState.routePreview ||
      _navigationState == NavigationUiState.navigating;

  List<WalkingRouteStep> get _routePreviewSteps {
    final route = _walkingRoute;
    final destination = _selectedBuilding;
    if (route == null || destination == null || route.points.isEmpty) {
      return const [];
    }

    final previewSteps = <WalkingRouteStep>[];
    if (route.steps.isEmpty) {
      previewSteps.add(
        WalkingRouteStep(
          instruction: RouteMetricsHelper.getHeadingInstruction(
              _selectedOrigin, destination),
          distanceMeters: 0,
          coordinate: route.points.first,
        ),
      );
      if (route.points.length > 2) {
        previewSteps.add(
          WalkingRouteStep(
            instruction: 'Continue along the highlighted campus path',
            distanceMeters: route.distanceMeters,
            coordinate: route.points[route.points.length ~/ 2],
          ),
        );
      }
    } else {
      for (var index = 0; index < route.steps.length; index++) {
        final step = route.steps[index];
        final fallbackPointIndex = route.steps.length == 1
            ? 0
            : ((index / (route.steps.length - 1)) * (route.points.length - 1))
                .round();
        previewSteps.add(
          WalkingRouteStep(
            instruction: step.instruction,
            distanceMeters: step.distanceMeters,
            coordinate: step.coordinate ?? route.points[fallbackPointIndex],
          ),
        );
      }
    }

    previewSteps.add(
      WalkingRouteStep(
        instruction: 'Arrive at ${destination.name} entrance',
        distanceMeters: 0,
        coordinate: route.points.last,
      ),
    );
    return previewSteps;
  }

  WalkingRouteStep? get _currentPreviewStep {
    final steps = _routePreviewSteps;
    if (steps.isEmpty) return null;
    final index =
        _previewStepIndex < steps.length ? _previewStepIndex : steps.length - 1;
    return steps[index];
  }

  LatLng? get _routeEtaLabelPoint {
    final points = _walkingRoute?.points;
    if (points == null || points.isEmpty) return null;
    final index = ((points.length - 1) * 0.78).round();
    return points[index];
  }

  Widget _buildTransportOriginMarker() {
    final isWalking = _selectedTransportMode == TransportMode.walking;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(
          color: navigationRouteBlue,
          width: 3,
        ),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 6),
        ],
      ),
      alignment: Alignment.center,
      child: isWalking
          ? Transform.rotate(
              // Markers turn with the map, so this is the true heading.
              angle: ((_navigationState == NavigationUiState.navigating
                          ? _navigationHeading.value ?? _facingHeading
                          : null) ??
                      routeHeading(_routePoints, _selectedOrigin.coordinate) ??
                      0) *
                  math.pi /
                  180,
              child: const Icon(Icons.navigation,
                  color: navigationRouteBlue, size: 26),
            )
          : Icon(
              routeModeIcon(_selectedTransportMode),
              color: navigationRouteBlue,
              size: 22,
            ),
    );
  }

  @override
  void initState() {
    super.initState();
    OfflinePackService.instance.addListener(_onOfflinePackChanged);
    _searchFocusNode.addListener(() {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadBuildings();
      _initializeCurrentLocation();
      _checkOfflineMapUpdate();
      _loadRecentHistory();
    });
  }

  void _onOfflinePackChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadRecentHistory() async {
    final token = UserSession.accessToken;
    if (token == null) return;
    try {
      final history = await NavigationHistoryService.load();
      if (mounted) {
        setState(() {
          _recentHistory = history.take(6).toList();
        });
      }
    } catch (_) {}
  }

  /// Asks the backend once per session whether the stored map is stale. A new
  /// version is only announced; the user chooses whether to download it.
  Future<void> _checkOfflineMapUpdate() async {
    final pack = OfflinePackService.instance;
    await pack.load();
    if (!pack.status.isReady) return;
    await pack.checkForUpdate();
  }

  Future<void> _loadBuildings() async {
    setState(() {
      _isLoadingBuildings = true;
      _buildingsError = null;
      isuCampusBuildings.clear();
    });
    try {
      final buildings = await CampusService.fetchBuildings();
      if (!mounted) return;
      setState(() {
        isuCampusBuildings.addAll(buildings);
        _isLoadingBuildings = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingBuildings = false;
        _buildingsError =
            'Unable to load campus locations. Check your connection and try again.';
      });
    }
  }

  @override
  void dispose() {
    OfflinePackService.instance.removeListener(_onOfflinePackChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _followTimer?.cancel();
    _navigationPosition.dispose();
    _navigationHeading.dispose();
    _deviceHeading.dispose();
    _positionSubscription?.cancel();
    _gpsWatchdog?.cancel();
    _compassSubscription?.cancel();
    _mapZoom.dispose();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _initializeCurrentLocation() async {
    if (_isLocating) return;
    setState(() {
      _isLocating = true;
      _locationStatus = 'Getting your current location...';
    });

    try {
      final locationEnabled = await Geolocator.isLocationServiceEnabled();
      if (!mounted) return;
      if (!locationEnabled) {
        setState(() => _locationStatus =
            'Turn on Location Services to use your position.');
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (!mounted) return;
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (!mounted) return;
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setState(() => _locationStatus =
            'Location permission is needed to show your position.');
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (!mounted) return;
      _updateCurrentPosition(position);

      // Keep an existing GPS stream alive when refreshing the current fix.
      if (_positionSubscription != null) return;
      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: _navigationLocationSettings(),
      ).listen(_updateCurrentPosition, onError: (Object error) {
        if (!mounted) return;
        _positionSubscription?.cancel();
        _positionSubscription = null;
        // The last fix is no longer current, so it can't start directions.
        _lastPositionAt = null;
        setState(() {
          _locationStatus =
              'GPS is unavailable. Check Location Services and permissions.';
          _navigationStatus = _locationStatus;
        });
      });
    } catch (_) {
      if (mounted) {
        setState(() => _locationStatus =
            'Current location is unavailable. You can choose another starting point.');
      }
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  /// One fix per second. Android otherwise sends one every five seconds,
  /// which leaves the camera far behind at vehicle speeds.
  LocationSettings _navigationLocationSettings() {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
        intervalDuration: const Duration(seconds: 1),
      );
    }
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
        activityType: ActivityType.otherNavigation,
        pauseLocationUpdatesAutomatically: false,
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 0,
    );
  }

  void _updateCurrentPosition(Position position) {
    if (!mounted) return;
    final next = LatLng(position.latitude, position.longitude);
    _gpsAccuracy = position.accuracy;
    _lastPositionAt = position.timestamp;
    final previous = _currentUserLocation;
    final moving = position.speed.isFinite && position.speed > 0.5;
    setState(() {
      if (moving &&
          position.heading.isFinite &&
          position.heading >= 0 &&
          position.heading < 360) {
        _movementHeading = position.heading;
      } else if (previous != null && const Distance()(previous, next) >= 3) {
        _movementHeading =
            navigationBearing(previous, next) ?? _movementHeading;
      }
      _fixSpeed = moving ? position.speed : 0;
      _fixCourse = moving ? _movementHeading : null;
      _fixReceivedAt = _navigationNow;
      _navigationPosition.value = next;
      _currentUserLocation = LatLng(position.latitude, position.longitude);
      _locationStatus = isuEchagueBounds.contains(_currentUserLocation!)
          ? null
          : 'You are outside the supported ISU Echague campus area.';
      if (_selectedOrigin.type == NavigationOriginType.currentLocation) {
        _selectedOrigin = NavigationOrigin(
          id: 'current_location',
          label: 'My Current Location',
          coordinate: _currentUserLocation!,
          type: NavigationOriginType.currentLocation,
        );
        _hasSelectedOrigin = isuEchagueBounds.contains(_currentUserLocation!);
      } else if (!_hasSelectedOrigin &&
          _navigationState == NavigationUiState.chooseRoute &&
          isuEchagueBounds.contains(_currentUserLocation!)) {
        // A fix that arrives before any starting point is chosen becomes
        // the default. A starting point the user picked is never replaced.
        _applyDefaultOrigin();
      }
    });

    // Only trusted fixes count as movement.
    _odometer.record(_navigationNow, _hasUsableFix ? _fixSpeed : 0);
    _startCompass();
    _refreshNavigationProgress(countFix: true);

    if (_navigationState == NavigationUiState.navigating &&
        isuEchagueBounds.contains(_currentUserLocation!)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _updateNavigationCamera(force: true);
      });
    }
  }

  /// Navigation ticks, plus the compass for the walking arrow.
  void _startFollowing() {
    _followTimer ??=
        Timer.periodic(const Duration(milliseconds: 100), (_) => _followTick());
    _startCompass();
  }

  /// Runs for as long as the screen is open: the location cone uses it
  /// outside navigation too.
  void _startCompass() {
    if (_compassSubscription != null ||
        kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return;
    }
    final events = FlutterCompass.events;
    if (events == null) return;
    _compassSubscription = events.listen(
      (event) {
        final heading = event.heading;
        if (!mounted || heading == null || !heading.isFinite || heading < 0) {
          return;
        }
        _deviceHeading.value = smoothHeading(_deviceHeading.value, heading);
        if (_navigationState != NavigationUiState.navigating) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _updateNavigationCamera();
        });
      },
      onError: (_) {
        _compassSubscription?.cancel();
        _compassSubscription = null;
        _deviceHeading.value = null;
      },
    );
  }

  void _stopFollowing() {
    _followTimer?.cancel();
    _followTimer = null;
    _cameraHeading = null;
    _navigationHeading.value = null;
    _lastNavigationCameraUpdate = null;
  }

  /// Compass when walking or still; GPS course at vehicle speeds.
  double? get _facingHeading => navigationFacing(
      compassHeading: _deviceHeading.value,
      gpsCourse: _fixCourse ?? _movementHeading,
      speed: _fixSpeed);

  /// Moves the marker and camera along the current course between GPS fixes.
  void _followTick() {
    final fix = _currentUserLocation;
    final receivedAt = _fixReceivedAt;
    if (!mounted ||
        fix == null ||
        receivedAt == null ||
        _navigationState != NavigationUiState.navigating) {
      return;
    }
    _navigationPosition.value = predictPosition(fix,
        speed: _fixSpeed,
        course: _fixCourse,
        elapsed: _navigationNow.difference(receivedAt));
    // Ticks are already paced; the throttle is for frequent compass events.
    _updateNavigationCamera(force: true);
  }

  /// Points the walking arrow where the phone faces and, while following,
  /// turns the map so the route ahead points up.
  void _updateNavigationCamera({bool force = false}) {
    final location = _currentUserLocation;
    if (!mounted ||
        location == null ||
        _navigationState != NavigationUiState.navigating) {
      return;
    }
    final now = DateTime.now();
    if (!force &&
        _lastNavigationCameraUpdate != null &&
        now.difference(_lastNavigationCameraUpdate!) <
            const Duration(milliseconds: 90)) {
      return;
    }
    _lastNavigationCameraUpdate = now;
    final position = _navigationPosition.value ?? location;
    final cameraTarget = navigationCameraHeading(_routePoints, position,
            gpsCourse: _fixCourse ?? _movementHeading) ??
        0;
    _cameraHeading = smoothHeading(_cameraHeading, cameraTarget, factor: 0.2);
    final facing = _facingHeading;
    _navigationHeading.value = facing == null
        ? _cameraHeading
        : smoothHeading(_navigationHeading.value, facing, factor: 0.35);
    if (!_followNavigationCamera) return;
    _mapController.moveAndRotate(
        position, 18.5, cameraRotationForHeading(_cameraHeading!));
  }

  void _resumeNavigationFollowing() {
    setState(() => _followNavigationCamera = true);
    _startFollowing();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateNavigationCamera(force: true);
    });
  }

  /// Starts new directions from the user's position when a fresh fix is
  /// known inside campus. Otherwise no starting point is chosen yet.
  void _applyDefaultOrigin() {
    final location = _currentUserLocation;
    final insideCampus =
        location != null && _hasFreshFix && isuEchagueBounds.contains(location);
    _selectedOrigin = insideCampus
        ? NavigationOrigin(
            id: 'current_location',
            label: 'My Current Location',
            coordinate: location,
            type: NavigationOriginType.currentLocation,
          )
        : _defaultOrigin;
    _hasSelectedOrigin = insideCampus;
  }

  /// Asks for a fix in the background when directions open without one, so
  /// the user's position can still become the starting point.
  void _locateForDefaultOrigin() {
    if (!_hasSelectedOrigin) _initializeCurrentLocation();
  }

  Future<void> _useCurrentLocationAsOrigin() async {
    if (_currentUserLocation == null ||
        !isuEchagueBounds.contains(_currentUserLocation!)) {
      await _initializeCurrentLocation();
    }
    if (!mounted) return;

    final location = _currentUserLocation;
    if (location == null || !isuEchagueBounds.contains(location)) {
      return;
    }

    setState(() {
      _selectedOrigin = NavigationOrigin(
        id: 'current_location',
        label: 'My Current Location',
        coordinate: location,
        type: NavigationOriginType.currentLocation,
      );
      _hasSelectedOrigin = true;
      _locationStatus = null;
    });
  }

  void _cancelDirections() {
    _stopFollowing();
    _gpsWatchdog?.cancel();
    _navigationGeneration++;
    setState(() {
      _navigationState = NavigationUiState.idle;
      _walkingRoute = null;
      _selectedRoom = null;
      _historySessionId = null;
      _followNavigationCamera = true;
      _liveProgress = null;
      _navigationStatus = null;
      _routeError = null;
      _isRerouting = false;
      _lastRerouteAt = null;
      _rerouteTravelled = null;
      _offRouteFixes = 0;
      _arrivalFixes = 0;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _mapController.moveAndRotate(isuCampusCenter, 16.8, 0);
    });
  }

  void _recordHistory(NavigationHistoryStatus status) {
    if (status != NavigationHistoryStatus.previewed &&
        status != NavigationHistoryStatus.navigationStarted) return;
    final destination = _selectedBuilding;
    final route = _walkingRoute;
    if (destination == null || route == null || _historySessionId != null)
      return;
    final token = UserSession.accessToken;
    if (token == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('Please log in again to save your navigation history.')));
      return;
    }
    final sessionId =
        '${DateTime.now().microsecondsSinceEpoch}_${destination.id}';
    _historySessionId = sessionId;
    final roomId = _selectedRoom?.id;
    _historyWriteQueue = _historyWriteQueue
        .then((_) => NavigationHistoryService.record(
            buildingId: destination.id, roomId: roomId, token: token))
        .catchError((Object error) {
      if (!mounted || UserSession.accessToken != token) return;
      if (_historySessionId == sessionId) _historySessionId = null;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'History was not saved. ${error.toString().replaceFirst('Exception: ', '')}')));
    });
  }

  Future<void> _startNavigation() async {
    if (_selectedOrigin.type != NavigationOriginType.currentLocation ||
        _walkingRoute == null) return;
    await _initializeCurrentLocation();
    if (!mounted || _navigationState != NavigationUiState.routeDetails) return;
    if (_currentUserLocation == null ||
        !_hasFreshFix ||
        !isuEchagueBounds.contains(_currentUserLocation!)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'A current GPS position inside campus is needed to start navigation.')));
      return;
    }
    FocusScope.of(context).unfocus();
    _recordHistory(NavigationHistoryStatus.navigationStarted);
    setState(() {
      _navigationState = NavigationUiState.navigating;
      _followNavigationCamera = true;
      _navigationGeneration++;
      _liveProgress = null;
      _arrivalFixes = 0;
      _offRouteFixes = 0;
      _lastRerouteAt = null;
      _rerouteTravelled = null;
    });
    _gpsWatchdog?.cancel();
    _gpsWatchdog = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || _navigationState != NavigationUiState.navigating) return;
      if (!_hasFreshFix) {
        _arrivalFixes = 0;
        _offRouteFixes = 0;
        setState(() =>
            _navigationStatus = 'GPS signal lost. Waiting for your location…');
      }
    });
    await _reroute(force: true);
    if (!mounted || _navigationState != NavigationUiState.navigating) return;
    _startFollowing();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateNavigationCamera(force: true);
    });
  }

  void _refreshNavigationProgress({bool countFix = false}) {
    final route = _walkingRoute;
    final location = _currentUserLocation;
    if (_navigationState != NavigationUiState.navigating ||
        route == null ||
        location == null) return;
    if (!_hasFreshFix) {
      setState(() =>
          _navigationStatus = 'GPS signal lost. Waiting for your location…');
      _arrivalFixes = 0;
      _offRouteFixes = 0;
      return;
    }
    if (!_gpsAccuracy.isFinite || _gpsAccuracy > 25 || _gpsAccuracy < 0) {
      setState(() => _navigationStatus =
          'GPS accuracy is low. Waiting for a better position…');
      _arrivalFixes = 0;
      _offRouteFixes = 0;
      return;
    }
    final progress =
        NavigationProgress.calculate(route, location, accuracy: _gpsAccuracy);
    setState(() {
      _liveProgress = progress;
      if (!_isRerouting) _navigationStatus = _locationStatus ?? _routeError;
    });
    if (_isRerouting || !countFix) return;
    _arrivalFixes = progress.arrived ? _arrivalFixes + 1 : 0;
    if (_arrivalFixes >= 2) {
      _gpsWatchdog?.cancel();
      _stopFollowing();
      _navigationGeneration++;
      setState(() => _navigationState = NavigationUiState.arrived);
      return;
    }
    _offRouteFixes = progress.offRouteMeters > 30 ? _offRouteFixes + 1 : 0;
    if (_offRouteFixes >= 2 && isuEchagueBounds.contains(location)) _reroute();
  }

  Future<void> _reroute({bool force = false}) async {
    final location = _currentUserLocation;
    final destination = _selectedBuilding;
    if (_isRerouting ||
        location == null ||
        destination == null ||
        _navigationState != NavigationUiState.navigating) return;
    if (!_hasUsableFix) {
      _refreshNavigationProgress();
      return;
    }
    if (!force &&
        _lastRerouteAt != null &&
        _navigationNow.difference(_lastRerouteAt!) <
            const Duration(seconds: 15)) return;
    final generation = _navigationGeneration;
    _lastRerouteAt = _navigationNow;
    _rerouteTravelled = _odometer.metersAt(_navigationNow);
    setState(() {
      _isRerouting = true;
      _routeError = null;
      _navigationStatus = 'Updating route from your current location…';
    });
    try {
      final routes = await CampusService.fetchRoutes(
          NavigationOrigin(
              id: 'current_location',
              label: 'My Current Location',
              coordinate: location,
              type: NavigationOriginType.currentLocation),
          destination,
          mode: _selectedTransportMode);
      final route =
          routes.firstWhere((route) => route.type == _selectedRouteType);
      if (route.points.isEmpty) {
        throw Exception('No mapped route is available.');
      }
      if (!mounted || generation != _navigationGeneration) return;
      setState(() {
        _walkingRoute = route;
        _isRerouting = false;
        _navigationStatus = null;
        _routeError = null;
        _offRouteFixes = 0;
        _arrivalFixes = 0;
      });
      _refreshNavigationProgress();
    } catch (error) {
      if (!mounted || generation != _navigationGeneration) return;
      setState(() {
        _isRerouting = false;
        _routeError =
            'Route update failed. ${error.toString().replaceFirst('Exception: ', '')}';
        _navigationStatus = _routeError;
      });
    }
  }

  void _openRoutePreview() {
    final steps = _routePreviewSteps;
    if (steps.isEmpty) return;
    _recordHistory(NavigationHistoryStatus.previewed);
    setState(() {
      _previewStepIndex = 0;
      _navigationState = NavigationUiState.routePreview;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final coordinate = _currentPreviewStep?.coordinate;
      if (mounted && coordinate != null) {
        _mapController.move(coordinate, 18.5);
      }
    });
  }

  void _showPreviewStep(int requestedIndex) {
    final steps = _routePreviewSteps;
    if (steps.isEmpty) return;
    final index = requestedIndex < 0
        ? 0
        : requestedIndex >= steps.length
            ? steps.length - 1
            : requestedIndex;
    setState(() => _previewStepIndex = index);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final coordinate = _currentPreviewStep?.coordinate;
      if (mounted && coordinate != null) {
        _mapController.move(coordinate, 18.5);
      }
    });
  }

  Future<void> _confirmEndNavigation() async {
    final shouldEnd = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('End navigation?'),
        content: const Text('Your current route progress will be cleared.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Continue Navigation'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('End Route'),
          ),
        ],
      ),
    );
    if (shouldEnd == true && mounted) {
      _recordHistory(NavigationHistoryStatus.endedEarly);
      _cancelDirections();
    }
  }

  String? _categoryFromSearchQuery(String rawQuery) {
    final q = rawQuery.trim().toLowerCase();
    if (q.isEmpty) return null;
    if (const {
      'college',
      'colleges',
      'academic',
      'academic building',
    }.contains(q)) {
      return 'College';
    }
    if (const {
      'campus service',
      'campus services',
      'service',
      'services',
    }.contains(q)) {
      return 'Campus services';
    }
    if (const {
      'food',
      'foods',
      'canteen',
      'cafeteria',
      'dining',
      'eatery',
      'snack',
    }.contains(q)) {
      return 'Food';
    }
    if (const {
      'parking',
      'parkings',
      'park',
      'parking area',
      'car park',
    }.contains(q)) {
      return 'Parking';
    }
    if (const {
      'facility',
      'facilities',
    }.contains(q)) {
      return 'Facility';
    }
    if (const {
      'room',
      'rooms',
      'classroom',
      'classrooms',
    }.contains(q)) {
      return 'Room';
    }
    if (const {
      'office',
      'offices',
    }.contains(q)) {
      return 'Office';
    }
    if (const {
      'laboratory',
      'laboratories',
      'lab',
      'labs',
    }.contains(q)) {
      return 'Laboratory';
    }
    if (const {
      'restroom',
      'restrooms',
      'cr',
      'crs',
      'comfort room',
      'comfort rooms',
      'toilet',
      'toilets',
      'washroom',
    }.contains(q)) {
      return 'Restroom';
    }
    return null;
  }

  BuildingMarkerStyle _markerStyleForCurrentFilter(CampusBuilding building) {
    final activeCategory = _selectedCategoryFilter != 'All'
        ? _selectedCategoryFilter
        : _categoryFromSearchQuery(_searchController.text);

    switch (activeCategory) {
      case 'College':
      case 'Colleges':
        return const BuildingMarkerStyle(
          icon: Icons.school,
          color: Color(0xFF0F751B),
        );
      case 'Campus services':
        return const BuildingMarkerStyle(
          icon: Icons.support_agent,
          color: Color(0xFFEA580C),
        );
      case 'Food':
        return const BuildingMarkerStyle(
          icon: Icons.restaurant,
          color: Color(0xFFD97706),
        );
      case 'Parking':
      case 'Parkings':
        return const BuildingMarkerStyle(
          icon: Icons.local_parking,
          color: Color(0xFF2563EB),
        );
      case 'Facility':
        return const BuildingMarkerStyle(
          icon: Icons.domain,
          color: Color(0xFF0F751B),
        );
      case 'Room':
        return const BuildingMarkerStyle(
          icon: Icons.meeting_room,
          color: Color(0xFF0F751B),
        );
      case 'Office':
        return const BuildingMarkerStyle(
          icon: Icons.business_center,
          color: Color(0xFF0F751B),
        );
      case 'Laboratory':
        return const BuildingMarkerStyle(
          icon: Icons.science,
          color: Color(0xFF0891B2),
        );
      case 'Restroom':
        return const BuildingMarkerStyle(
          icon: Icons.wc,
          color: Color(0xFF475569),
        );
      default:
        return buildingMarkerStyle(building);
    }
  }

  bool _matchesCategoryFilter(CampusBuilding b, String filter) {
    if (filter == 'All') return true;

    final name = b.name.toLowerCase();
    final acronym = b.acronym.toLowerCase();
    final category = b.category.toLowerCase();
    final description = b.description.toLowerCase();
    final combined = '$category $name $acronym $description';

    final isParkingLocation = b.isParking ||
        category.contains('parking') ||
        name.contains('parking') ||
        acronym.contains('parking');

    if (filter == 'Parking' || filter == 'Parkings') {
      return isParkingLocation ||
          b.rooms.any((r) =>
              r.category == RoomCategory.parking ||
              r.title.toLowerCase().contains('parking'));
    }

    // Never show parking lots under non-parking category filters
    if (isParkingLocation) return false;

    switch (filter) {
      case 'College':
      case 'Colleges':
        return category.contains('college') ||
            category.contains('academic') ||
            name.contains('college') ||
            name.contains('school') ||
            name.contains('institute') ||
            const {
              'ccsict',
              'coe',
              'cbapa',
              'ca',
              'ced',
              'cas',
              'ccje',
              'cf',
              'con',
              'svm',
            }.contains(acronym);

      case 'Campus services':
        return category.contains('service') ||
            category.contains('admin') ||
            combined.contains('campus service') ||
            combined.contains('administration') ||
            combined.contains('osas') ||
            combined.contains('student affairs') ||
            combined.contains('student service') ||
            combined.contains('infirmary') ||
            combined.contains('clinic') ||
            combined.contains('health') ||
            combined.contains('library') ||
            combined.contains('security') ||
            combined.contains('guard') ||
            combined.contains('registrar') ||
            combined.contains('cashier') ||
            combined.contains('guidance') ||
            b.rooms.any((r) {
              final rt = r.title.toLowerCase();
              return r.category == RoomCategory.administrative ||
                  rt.contains('service') ||
                  rt.contains('registrar') ||
                  rt.contains('cashier') ||
                  rt.contains('clinic') ||
                  rt.contains('osas') ||
                  rt.contains('guidance');
            });

      case 'Food':
        return category.contains('food') ||
            combined.contains('canteen') ||
            combined.contains('cafeteria') ||
            combined.contains('food') ||
            combined.contains('dining') ||
            combined.contains('eatery') ||
            b.rooms.any((r) {
              final rt = r.title.toLowerCase();
              return rt.contains('canteen') ||
                  rt.contains('cafeteria') ||
                  rt.contains('food');
            });

      case 'Facility':
        return category.contains('facility') ||
            category.contains('facilities') ||
            combined.contains('gym') ||
            combined.contains('grandstand') ||
            combined.contains('auditorium') ||
            combined.contains('oval') ||
            combined.contains('court') ||
            combined.contains('dorm') ||
            combined.contains('hostel') ||
            combined.contains('chapel') ||
            combined.contains('church') ||
            combined.contains('center') ||
            combined.contains('hall') ||
            b.rooms.any((r) =>
                r.category == RoomCategory.facility ||
                r.category == RoomCategory.studyArea ||
                r.title.toLowerCase().contains('facility'));

      case 'Room':
        return category == 'room' ||
            b.rooms.any((r) =>
                r.category == RoomCategory.room ||
                r.category == RoomCategory.classroom ||
                r.title.toLowerCase().contains('room'));

      case 'Office':
        return category.contains('office') ||
            category.contains('admin') ||
            name.contains('office') ||
            name.contains('administration') ||
            b.rooms.any((r) =>
                r.category == RoomCategory.office ||
                r.category == RoomCategory.administrative ||
                r.category == RoomCategory.faculty ||
                r.title.toLowerCase().contains('office'));

      case 'Laboratory':
        return category.contains('lab') ||
            name.contains('lab') ||
            b.rooms.any((r) =>
                r.category == RoomCategory.laboratory ||
                r.title.toLowerCase().contains('lab'));

      case 'Restroom':
        final hasCrWord = RegExp(r'cr').hasMatch(combined);
        return category.contains('restroom') ||
            combined.contains('restroom') ||
            combined.contains('comfort room') ||
            combined.contains('toilet') ||
            combined.contains('washroom') ||
            hasCrWord ||
            b.rooms.any((r) {
              final rt = r.title.toLowerCase();
              final rd = (r.description ?? '').toLowerCase();
              return r.category == RoomCategory.restroom ||
                  rt.contains('restroom') ||
                  rt.contains('comfort room') ||
                  rt.contains('toilet') ||
                  rt.contains('washroom') ||
                  RegExp(r'cr').hasMatch(rt) ||
                  RegExp(r'cr').hasMatch(rd);
            });

      case 'Shaded':
        return b.hasShadedPath;

      default:
        return true;
    }
  }

  List<CampusBuilding> _getFilteredBuildings() {
    final query = _searchController.text.trim();
    final ids = query.isEmpty ? <String>{} : CampusSearch.search(
        isuCampusBuildings, query, origin: _currentUserLocation)
        .map((r) => r.building.id).toSet();
    return isuCampusBuildings.where((b) {
      if (query.isNotEmpty && !ids.contains(b.id)) return false;
      if (!_matchesCategoryFilter(b, _selectedCategoryFilter)) return false;
      return true;
    }).toList();
  }

  void _selectBuildingAndShowDetails(CampusBuilding building, {CampusRoom? room}) {
    setState(() {
      _selectedBuilding = building;
      _selectedRoom = room;
      _walkingRoute = null;
      _historySessionId = null;
      _navigationState = NavigationUiState.buildingDetails;
    });
    _mapController.move(building.coordinate, 17.5);
  }

  List<CampusBuilding> _getSuggestedBuildings() {
    if (isuCampusBuildings.isEmpty) return const [];

    final suggestions = <CampusBuilding>[];
    final addedIds = <String>{};

    // 1. Add recent destinations from navigation history if available
    for (final entry in _recentHistory) {
      final match = isuCampusBuildings
          .where((b) => b.id == entry.destinationId)
          .firstOrNull;
      if (match != null && addedIds.add(match.id)) {
        suggestions.add(match);
      }
    }

    // 2. Add prominent campus buildings by keyword matching
    const prominentKeywords = [
      'library',
      'ccsict',
      'administration',
      'admin',
      'canteen',
      'gym',
      'infirmary',
      'clinic',
      'engineering',
      'grandstand',
    ];

    for (final keyword in prominentKeywords) {
      for (final building in isuCampusBuildings) {
        if (addedIds.contains(building.id)) continue;
        final name = building.name.toLowerCase();
        final acronym = building.acronym.toLowerCase();
        if (name.contains(keyword) || acronym.contains(keyword)) {
          addedIds.add(building.id);
          suggestions.add(building);
          break;
        }
      }
      if (suggestions.length >= 8) break;
    }

    // 3. Fallback: Fill up to 6 buildings if still few
    for (final building in isuCampusBuildings) {
      if (suggestions.length >= 6) break;
      if (addedIds.add(building.id)) {
        suggestions.add(building);
      }
    }

    return suggestions;
  }

  List<SmartSearchResult> _getSmartSearchResults() {
    return CampusSearch.search(isuCampusBuildings, _searchController.text,
        origin: _currentUserLocation)
        .where((r) => _matchesCategoryFilter(r.building, _selectedCategoryFilter))
        .map((r) => SmartSearchResult(building: r.building,
            matchedRooms: r.room == null ? [] : [r.room!], isDirectMatch: true))
        .toList();
  }

  Future<void> _openSearchLocation(CampusBuilding building, {CampusRoom? room}) async {
    _searchController.clear();
    _searchFocusNode.unfocus();
    setState(() {
      _selectedBuilding = building;
      _selectedRoom = room;
      _walkingRoute = null;
      _historySessionId = null;
      _navigationState = NavigationUiState.idle;
    });
    _mapController.move(room?.coordinate ?? building.coordinate, 18);
    final navigate = await showDialog<bool>(context: context,
        builder: (_) => IndoorLocationDetailsDialog(building: building, room: room));
    if (!mounted || navigate != true) return;
    _selectBuildingAndShowDetails(building, room: room);
    setState(() {
      _hasSelectedOrigin = false;
      _applyDefaultOrigin();
      _navigationState = NavigationUiState.chooseRoute;
    });
    _locateForDefaultOrigin();
  }

  void _handleSearchSubmitted(String query) {
    if (query.trim().isEmpty) return;
    _searchFocusNode.unfocus();
    final results = _getSmartSearchResults();
    if (results.length == 1) {
      final result = results.first;
      _openSearchLocation(result.building, room: result.matchedRooms.firstOrNull);
    } else if (results.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('No location found matching "$query"')));
    }
  }

  Widget _buildFilterChip(String label, IconData icon) {
    final isSelected = _selectedCategoryFilter == label;
    return GestureDetector(
      onTap: () {
        _searchFocusNode.unfocus();
        setState(() {
          if (_selectedCategoryFilter == label && label != 'All') {
            _selectedCategoryFilter = 'All';
          } else {
            _selectedCategoryFilter = label;
          }
        });
      },
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFECC700) : const Color(0xFF174A2F),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFFECC700) : Colors.white24,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? Colors.black87 : Colors.white,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.montserrat(
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? Colors.black87 : Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSmartSearchPanel(double topPadding) {
    final query = _searchController.text.trim();
    final isQueryEmpty = query.isEmpty;
    final smartResults = _getSmartSearchResults();
    final suggestedBuildings = _getSuggestedBuildings();

    return Positioned(
      top: topPadding + 155,
      left: 16,
      right: 16,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(18),
        color: Colors.white,
        shadowColor: Colors.black26,
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.44,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: isQueryEmpty
                ? _buildSuggestedForYouContent(suggestedBuildings)
                : _buildSmartResultsContent(query, smartResults),
          ),
        ),
      ),
    );
  }

  Widget _buildSuggestedForYouContent(List<CampusBuilding> suggestedBuildings) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Suggested header with icon
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F751B).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.auto_awesome,
                  size: 15,
                  color: Color(0xFF0F751B),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'SUGGESTED FOR YOU',
                style: GoogleFonts.montserrat(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0B351E),
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              Text(
                'Campus Highlights',
                style: GoogleFonts.montserrat(
                  fontSize: 10.5,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),

        if (suggestedBuildings.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            child: Center(
              child: Text(
                'Explore ISU Echague campus buildings by searching or selecting a category.',
                textAlign: TextAlign.center,
                style: GoogleFonts.montserrat(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
            ),
          )
        else
          Flexible(
            child: ListView.separated(
              padding: const EdgeInsets.only(bottom: 8, top: 4),
              shrinkWrap: true,
              itemCount: suggestedBuildings.length,
              separatorBuilder: (_, __) => Divider(
                height: 1,
                indent: 16,
                endIndent: 16,
                color: Colors.grey.shade100,
              ),
              itemBuilder: (context, idx) {
                final bldg = suggestedBuildings[idx];
                final style = buildingMarkerStyle(bldg);
                final isRecent =
                    _recentHistory.any((h) => h.destinationId == bldg.id);
                return ListTile(
                  dense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                  leading: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: style.color.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(style.icon, color: style.color, size: 18),
                  ),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          bldg.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.montserrat(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      if (isRecent)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.history,
                                  size: 11, color: Colors.grey.shade700),
                              const SizedBox(width: 3),
                              Text(
                                'Recent',
                                style: GoogleFonts.montserrat(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  subtitle: Text(
                    bldg.acronym.isNotEmpty
                        ? '${bldg.acronym} • ${bldg.category}${bldg.rooms.isNotEmpty ? ' • ${bldg.rooms.length} Rooms' : ''}'
                        : '${bldg.category}${bldg.rooms.isNotEmpty ? ' • ${bldg.rooms.length} Rooms' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.montserrat(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  trailing: Icon(
                    Icons.north_west,
                    size: 14,
                    color: Colors.grey.shade400,
                  ),
                  onTap: () {
                    _searchController.clear();
                    _searchFocusNode.unfocus();
                    _openSearchLocation(bldg);
                  },
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildSmartResultsContent(
      String query, List<SmartSearchResult> smartResults) {
    if (smartResults.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 36, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            Text(
              'No matches found for "$query"',
              textAlign: TextAlign.center,
              style: GoogleFonts.montserrat(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Try typing "CCSICT", "Library", "Canteen", "Parking", or "CR".',
              textAlign: TextAlign.center,
              style: GoogleFonts.montserrat(
                fontSize: 11,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Text(
            'SEARCH RESULTS (${smartResults.length})',
            style: GoogleFonts.montserrat(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade600,
              letterSpacing: 0.5,
            ),
          ),
        ),
        Flexible(
          child: ListView.separated(
            padding: const EdgeInsets.only(bottom: 8),
            shrinkWrap: true,
            itemCount: smartResults.length,
            separatorBuilder: (_, __) => Divider(
              height: 1,
              indent: 16,
              endIndent: 16,
              color: Colors.grey.shade100,
            ),
            itemBuilder: (context, idx) {
              final result = smartResults[idx];
              final bldg = result.building;
              final style = buildingMarkerStyle(bldg);

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    dense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                    leading: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: style.color.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(style.icon, color: style.color, size: 18),
                    ),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            result.matchedRooms.firstOrNull?.title ?? bldg.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.montserrat(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                        if (bldg.rooms.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F751B).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${bldg.rooms.length} Rooms',
                              style: GoogleFonts.montserrat(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF0F751B),
                              ),
                            ),
                          ),
                      ],
                    ),
                    subtitle: Text(
                      bldg.acronym.isNotEmpty
                          ? '${bldg.acronym} • ${bldg.category}'
                          : bldg.category,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.montserrat(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    onTap: () {
                      _searchController.clear();
                      _searchFocusNode.unfocus();
                      _openSearchLocation(bldg, room: result.matchedRooms.firstOrNull);
                    },
                  ),
                  if (result.matchedRooms.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(48, 0, 14, 8),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: result.matchedRooms.take(3).map((room) {
                          return InkWell(
                            onTap: () {
                              _searchController.clear();
                              _searchFocusNode.unfocus();
                              _openSearchLocation(bldg, room: room);
                            },
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEAF5EC),
                                borderRadius: BorderRadius.circular(6),
                                border:
                                    Border.all(color: const Color(0xFFC3DFC8)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.meeting_room,
                                    size: 11,
                                    color: Color(0xFF0F751B),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${room.title} (${room.floor})',
                                    style: GoogleFonts.montserrat(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFF0F5A28),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final filteredBuildings = _getFilteredBuildings();
    final mapBuildings = _withRouteDestination(filteredBuildings);

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F5),
      body: Stack(
        children: [
          // 1. Interactive Full-Screen Campus Map Canvas
          Positioned.fill(
            key: const ValueKey('campus-map'),
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: isuCampusCenter,
                initialZoom: _initialCampusZoom,
                minZoom: 15.5,
                maxZoom: 19.5,
                // Desktop viewports can be wider than the campus bounds.
                // Constrain the center so resizing never invalidates the camera.
                cameraConstraint: CameraConstraint.containCenter(
                  bounds: isuEchagueBounds,
                ),
                onTap: (_, __) {
                  _searchFocusNode.unfocus();
                  if (_navigationState == NavigationUiState.buildingDetails) {
                    setState(() {
                      _navigationState = NavigationUiState.idle;
                    });
                  }
                },
                onPositionChanged: (camera, hasGesture) {
                  final zoom = camera.zoom;
                  if ((_mapZoom.value - zoom).abs() > 0.001) {
                    _mapZoom.value = zoom;
                  }
                  if (hasGesture &&
                      _navigationState == NavigationUiState.navigating &&
                      _followNavigationCamera) {
                    setState(() => _followNavigationCamera = false);
                  }
                },
              ),
              children: [
                // OpenStreetMap tiles, served from the offline pack when
                // one is downloaded. The key rebuilds the layer after a
                // download so freshly cached tiles are picked up.
                TileLayer(
                  key: ValueKey(
                      'tiles-${OfflinePackService.instance.status.installedVersion ?? 'live'}'),
                  urlTemplate: campusTileUrlTemplate,
                  userAgentPackageName: campusTileUserAgent,
                  tileProvider: OfflineAwareTileProvider(),
                ),

                PolygonLayer(
                  polygons: [
                    ...mapBuildings
                        .where((building) =>
                            building.polygonCoordinates.length >= 3 &&
                            !_highlightsDestination(building))
                        .map((building) => Polygon(
                              points: building.polygonCoordinates,
                              color: const Color(0xFF0F751B)
                                  .withValues(alpha: 0.18),
                              borderColor: const Color(0xFF0F751B),
                              borderStrokeWidth: 1.5,
                            )),
                    // Drawn last so the destination sits above its neighbours.
                    ...mapBuildings
                        .where((building) =>
                            building.polygonCoordinates.length >= 3 &&
                            _highlightsDestination(building))
                        .map((building) => Polygon(
                              points: building.polygonCoordinates,
                              color: const Color(0xFFECC700)
                                  .withValues(alpha: 0.32),
                              borderColor: const Color(0xFFECC700),
                              borderStrokeWidth: 3,
                            )),
                    Polygon(
                      points: isuEchagueMockBoundary,
                      color: const Color(0xFF0F751B).withValues(alpha: 0.05),
                      borderColor: const Color(0xFF0F751B),
                      borderStrokeWidth: 2,
                    ),
                  ],
                ),

                // Active Route Polylines (if route chosen or navigating)
                if (_walkingRoute != null &&
                    (_navigationState == NavigationUiState.routeDetails ||
                        _navigationState == NavigationUiState.routePreview ||
                        _navigationState == NavigationUiState.navigating))
                  // Follows the smoothed position, so the line shrinks with
                  // the arrow between GPS fixes.
                  ValueListenableBuilder<LatLng?>(
                    valueListenable: _navigationPosition,
                    builder: (context, position, _) => PolylineLayer(
                      polylines: [
                        Polyline(
                          points: _visibleRoutePoints(position),
                          strokeWidth: 5.0,
                          color: navigationRouteBlue,
                          borderColor: Colors.white,
                          borderStrokeWidth: 2.0,
                        ),
                      ],
                    ),
                  ),

                // Building names fade first; icons fade at the farthest zoom.
                // Icons and names stay upright however the map is rotated.
                ValueListenableBuilder<double>(
                  valueListenable: _mapZoom,
                  builder: (context, zoom, _) => MarkerLayer(
                    rotate: true,
                    markers: mapBuildings.map((building) {
                      final isSelected = _selectedBuilding?.id == building.id;
                      final markerStyle = _markerStyleForCurrentFilter(building);
                      final opacity =
                          buildingIconOpacity(zoom, isSelected: isSelected);
                      return Marker(
                        key: ValueKey('building-marker-${building.id}'),
                        point: building.coordinate,
                        width: 38,
                        height: 38,
                        child: IgnorePointer(
                          ignoring: opacity == 0,
                          child: ExcludeSemantics(
                            excluding: opacity == 0,
                            child: AnimatedOpacity(
                              key: ValueKey('building-icon-${building.id}'),
                              opacity: opacity,
                              duration: const Duration(milliseconds: 180),
                              curve: Curves.easeOut,
                              child: Semantics(
                                button: true,
                                label: building.name,
                                child: Tooltip(
                                  message: building.name,
                                  child: GestureDetector(
                                    onTap: () =>
                                        _selectBuildingAndShowDetails(building),
                                    child: Center(
                                      child: AnimatedContainer(
                                        duration:
                                            const Duration(milliseconds: 220),
                                        width: isSelected ? 32 : 28,
                                        height: isSelected ? 32 : 28,
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? const Color(0xFFECC700)
                                              : markerStyle.color,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: Colors.white,
                                            width: isSelected ? 2.5 : 2,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black
                                                  .withValues(alpha: 0.24),
                                              blurRadius: isSelected ? 6 : 4,
                                              offset: const Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: Icon(
                                          markerStyle.icon,
                                          color: isSelected
                                              ? Colors.black87
                                              : Colors.white,
                                          size: isSelected ? 18 : 16,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),

                // Labels appear progressively as the user zooms in. They never
                // take taps away from the icon markers underneath. Both turn
                // around the building's point, so the name stays below the
                // icon on screen.
                ValueListenableBuilder<double>(
                  valueListenable: _mapZoom,
                  builder: (context, zoom, _) => MarkerLayer(
                    rotate: true,
                    markers: mapBuildings.map((building) {
                      return Marker(
                        point: building.coordinate,
                        width: 120,
                        height: 25,
                        alignment: Alignment.topCenter,
                        child: IgnorePointer(
                          child: ExcludeSemantics(
                            child: AnimatedOpacity(
                              key: ValueKey('building-label-${building.id}'),
                              opacity: buildingLabelOpacity(zoom),
                              duration: const Duration(milliseconds: 180),
                              curve: Curves.easeOut,
                              child: Transform.translate(
                                // Keep the label below the entire icon, not
                                // across its lower half at the map anchor.
                                offset: const Offset(0, 40),
                                child: Center(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.white.withValues(alpha: 0.94),
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                    child: Text(
                                      building.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.montserrat(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: const Color(0xFF0B351E),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),

                if (_showsTransportOriginMarker)
                  ListenableBuilder(
                    listenable: Listenable.merge(
                        [_navigationPosition, _navigationHeading]),
                    builder: (context, _) => MarkerLayer(
                      markers: [
                        Marker(
                          point:
                              _navigationState == NavigationUiState.navigating
                                  ? _navigationPosition.value ??
                                      _currentUserLocation ??
                                      _selectedOrigin.coordinate
                                  : _walkingRoute?.points.first ??
                                      _selectedOrigin.coordinate,
                          width: 42,
                          height: 42,
                          child: _buildTransportOriginMarker(),
                        ),
                      ],
                    ),
                  ),

                if (_navigationState == NavigationUiState.routePreview &&
                    _currentPreviewStep?.coordinate != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _currentPreviewStep!.coordinate!,
                        width: 46,
                        height: 46,
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF1D4ED8),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                            boxShadow: const [
                              BoxShadow(color: Colors.black38, blurRadius: 8),
                            ],
                          ),
                          child: Transform.rotate(
                            angle: (routeHeading(_routePoints,
                                        _currentPreviewStep!.coordinate!) ??
                                    0) *
                                math.pi /
                                180,
                            child: const Icon(
                              Icons.navigation,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                if (_navigationState == NavigationUiState.routePreview &&
                    _routeEtaLabelPoint != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _routeEtaLabelPoint!,
                        rotate: true,
                        width: 76,
                        // Space for both the ETA pill and its map pointer.
                        // A 48px marker clipped this Column by about 3px.
                        height: 56,
                        alignment: Alignment.topCenter,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: navigationRouteBlue,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2,
                                ),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black26,
                                    blurRadius: 6,
                                  ),
                                ],
                              ),
                              child: Text(
                                _walkingRoute!.time,
                                style: GoogleFonts.montserrat(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const Icon(
                              Icons.arrow_drop_down,
                              color: navigationRouteBlue,
                              size: 18,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                if (_currentUserLocation != null &&
                    !(_showsTransportOriginMarker &&
                        _selectedOrigin.type ==
                            NavigationOriginType.currentLocation))
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _currentUserLocation!,
                        width: 112,
                        height: 112,
                        child: ValueListenableBuilder<double?>(
                          valueListenable: _deviceHeading,
                          builder: (context, heading, _) =>
                              LocationPuck(heading: heading),
                        ),
                      ),
                    ],
                  ),

                RichAttributionWidget(
                  attributions: [
                    TextSourceAttribution(
                      'OpenStreetMap contributors',
                      onTap: () {},
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Floating Map Action Buttons (Recenter & Zoom)
          if (isuCampusBuildings.isEmpty)
            Center(
              key: const ValueKey('campus-loading-status'),
              child: Container(
                margin: const EdgeInsets.all(24),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 12),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_isLoadingBuildings)
                      const CircularProgressIndicator()
                    else
                      const Icon(
                        Icons.location_off_outlined,
                        size: 42,
                        color: Color(0xFF0F751B),
                      ),
                    const SizedBox(height: 10),
                    Text(
                      _isLoadingBuildings
                          ? 'Loading campus locations...'
                          : _buildingsError ??
                              'No campus locations available yet.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.montserrat(
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF0B351E),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Campus locations are loaded from the database.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.montserrat(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    if (!_isLoadingBuildings)
                      TextButton.icon(
                        onPressed: _loadBuildings,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                  ],
                ),
              ),
            ),

          // Update notice for a downloaded map. Never starts a download.
          if (hasOfflineUpdate() &&
              !_offlineUpdateDismissed &&
              _navigationState == NavigationUiState.idle)
            Positioned(
              key: const ValueKey('offline-update-banner'),
              left: 16,
              right: 16,
              bottom: 24,
              child: OfflineUpdateBanner(
                onDismiss: () => setState(() => _offlineUpdateDismissed = true),
              ),
            ),

          if (!_isNavigationActive &&
              _navigationState != NavigationUiState.chooseRoute)
            Positioned(
              key: const ValueKey('map-action-buttons'),
              right: 16,
              top: topPadding + 170,
              child: Column(
                children: [
                  // Recenter to ISU Echague Main Gate
                  FloatingActionButton.small(
                    heroTag: 'btn_recenter',
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF0F751B),
                    elevation: 4,
                    onPressed: () {
                      if (_currentUserLocation != null) {
                        _mapController.move(_currentUserLocation!, 18.0);
                      } else {
                        _initializeCurrentLocation();
                        _mapController.move(isuCampusCenter, 16.8);
                      }
                    },
                    child: const Icon(Icons.my_location, size: 20),
                  ),
                  const SizedBox(height: 10),
                  // Zoom In
                  FloatingActionButton.small(
                    heroTag: 'btn_zoom_in',
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF0F751B),
                    elevation: 4,
                    onPressed: () {
                      final currentZoom = _mapController.camera.zoom;
                      _mapController.move(
                        _mapController.camera.center,
                        (currentZoom + 1).clamp(15.5, 19.5),
                      );
                    },
                    child: const Icon(Icons.add, size: 20),
                  ),
                  const SizedBox(height: 8),
                  // Zoom Out
                  FloatingActionButton.small(
                    heroTag: 'btn_zoom_out',
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF0F751B),
                    elevation: 4,
                    onPressed: () {
                      final currentZoom = _mapController.camera.zoom;
                      _mapController.move(
                        _mapController.camera.center,
                        (currentZoom - 1).clamp(15.5, 19.5),
                      );
                    },
                    child: const Icon(Icons.remove, size: 20),
                  ),
                ],
              ),
            ),

          // 2. Dark Green Header Bar
          if (!_isNavigationActive &&
              _navigationState != NavigationUiState.chooseRoute)
            Positioned(
              key: const ValueKey('map-header'),
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: EdgeInsets.fromLTRB(20, topPadding + 10, 20, 14),
                decoration: const BoxDecoration(
                  color: Color(0xFF0B351E),
                  borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(28),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            SizedBox(
                              width: 28,
                              height: 28,
                              child: ClipOval(
                                child: Image.asset(
                                  'assets/images/logo_kumpas_app.png',
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) =>
                                      const Icon(
                                    Icons.navigation,
                                    color: Colors.white,
                                    size: 22,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'KUMPAS',
                              style: GoogleFonts.montserrat(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.6,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            GestureDetector(
                              onTap: () async {
                                await _historyWriteQueue;
                                if (!context.mounted) return;
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => UserInfoScreen(
                                      onNavigateToHistory: (entry) {
                                        final destination = isuCampusBuildings
                                            .where((b) =>
                                                b.id == entry.destinationId)
                                            .firstOrNull;
                                        if (destination == null) return;
                                        _selectBuildingAndShowDetails(
                                            destination);
                                        setState(() {
                                          _selectedRoom = destination.rooms
                                              .where(
                                                  (r) => r.id == entry.roomId)
                                              .firstOrNull;
                                          _applyDefaultOrigin();
                                          _walkingRoute = null;
                                          _navigationState =
                                              NavigationUiState.chooseRoute;
                                        });
                                        _locateForDefaultOrigin();
                                      },
                                    ),
                                  ),
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF174A2F),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white24,
                                    width: 1,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.person_outline,
                                  color: Colors.white,
                                  size: 22,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            SizedBox(
                              width: 36,
                              height: 36,
                              child: ClipOval(
                                child: Image.asset(
                                  'assets/images/logo_isu_png.png',
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) =>
                                      const Icon(
                                    Icons.school,
                                    color: Colors.white,
                                    size: 24,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // Search Field Bar
                    Container(
                      height: 42,
                      decoration: BoxDecoration(
                        color: const Color(0xFF174A2F),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.search,
                            color: Colors.white70,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              focusNode: _searchFocusNode,
                              // The result panel is outside this TextField. Keep
                              // it mounted through a desktop mouse click; map
                              // taps and result selection explicitly unfocus.
                              onTapOutside: (_) {},
                              textInputAction: TextInputAction.search,
                              onSubmitted: _handleSearchSubmitted,
                              onChanged: (val) => setState(() {}),
                              style: GoogleFonts.montserrat(
                                color: Colors.white,
                                fontSize: 13,
                              ),
                              decoration: InputDecoration(
                                hintText:
                                    'Search building, parking, or room...',
                                hintStyle: GoogleFonts.montserrat(
                                  color: Colors.white60,
                                  fontSize: 12.5,
                                ),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          ),
                          if (_searchController.text.isNotEmpty ||
                              _searchFocusNode.hasFocus)
                            GestureDetector(
                              onTap: () {
                                _searchController.clear();
                                _searchFocusNode.unfocus();
                                setState(() {});
                              },
                              child: const Icon(
                                Icons.close,
                                color: Colors.white70,
                                size: 18,
                              ),
                            ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 10),

                    // Category Filter Chips Row
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: Row(
                        children: [
                          _buildFilterChip('All', Icons.grid_view),
                          _buildFilterChip('College', Icons.school),
                          _buildFilterChip(
                              'Campus services', Icons.support_agent),
                          _buildFilterChip('Food', Icons.restaurant),
                          _buildFilterChip('Parking', Icons.local_parking),
                          _buildFilterChip('Facility', Icons.domain),
                          _buildFilterChip('Room', Icons.meeting_room),
                          _buildFilterChip('Office', Icons.business_center),
                          _buildFilterChip('Laboratory', Icons.science),
                          _buildFilterChip('Restroom', Icons.wc),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Smart Search & "Suggested for you" Floating Panel
          if (!_isNavigationActive && _searchFocusNode.hasFocus)
            _buildSmartSearchPanel(topPadding),

          // 3. Bottom Sheet Overlay State Machine
          if (_locationStatus != null &&
              _searchController.text.trim().isEmpty &&
              !_isNavigationActive &&
              _navigationState != NavigationUiState.chooseRoute)
            Positioned(
              top: topPadding + 170,
              left: 16,
              right: 76,
              child: Material(
                color: Colors.white,
                elevation: 3,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _isLocating ? Icons.gps_fixed : Icons.location_off,
                        size: 18,
                        color: const Color(0xFF0F751B),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _isLocating
                              ? 'Getting your current location...'
                              : _locationStatus!,
                          style: GoogleFonts.montserrat(fontSize: 10.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          if (_selectedBuilding != null &&
              _navigationState == NavigationUiState.buildingDetails)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: BuildingDetailsSheet(
                building: _selectedBuilding!,
                onClose: () {
                  setState(() {
                    _navigationState = NavigationUiState.idle;
                  });
                },
                onDirectionsTap: () {
                  setState(() {
                    _historySessionId = null;
                    _selectedRoom = null;
                    _applyDefaultOrigin();
                    _walkingRoute = null;
                    _navigationState = NavigationUiState.chooseRoute;
                  });
                  _locateForDefaultOrigin();
                },
                onRoomDirectionsTap: (room) {
                  setState(() {
                    _historySessionId = null;
                    _selectedRoom = room;
                    _walkingRoute = null;
                    _applyDefaultOrigin();
                    _navigationState = NavigationUiState.chooseRoute;
                  });
                  _locateForDefaultOrigin();
                },
              ),
            ),

          if (_navigationState == NavigationUiState.chooseRoute)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: topPadding + 100,
              child: const ColoredBox(color: Color(0xFF0B351E)),
            ),

          if (_selectedBuilding != null &&
              _navigationState == NavigationUiState.chooseRoute)
            Positioned(
              top: topPadding + 32,
              bottom: 0,
              left: 0,
              right: 0,
              child: ChooseRouteSheet(
                destination: _selectedBuilding!,
                destinationRoom: _selectedRoom,
                origin: _selectedOrigin,
                hasSelectedOrigin: _hasSelectedOrigin,
                origins: _availableOrigins,
                isLocating: _isLocating,
                locationStatus: _locationStatus,
                isCurrentLocationInsideCampus: _currentUserLocation != null &&
                    isuEchagueBounds.contains(_currentUserLocation!),
                onUseCurrentLocation: _useCurrentLocationAsOrigin,
                onOriginSelected: (origin) {
                  setState(() {
                    _selectedOrigin = origin;
                    _hasSelectedOrigin = true;
                    _walkingRoute = null;
                  });
                },
                initialRouteType: _selectedRouteType,
                initialTransportMode: _selectedTransportMode,
                onTransportModeChanged: (mode) {
                  setState(() => _selectedTransportMode = mode);
                },
                onBack: () {
                  setState(() {
                    _navigationState = NavigationUiState.buildingDetails;
                  });
                },
                onCancel: _cancelDirections,
                onViewRoute: (route, mode) {
                  setState(() {
                    _selectedRouteType = route.type;
                    _walkingRoute = route;
                    _selectedTransportMode = mode;
                    _navigationState = NavigationUiState.routeDetails;
                  });
                },
              ),
            ),

          if (_selectedBuilding != null &&
              _navigationState == NavigationUiState.routeDetails)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: RouteDetailsSheet(
                route: _walkingRoute!,
                destination: _selectedBuilding!,
                destinationRoom: _selectedRoom,
                origin: _selectedOrigin,
                selectedRouteType: _selectedRouteType,
                selectedTransportMode: _selectedTransportMode,
                onBack: () {
                  setState(() {
                    _navigationState = NavigationUiState.chooseRoute;
                  });
                },
                onCancel: _cancelDirections,
                onPreviewRoute: _openRoutePreview,
                onStartNavigation: _startNavigation,
              ),
            ),

          if (_selectedBuilding != null &&
              _walkingRoute != null &&
              _navigationState == NavigationUiState.routePreview &&
              _currentPreviewStep != null)
            Positioned.fill(
              child: RoutePreviewHud(
                route: _walkingRoute!,
                selectedRouteType: _selectedRouteType,
                step: _currentPreviewStep!,
                currentStepIndex: _previewStepIndex,
                totalSteps: _routePreviewSteps.length,
                onBack: () {
                  setState(() {
                    _navigationState = NavigationUiState.routeDetails;
                  });
                },
                onPrevious: _previewStepIndex > 0
                    ? () => _showPreviewStep(_previewStepIndex - 1)
                    : null,
                onNext: _previewStepIndex < _routePreviewSteps.length - 1
                    ? () => _showPreviewStep(_previewStepIndex + 1)
                    : null,
              ),
            ),

          // 4. Full-Screen Turn-by-Turn Navigation HUD
          if (_selectedBuilding != null &&
              _navigationState == NavigationUiState.navigating)
            Positioned.fill(
              child: ActiveNavigationHud(
                route: _walkingRoute!,
                destination: _selectedBuilding!,
                destinationRoom: _selectedRoom,
                origin: _selectedOrigin,
                selectedRouteType: _selectedRouteType,
                selectedTransportMode: _selectedTransportMode,
                onEndRoute: _confirmEndNavigation,
                progress: _liveProgress,
                navigationStatus: _navigationStatus,
                onRecenter: _resumeNavigationFollowing,
                onRetryRoute: !_isRerouting && _navigationStatus != null
                    ? () async {
                        await _initializeCurrentLocation();
                        if (mounted) await _reroute(force: true);
                      }
                    : null,
              ),
            ),

          if (_navigationState == NavigationUiState.navigating)
            Positioned(
              right: 16,
              top: topPadding + 150,
              child: FloatingActionButton.small(
                heroTag: 'btn_follow_navigation',
                tooltip: _followNavigationCamera
                    ? 'Following your direction'
                    : 'Recenter and follow direction',
                backgroundColor: _followNavigationCamera
                    ? navigationRouteBlue
                    : Colors.white,
                foregroundColor: _followNavigationCamera
                    ? Colors.white
                    : navigationRouteBlue,
                onPressed: _resumeNavigationFollowing,
                child: Icon(
                  _followNavigationCamera
                      ? Icons.navigation
                      : Icons.my_location,
                  size: 21,
                ),
              ),
            ),

          // 5. "You've Arrived!" HUD (Mockup Screen)
          if (_selectedBuilding != null &&
              _navigationState == NavigationUiState.arrived)
            Positioned.fill(
              child: ArrivalHud(
                destination: _selectedBuilding!,
                destinationRoom: _selectedRoom,
                onFinish: _cancelDirections,
              ),
            ),
        ],
      ),
    );
  }
}

class SmartSearchResult {
  final CampusBuilding building;
  final List<CampusRoom> matchedRooms;
  final bool isDirectMatch;

  const SmartSearchResult({
    required this.building,
    this.matchedRooms = const [],
    this.isDirectMatch = false,
  });
}
