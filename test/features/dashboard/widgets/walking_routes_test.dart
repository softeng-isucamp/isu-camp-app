import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:isu_camp_app/features/dashboard/models/campus_models.dart';
import 'package:isu_camp_app/features/dashboard/widgets/navigation_sheets.dart';

void main() {
  const origin = NavigationOrigin(
      id: 'main_gate',
      label: 'Gate',
      coordinate: LatLng(16.72, 121.69),
      type: NavigationOriginType.mainGate);
  const destination = CampusBuilding(
      id: '1',
      name: 'Building',
      acronym: 'B',
      category: 'Building',
      description: '',
      coordinate: LatLng(16.721, 121.69));
  Map<String, dynamic> route(String type, int distance) => {
        'type': type,
        'distanceMeters': distance,
        'estimatedMinutes': 3,
        'startNodeName': 'Gate',
        'pathPoints': [
          [16.72, 121.69],
          [16.721, 121.69]
        ],
        'steps': [],
      };

  testWidgets('uses backend metrics and returns selected shaded route',
      (tester) async {
    WalkingRoute? selected;
    TransportMode? changedMode;
    await http.runWithClient(() async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: ChooseRouteSheet(
        destination: destination,
        origin: origin,
        onBack: () {},
        onCancel: () {},
        onTransportModeChanged: (mode) => changedMode = mode,
        onViewRoute: (route, mode) {
          selected = route;
        },
      ))));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('100 m'), findsOneWidget);
      expect(find.text('150 m'), findsOneWidget);
      await tester.ensureVisible(find.text('View Route'));
      await tester.pump();
      await tester.tap(find.text('View Route'));
      expect(selected?.type, RouteType.comfortableShaded);
      expect(selected?.distanceMeters, 150);
      await tester.ensureVisible(find.byIcon(Icons.directions_car));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.directions_car));
      await tester.pump();
      expect(changedMode, TransportMode.car);
      expect(find.text('Routing is currently available for Walking only.'),
          findsNothing);
      expect(
          tester
              .widget<ElevatedButton>(
                  find.widgetWithText(ElevatedButton, 'View Route'))
              .onPressed,
          isNotNull);
      expect(tester.takeException(), isNull);
    },
        () => MockClient((request) async {
              expect(request.method, 'POST');
              expect(jsonDecode(request.body)['destinationBuildingId'], '1');
              return http.Response(
                  jsonEncode({
                    'routes': [
                      {
                        ...route('shortest', 100),
                        'mode': jsonDecode(request.body)['mode']
                      },
                      {
                        ...route('comfortableShaded', 150),
                        'mode': jsonDecode(request.body)['mode']
                      }
                    ]
                  }),
                  200);
            }));
  });

  testWidgets('switching modes ignores older responses', (tester) async {
    final pending = <String, Completer<http.Response>>{};
    TransportMode? selectedMode;
    WalkingRoute? selectedRoute;
    await http.runWithClient(() async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: ChooseRouteSheet(
        destination: destination,
        origin: origin,
        onBack: () {},
        onCancel: () {},
        onViewRoute: (route, mode) {
          selectedMode = mode;
          selectedRoute = route;
        },
      ))));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.directions_car));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.pedal_bike));
      await tester.pump();
      http.Response response(String mode, int meters) => http.Response(
          jsonEncode({
            'routes': [
              {...route('shortest', meters), 'mode': mode},
              {...route('comfortableShaded', meters + 10), 'mode': mode},
            ]
          }),
          200);
      pending['bicycle']!.complete(response('bicycle', 220));
      await tester.pump();
      expect(find.text('220 m'), findsOneWidget);
      pending['car']!.complete(response('car', 100));
      pending['walking']!.complete(response('walking', 80));
      await tester.pump();
      expect(find.text('220 m'), findsOneWidget);
      expect(find.text('100 m'), findsNothing);
      await tester.ensureVisible(find.text('View Route'));
      await tester.pump();
      await tester.tap(find.text('View Route'));
      expect(selectedMode, TransportMode.bicycle);
      expect(selectedRoute?.mode, TransportMode.bicycle);
      expect(selectedRoute?.type, RouteType.shortest);
      expect(find.text('Shaded Path'), findsNothing);
      expect(find.text('CHOOSE ROUTE'), findsNothing);
      expect(tester.takeException(), isNull);
    },
        () => MockClient((request) {
              final mode = jsonDecode(request.body)['mode'] as String;
              pending[mode] = Completer<http.Response>();
              return pending[mode]!.future;
            }));
  });

  for (final mode in TransportMode.values) {
    testWidgets('${mode.name}: route preference is only shown for walking',
        (tester) async {
      WalkingRoute? selected;
      await http.runWithClient(() async {
        await tester.binding.setSurfaceSize(const Size(800, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(MaterialApp(
            home: Scaffold(
                body: ChooseRouteSheet(
          destination: destination,
          origin: origin,
          initialTransportMode: mode,
          onBack: () {},
          onCancel: () {},
          onViewRoute: (route, _) => selected = route,
        ))));
        await tester.pump();
        expect(find.text('Shaded Path'),
            mode == TransportMode.walking ? findsOneWidget : findsNothing);
        expect(find.text('CHOOSE ROUTE'),
            mode == TransportMode.walking ? findsOneWidget : findsNothing);
        await tester.ensureVisible(find.text('View Route'));
        await tester.tap(find.text('View Route'));
        expect(
            selected?.type,
            mode == TransportMode.walking
                ? RouteType.comfortableShaded
                : RouteType.shortest);
      },
          () => MockClient((_) async => http.Response(
              jsonEncode({
                'routes': [
                  {...route('shortest', 100), 'mode': mode.name},
                  {...route('comfortableShaded', 150), 'mode': mode.name},
                ]
              }),
              200)));
    });

    testWidgets('${mode.name}: no-route message disables navigation',
        (tester) async {
      await http.runWithClient(() async {
        await tester.binding.setSurfaceSize(const Size(800, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(MaterialApp(
            home: Scaffold(
                body: ChooseRouteSheet(
          destination: destination,
          origin: origin,
          initialTransportMode: mode,
          onBack: () {},
          onCancel: () {},
          onViewRoute: (_, __) => fail('No route must not navigate'),
        ))));
        await tester.pump();
        expect(find.text('No walking route'), findsOneWidget);
        expect(
            tester
                .widget<ElevatedButton>(
                    find.widgetWithText(ElevatedButton, 'View Route'))
                .onPressed,
            isNull);
        expect(find.text('Retry'), findsOneWidget);
      },
          () => MockClient((_) async =>
              http.Response('{"detail":"No walking route"}', 404)));
    });
  }
}
