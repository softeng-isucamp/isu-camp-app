import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isu_camp_app/features/dashboard/widgets/location_puck.dart';

void main() {
  Future<void> pump(WidgetTester tester, double? heading) => tester.pumpWidget(
      MaterialApp(home: Center(child: LocationPuck(heading: heading))));

  testWidgets('shows a heading cone when the compass reports one',
      (tester) async {
    await pump(tester, 90);
    expect(find.byKey(const ValueKey('location-heading-cone')), findsOneWidget);
  });

  testWidgets('shows only the dot without a compass', (tester) async {
    await pump(tester, null);
    expect(find.byKey(const ValueKey('location-heading-cone')), findsNothing);
  });
}
