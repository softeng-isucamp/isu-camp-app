import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isu_camp_app/features/dashboard/models/campus_models.dart';
import 'package:isu_camp_app/features/dashboard/widgets/navigation_sheets.dart';
import 'package:latlong2/latlong.dart';

void main() {
  const origin = NavigationOrigin(
    id: 'origin',
    label: 'Mock Origin',
    coordinate: LatLng(16.7216, 121.6917),
    type: NavigationOriginType.campusCenter,
  );
  const destination = CampusBuilding(
    id: 'destination',
    name: 'Mock Destination',
    acronym: 'MD',
    category: 'Academic',
    description: '',
    coordinate: LatLng(16.7187, 121.6884),
    rooms: [
      CampusRoom(
        id: 'room',
        title: 'Room 1',
        category: RoomCategory.classroom,
        floor: '1st Floor',
        icon: Icons.meeting_room,
      ),
    ],
  );
  const currentLocation = NavigationOrigin(
    id: 'current_location',
    label: 'My Current Location',
    coordinate: LatLng(16.7216, 121.6917),
    type: NavigationOriginType.currentLocation,
  );
  const buildingOrigin = NavigationOrigin(
    id: 'college_of_medicine',
    label: 'College of Medicine',
    coordinate: LatLng(16.7201, 121.6902),
    type: NavigationOriginType.campusLocation,
  );

  test('route modes use consistent transport icons', () {
    expect(routeModeIcon(TransportMode.car), Icons.directions_car);
    expect(routeModeIcon(TransportMode.motorcycle), Icons.two_wheeler);
    expect(routeModeIcon(TransportMode.bicycle), Icons.pedal_bike);
    expect(routeModeIcon(TransportMode.walking), Icons.directions_walk);
  });

  testWidgets(
      'only current location can start navigation; all origins can preview',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final route = WalkingRoute.fromJson({
      'type': 'shortest',
      'distanceMeters': 120,
      'estimatedMinutes': 2,
      'startNodeName': 'Entrance',
      'pathPoints': [
        [16.7216, 121.6917],
        [16.7220, 121.6920]
      ],
      'steps': [],
    });
    var starts = 0;
    var previews = 0;
    for (final selectedOrigin in [buildingOrigin, origin, currentLocation]) {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RouteDetailsSheet(
              route: route,
              destination: destination,
              origin: selectedOrigin,
              selectedRouteType: RouteType.shortest,
              onBack: () {},
              onCancel: () {},
              onPreviewRoute: () => previews++,
              onStartNavigation: () => starts++,
            ),
          ),
        ),
      ));
      await tester.ensureVisible(find.text('Preview'));
      await tester.tap(find.text('Preview'));
      if (selectedOrigin.type == NavigationOriginType.currentLocation) {
        expect(find.text('Start'), findsOneWidget);
        await tester.tap(find.text('Start'));
      } else {
        expect(find.text('Start'), findsNothing);
        expect(find.textContaining('Preview only.'), findsOneWidget);
      }
    }
    expect(previews, 3);
    expect(starts, 1);
  });

  test('walking route keeps structured preview step details', () {
    final route = WalkingRoute.fromJson({
      'type': 'shortest',
      'distanceMeters': 120,
      'estimatedMinutes': 2,
      'startNodeName': 'College entrance',
      'pathPoints': [
        [16.7216, 121.6917],
        [16.7220, 121.6920],
      ],
      'steps': [
        {
          'instruction': 'Turn left toward OSAS',
          'distanceMeters': 35,
          'coordinate': [16.7218, 121.6918],
        },
      ],
    });

    expect(route.steps, hasLength(1));
    expect(route.steps.first.instruction, 'Turn left toward OSAS');
    expect(route.steps.first.distance, '35 m');
    expect(route.steps.first.coordinate, const LatLng(16.7218, 121.6918));
    expect(
        routeInstructionIcon(route.steps.first.instruction), Icons.turn_left);
  });

  test('mock route metrics use origin, preference, and transport mode', () {
    final shortestDistance = int.parse(
      RouteMetricsHelper.getDistanceString(
        origin,
        destination,
        RouteType.shortest,
        TransportMode.walking,
      ).replaceAll('m', ''),
    );
    final shadedDistance = int.parse(
      RouteMetricsHelper.getDistanceString(
        origin,
        destination,
        RouteType.comfortableShaded,
        TransportMode.walking,
      ).replaceAll('m', ''),
    );
    final walkingMinutes = int.parse(
      RouteMetricsHelper.getTimeString(
        origin,
        destination,
        RouteType.shortest,
        TransportMode.walking,
      ).split(' ').first,
    );
    final bicycleMinutes = int.parse(
      RouteMetricsHelper.getTimeString(
        origin,
        destination,
        RouteType.shortest,
        TransportMode.bicycle,
      ).split(' ').first,
    );

    expect(shortestDistance, greaterThan(0));
    expect(shadedDistance, greaterThan(shortestDistance));
    expect(walkingMinutes, greaterThanOrEqualTo(bicycleMinutes));
  });

  testWidgets('starting point shows current location and expandable buildings',
      (tester) async {
    NavigationOrigin? selected;
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ChooseStartingPointSheet(
              destination: destination,
              origins: const [currentLocation, buildingOrigin],
              selectedOrigin: origin,
              hasSelectedOrigin: false,
              isLocating: false,
              locationStatus: null,
              isCurrentLocationInsideCampus: true,
              onUseCurrentLocation: () async {},
              onOriginSelected: (value) => selected = value,
              onBack: () {},
              onCancel: () {},
              onContinue: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Use My Current Location'), findsOneWidget);
    expect(find.text('Others'), findsOneWidget);
    expect(find.text('College of Medicine'), findsNothing);

    final continueButton = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Continue to Route Options'),
    );
    expect(continueButton.onPressed, isNull);

    await tester.tap(find.text('Others'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('College of Medicine'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('College of Medicine'), findsOneWidget);

    await tester.tap(find.text('College of Medicine'));
    await tester.pump();
    expect(selected?.id, 'college_of_medicine');
  });

  testWidgets('outside-campus current location shows an error', (tester) async {
    var attempts = 0;
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ChooseStartingPointSheet(
              destination: destination,
              origins: const [currentLocation, buildingOrigin],
              selectedOrigin: origin,
              hasSelectedOrigin: false,
              isLocating: false,
              locationStatus:
                  'You are outside the supported ISU Echague campus area.',
              isCurrentLocationInsideCampus: false,
              onUseCurrentLocation: () async => attempts++,
              onOriginSelected: (_) {},
              onBack: () {},
              onCancel: () {},
              onContinue: () {},
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Use My Current Location'));
    await tester.pump();

    expect(attempts, 1);
    expect(
      find.text('You are outside the supported ISU Echague campus area.'),
      findsOneWidget,
    );
  });

  testWidgets('route preview shows step details and navigation controls',
      (tester) async {
    var nextCount = 0;
    final route = WalkingRoute.fromJson({
      'type': 'shortest',
      'distanceMeters': 120,
      'estimatedMinutes': 2,
      'startNodeName': 'College entrance',
      'pathPoints': [
        [16.7216, 121.6917],
        [16.7220, 121.6920],
      ],
      'steps': const [],
    });
    const step = WalkingRouteStep(
      instruction: 'Head north',
      distanceMeters: 40,
      coordinate: LatLng(16.7216, 121.6917),
    );
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RoutePreviewHud(
            route: route,
            selectedRouteType: RouteType.shortest,
            step: step,
            currentStepIndex: 0,
            totalSteps: 3,
            onBack: () {},
            onPrevious: null,
            onNext: () => nextCount++,
          ),
        ),
      ),
    );

    expect(find.text('Route Preview'), findsOneWidget);
    expect(find.text('Head north'), findsOneWidget);
    expect(find.text('40 m'), findsOneWidget);
    expect(find.text('Route Modes'), findsNothing);
    expect(find.textContaining('Shortest Route'), findsOneWidget);
    expect(find.text('Distance: 120 m'), findsOneWidget);
    expect(find.text('Est: 2 min'), findsOneWidget);
    expect(find.text('Step 1 of 3'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.chevron_right));
    expect(nextCount, 1);
  });
}
