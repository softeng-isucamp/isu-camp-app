import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:isu_camp_app/core/app_theme.dart';
import 'package:isu_camp_app/features/auth/screens/help_screen.dart';
import 'package:isu_camp_app/features/auth/screens/login_screen.dart';
import 'package:isu_camp_app/features/auth/screens/register_screen.dart';
import 'package:isu_camp_app/features/dashboard/screens/user_info_screen.dart';
import 'package:isu_camp_app/features/dashboard/screens/map_view_screen.dart';
import 'package:isu_camp_app/features/dashboard/widgets/navigation_sheets.dart';
import 'package:isu_camp_app/features/offline/screens/offline_map_screen.dart';

Widget app(Widget child, {double scale = 1}) => MaterialApp(
      theme: AppTheme.light,
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!),
      home: child,
    );

void main() {
  testWidgets('landscape profile scroll reaches offline, history and logout',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(844, 390));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(app(const UserInfoScreen()));
    await tester.pumpAndSettle();
    final scroll = find.byKey(const ValueKey('profile-scroll'));
    await tester.scrollUntilVisible(find.text('Log Out'), 150,
        scrollable:
            find.descendant(of: scroll, matching: find.byType(Scrollable)));
    expect(find.text('Log Out').hitTestable(), findsOneWidget);
    expect(find.text('Offline Map'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final entry in <String, Widget>{
    'login': const LoginScreen(),
    'signup': const RegisterScreen(),
    'offline': const OfflineMapScreen()
  }.entries) {
    testWidgets('${entry.key} fits 320px at 200% text throughout its scroll',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(app(entry.value, scale: 2));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.drag(
          find.byType(SingleChildScrollView).first, const Offset(0, -1800));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('room filters and Enter preserve the same scoped search results',
      (tester) async {
    final tile = File('assets/images/logo_isu.webp').readAsBytesSync();
    const name =
        'Office of the Academic Researches Librarian with a Very Long Campus Title';
    final buildings = [
      for (final pair in [('7', 'Main Library'), ('1', 'CCSICT')])
        {
          'id': pair.$1,
          'name': pair.$2,
          'acronym': pair.$1 == '7' ? 'OSM-WAY-123' : 'CCSICT',
          'category': 'Campus Services',
          'latitude': 16.72,
          'longitude': 121.69,
          'rooms': [
            {
              'id': '${pair.$1}-office',
              'title': name,
              'category': 'office',
              'keywords': 'academic',
              'floor': '2nd Floor'
            },
            {
              'id': '${pair.$1}-wc',
              'title': 'Restroom',
              'category': 'restroom',
              'floor': 'Ground Floor'
            },
          ],
        }
    ];
    await http.runWithClient(() async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(app(const MapViewScreen()));
      await tester.pump(const Duration(seconds: 1));
      await tester.enterText(find.byType(TextField).first, 'academic');
      await tester.pump();
      expect(tester.takeException(), isNull,
          reason: 'long room chip must wrap at normal text size');
      await tester.enterText(
          find.byType(TextField).first, 'restroom in Main Library');
      await tester.pump();
      expect(find.text('SEARCH RESULTS (1)'), findsOneWidget);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(
          tester
              .widget<SearchResultsSheet>(find.byType(SearchResultsSheet))
              .results
              .single
              .building
              .id,
          '7');
      expect(
          tester
              .widget<SearchResultsSheet>(find.byType(SearchResultsSheet))
              .results
              .single
              .room
              ?.category
              .name,
          'restroom');
      // Office contains no restroom result even when their parent also has offices.
      final filter = find.byKey(const ValueKey('category-Office'));
      await tester.ensureVisible(filter);
      await tester.tap(filter);
      await tester.pump();
      expect(
          tester
              .widget<SearchResultsSheet>(find.byType(SearchResultsSheet))
              .results,
          isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
        () => MockClient((r) async => r.url.path == '/campus/buildings'
            ? http.Response(jsonEncode({'buildings': buildings}), 200)
            : http.Response.bytes(tile, 200,
                headers: {'content-type': 'image/png'})));
  });

  testWidgets(
      'Help copies a useful report instead of advertising an inert phone link',
      (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData')
        copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.pumpWidget(app(const HelpScreen()));
    await tester.ensureVisible(find.text('Copy issue report'));
    await tester.tap(find.text('Copy issue report'));
    await tester.pump();
    expect(copied, contains('KUMPAS issue report'));
    expect(find.text('09123456789'), findsNothing);
    expect(
        find.textContaining('Issue report template copied.'), findsOneWidget);
  });
  testWidgets('Help provides selectable details if clipboard access is denied',
      (tester) async {
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData')
        throw PlatformException(code: 'denied');
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.pumpWidget(app(const HelpScreen()));
    await tester.ensureVisible(find.text('Copy issue report'));
    await tester.tap(find.text('Copy issue report'));
    await tester.pumpAndSettle();
    expect(find.byType(SelectableText), findsOneWidget);
    expect(tester.widget<SelectableText>(find.byType(SelectableText)).data,
        contains('KUMPAS issue report'));
  });
}
