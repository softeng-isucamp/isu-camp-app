import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:isu_camp_app/features/dashboard/models/campus_models.dart';
import 'package:isu_camp_app/features/dashboard/widgets/navigation_sheets.dart';
import 'package:latlong2/latlong.dart';

void main() {
  testWidgets('indoor photo never falls back to the building photo',
      (tester) async {
    const building = CampusBuilding(
      id: 'building-photo',
      name: 'Building',
      acronym: 'B',
      category: 'Academic',
      description: '',
      coordinate: LatLng(16, 121),
      imageUrl: 'assets/building.jpg',
    );
    for (final photo in <String?>[null, 'assets/room.jpg']) {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
        body: IndoorLocationDetailsDialog(
          building: building,
          room: CampusRoom(
              id: 'room',
              title: 'Room',
              category: RoomCategory.room,
              floor: 'Ground Floor',
              icon: Icons.meeting_room,
              imageUrl: photo),
        ),
      )));
      await tester.pumpAndSettle();
      expect(tester.widget<LocationPhoto>(find.byType(LocationPhoto)).imageUrl,
          photo);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('database photo data is displayed as a memory image',
      (tester) async {
    const photo = 'data:image/png;base64,'
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
      body: SizedBox(height: 180, child: LocationPhoto(imageUrl: photo)),
    )));
    await tester.pumpAndSettle();
    expect(tester.widget<Image>(find.byType(Image)).image, isA<MemoryImage>());
    expect(find.text('Photo unavailable'), findsNothing);
    expect(tester.takeException(), isNull);
  });

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
    acronym: 'COM',
    coordinate: LatLng(16.7201, 121.6902),
    type: NavigationOriginType.campusLocation,
  );
  const libraryOrigin = NavigationOrigin(
    id: 'main_library',
    label: 'Main Library',
    acronym: 'ML',
    coordinate: LatLng(16.7212, 121.6911),
    type: NavigationOriginType.campusLocation,
  );

  test('route modes use consistent transport icons', () {
    expect(routeModeIcon(TransportMode.car), Icons.directions_car);
    expect(routeModeIcon(TransportMode.motorcycle), Icons.two_wheeler);
    expect(routeModeIcon(TransportMode.bicycle), Icons.pedal_bike);
    expect(routeModeIcon(TransportMode.walking), Icons.directions_walk);
  });

  testWidgets('indoor details show building and floor before directions',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    CampusRoom? selected;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
      body: BuildingDetailsSheet(
        building: destination,
        onDirectionsTap: () {},
        onRoomDirectionsTap: (room) => selected = room,
      ),
    )));
    await tester.ensureVisible(find.text('Details'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(find.text('Building: Mock Destination'), findsOneWidget);
    expect(find.text('Floor: 1st Floor'), findsOneWidget);
    expect(find.text('Room name: Room 1'), findsOneWidget);
    expect(selected, isNull);
    await tester.tap(find.byTooltip('Close details'));
    await tester.pumpAndSettle();
    expect(find.byType(IndoorLocationDetailsDialog), findsNothing);
    expect(selected, isNull);
    await tester.ensureVisible(find.text('Details'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Get Directions'));
    await tester.pumpAndSettle();
    expect(selected, destination.rooms.first);
    expect(find.byType(IndoorLocationDetailsDialog), findsNothing);
  });

  testWidgets('location details tolerate a null room description',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
      body: IndoorLocationDetailsDialog(
        building: destination,
        room: const CampusRoom(
          id: 'legacy-room',
          title: 'Legacy Room',
          category: RoomCategory.room,
          floor: 'Ground Floor',
          icon: Icons.meeting_room,
          description: null,
        ),
      ),
    )));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Room name: Legacy Room'), findsOneWidget);
    expect(find.text('Get Directions'), findsOneWidget);
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

  testWidgets('route panel chooses a building before requesting a route',
      (tester) async {
    NavigationOrigin? selected;
    var requests = 0;
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await http.runWithClient(() async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, update) => ChooseRouteSheet(
              destination: destination,
              origin: selected ?? origin,
              hasSelectedOrigin: selected != null,
              origins: const [currentLocation, buildingOrigin, libraryOrigin],
              isCurrentLocationInsideCampus: true,
              onUseCurrentLocation: () async {},
              onOriginSelected: (value) => update(() => selected = value),
              onBack: () {},
              onCancel: () {},
              onViewRoute: (_, __) {},
            ),
          ),
        ),
      ));
      expect(requests, 0);
      expect(
          tester
              .widget<TextField>(
                  find.byKey(const ValueKey('route-origin-field')))
              .decoration!
              .hintText,
          'Your Location');
      expect(find.text('CHOOSE STARTING POINT'), findsNothing);
      expect(
          tester
              .widget<ElevatedButton>(
                  find.widgetWithText(ElevatedButton, 'View Route'))
              .onPressed,
          isNull);
      final search = find.byKey(const ValueKey('route-origin-field'));
      await tester.tap(search);
      await tester.pump();
      expect(find.text('Use My Current Location'), findsOneWidget);
      await tester.enterText(search, 'com');
      await tester.pump();
      expect(find.text('College of Medicine'), findsOneWidget);
      expect(find.text('Main Library'), findsNothing);
      expect(requests, 0);
      await tester.enterText(search, 'library');
      await tester.pump();
      expect(find.text('Main Library'), findsOneWidget);
      expect(find.text('College of Medicine'), findsNothing);
      await tester.enterText(search, 'unknown');
      await tester.pump();
      expect(find.text('No buildings found.'), findsOneWidget);
      expect(find.text('Use My Current Location'), findsOneWidget);
      await tester.enterText(search, '');
      await tester.pump();
      await tester.tap(find.text('Others'));
      await tester.pump();
      expect(find.text('College of Medicine'), findsOneWidget);
      expect(find.text('Main Library'), findsOneWidget);
      await tester.enterText(search, 'medicine');
      await tester.pump();
      await tester.ensureVisible(find.text('College of Medicine'));
      await tester.tap(find.text('College of Medicine'));
      await tester.pump();
      expect(selected?.id, 'college_of_medicine');
      expect(requests, 1);
      expect(find.text('Use My Current Location'), findsNothing);
      expect(tester.widget<TextField>(search).controller?.text,
          'College of Medicine');
      expect(tester.takeException(), isNull);
    },
        () => MockClient((request) async {
              requests++;
              return http.Response('{"routes":[]}', 200);
            }));
  });

  testWidgets('outside-campus selection keeps route unavailable',
      (tester) async {
    var attempts = 0;
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ChooseRouteSheet(
              destination: destination,
              origin: origin,
              hasSelectedOrigin: false,
              origins: const [buildingOrigin],
              locationStatus:
                  'You are outside the supported ISU Echague campus area.',
              isCurrentLocationInsideCampus: false,
              onUseCurrentLocation: () async => attempts++,
              onOriginSelected: (_) {},
              onBack: () {},
              onCancel: () {},
              onViewRoute: (_, __) {},
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('route-origin-field')));
    await tester.pump();
    await tester.tap(find.text('Use My Current Location'));
    await tester.pump();
    expect(attempts, 1);
    expect(
      find.text('You are outside the supported ISU Echague campus area.'),
      findsOneWidget,
    );
    expect(
        tester
            .widget<ElevatedButton>(
                find.widgetWithText(ElevatedButton, 'View Route'))
            .onPressed,
        isNull);
  });

  testWidgets('current location selection refreshes route in the same panel',
      (tester) async {
    NavigationOrigin? selected;
    var requests = 0;
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await http.runWithClient(() async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, update) => ChooseRouteSheet(
              destination: destination,
              origin: selected ?? origin,
              hasSelectedOrigin: selected != null,
              isCurrentLocationInsideCampus: true,
              onUseCurrentLocation: () async {
                update(() => selected = currentLocation);
              },
              onBack: () {},
              onCancel: () {},
              onViewRoute: (_, __) {},
            ),
          ),
        ),
      ));
      await tester.tap(find.byKey(const ValueKey('route-origin-field')));
      await tester.pump();
      await tester.tap(find.text('Use My Current Location'));
      await tester.pump();
      expect(find.text('My Current Location'), findsOneWidget);
      expect(find.text('Use My Current Location'), findsNothing);
      expect(requests, 1);
      expect(tester.takeException(), isNull);
    },
        () => MockClient((request) async {
              requests++;
              return http.Response('{"routes":[]}', 200);
            }));
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
