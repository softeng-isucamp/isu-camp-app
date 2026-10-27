import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:isu_camp_app/features/dashboard/screens/map_view_screen.dart';
import 'package:isu_camp_app/features/dashboard/widgets/navigation_sheets.dart';

void main() {
  for (final indoor in [true, false]) {
    testWidgets(
        '${indoor ? 'indoor' : 'building'} search opens location dialog and preserves destination',
        (tester) async {
      final bytes = File('assets/images/logo_isu_png.png').readAsBytesSync();
      await tester.binding.setSurfaceSize(const Size(1200, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await http.runWithClient(() async {
        await tester.pumpWidget(const MaterialApp(home: MapViewScreen()));
        await tester.pump(const Duration(milliseconds: 500));
        await tester.enterText(find.byType(TextField),
            indoor ? 'drawing room of COE' : 'College of Engineering');
        await tester.pump(const Duration(milliseconds: 200));
        await tester.tap(find.widgetWithText(
            ListTile, indoor ? 'New Drawing Room' : 'College of Engineering'));
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byType(IndoorLocationDetailsDialog), findsOneWidget);
        expect(find.byType(BuildingDetailsSheet), findsNothing);
        expect(find.text('Room name: New Drawing Room'),
            indoor ? findsOneWidget : findsNothing);
        expect(find.text('Floor: 2nd Floor'),
            indoor ? findsOneWidget : findsNothing);
        if (!indoor) expect(find.text('Category: College'), findsOneWidget);
        expect(find.text('Building: College of Engineering'), findsOneWidget);
        await tester.tap(find.text('Get Directions'));
        await tester.pump(const Duration(milliseconds: 400));
        final panel =
            tester.widget<ChooseRouteSheet>(find.byType(ChooseRouteSheet));
        expect(panel.destinationRoom?.id, indoor ? '148' : null);
        expect(panel.destination.id, '64');
        await tester.pumpWidget(const SizedBox.shrink());
      },
          () => MockClient((request) async {
                if (request.url.path == '/campus/buildings') {
                  return http.Response(
                      jsonEncode({
                        'buildings': [
                          {
                            'id': '64',
                            'name': 'College of Engineering',
                            'category': 'College',
                            'latitude': 16.72,
                            'longitude': 121.69,
                            'rooms': [
                              {
                                'id': '148',
                                'title': 'New Drawing Room',
                                'category': 'room',
                                'floor': '2nd Floor'
                              }
                            ],
                          }
                        ]
                      }),
                      200);
                }
                return http.Response.bytes(bytes, 200,
                    headers: {'content-type': 'image/png'});
              }));
    });
  }
}
