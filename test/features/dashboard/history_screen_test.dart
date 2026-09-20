import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:isu_camp_app/features/auth/services/user_session.dart';
import 'package:isu_camp_app/features/dashboard/data/campus_dataset.dart';
import 'package:isu_camp_app/features/dashboard/models/campus_models.dart';
import 'package:isu_camp_app/features/dashboard/models/navigation_history.dart';
import 'package:isu_camp_app/features/dashboard/screens/user_info_screen.dart';

void main() {
  final response = jsonEncode({
    'entries': [
      {
        'id': '1',
        'destinationId': '8',
        'destinationName': 'CCSICT',
        'destinationAcronym': 'CCS',
        'roomId': '9',
        'roomName': 'Lab 1',
        'createdAt': '2026-09-20T01:00:00Z',
      }
    ]
  });
  setUp(() {
    UserSession.setLoggedInUser(username: 'student', token: 'test-token');
    isuCampusBuildings.add(const CampusBuilding(
        id: '8',
        name: 'CCSICT',
        acronym: 'CCS',
        category: 'Academic',
        description: '',
        coordinate: LatLng(16.72, 121.69),
        rooms: [
          CampusRoom(
              id: '9',
              title: 'Lab 1',
              category: RoomCategory.laboratory,
              floor: '1st Floor',
              icon: Icons.science)
        ]));
  });
  tearDown(() {
    UserSession.logout();
    isuCampusBuildings.clear();
  });

  testWidgets('history Get directions preserves building and room selection',
      (tester) async {
    NavigationHistoryEntry? selected;
    await http.runWithClient(() async {
      await tester.binding.setSurfaceSize(const Size(430, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
          home: Builder(
              builder: (context) => Scaffold(
                    body: TextButton(
                        onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => UserInfoScreen(
                                    onNavigateToHistory: (entry) =>
                                        selected = entry))),
                        child: const Text('Profile')),
                  ))));
      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('History'));
      await tester.tap(find.text('History'));
      await tester.pumpAndSettle();
      expect(find.text('CCSICT'), findsOneWidget);
      expect(find.text('Lab 1'), findsOneWidget);
      expect(find.text('Get directions'), findsOneWidget);
      await tester.tap(find.text('Get directions'));
      await tester.pumpAndSettle();
      expect(selected?.destinationId, '8');
      expect(selected?.roomId, '9');
      expect(tester.takeException(), isNull);
    }, () => MockClient((_) async => http.Response(response, 200)));
  });

  testWidgets('failed history load displays retry and can recover',
      (tester) async {
    var fail = true;
    await http.runWithClient(() async {
      await tester.binding.setSurfaceSize(const Size(430, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const MaterialApp(home: UserInfoScreen()));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('History'));
      await tester.tap(find.text('History'));
      await tester.pumpAndSettle();
      expect(find.text('Could not load history.'), findsOneWidget);
      fail = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Get directions'), findsOneWidget);
    },
        () => MockClient((_) async => fail
            ? http.Response('{"detail":"Could not load history."}', 503)
            : http.Response(response, 200)));
  });
}
