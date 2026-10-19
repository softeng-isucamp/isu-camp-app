import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:isu_camp_app/features/offline/screens/offline_map_screen.dart';
import 'package:isu_camp_app/features/offline/models/offline_pack.dart';
import 'package:isu_camp_app/features/offline/services/offline_file_store.dart';
import 'package:isu_camp_app/features/offline/services/offline_pack_service.dart';

/// What the screen shows for each pack state, and that opening it never
/// downloads anything. The download, update, and delete mechanics themselves
/// are covered in offline_pack_service_test.dart.
const String _baseUrl = 'http://api.test';

Map<String, dynamic> _bundle(String version) => {
      'version': version,
      'generatedAt': '2026-10-14T00:00:00Z',
      'skippedCount': 0,
      'buildings': const [
        {
          'id': '5',
          'name': 'Admin Building',
          'acronym': 'ADM',
          'latitude': 16.7220,
          'longitude': 121.6900,
          'rooms': [],
        }
      ],
      'graph': const {
        'nodes': [],
        'pathways': [],
        'modes': [],
        'points': [],
      },
    };

class _ProgressPack extends OfflinePackService {
  OfflinePackStatus snapshot = const OfflinePackStatus(
    state: OfflinePackState.downloading,
    bytesOnDisk: 13 * 1024 * 1024,
    bytesInFlight: 512 * 1024,
    completedFiles: 123,
    totalFiles: 456,
  );

  @override
  OfflinePackStatus get status => snapshot;

  @override
  Future<void> load() async {}

  void show(OfflinePackStatus status) {
    snapshot = status;
    notifyListeners();
  }
}

void main() {
  late Directory root;
  late List<String> requests;
  final OfflinePackService liveInstance = OfflinePackService.instance;

  setUp(() {
    root = Directory.systemTemp.createTempSync('kumpas_offline_ui');
    requests = [];
  });

  tearDown(() {
    OfflinePackService.instance = liveInstance;
    try {
      if (root.existsSync()) root.deleteSync(recursive: true);
    } on FileSystemException {
      // A temporary directory Windows still holds open; the OS reclaims it.
    }
  });

  MockClient backend(String version) => MockClient((request) async {
        final url = request.url.toString();
        requests.add(url);
        if (url.endsWith('/campus/offline/bundle')) {
          return http.Response(jsonEncode(_bundle(version)), 200);
        }
        if (url.endsWith('/campus/offline/manifest')) {
          return http.Response(jsonEncode({'version': version}), 200);
        }
        return http.Response.bytes([0x89, 0x50, 0x4E, 0x47], 200);
      });

  // Only the coarsest zoom, so these UI tests download nine tiles, not 1126.
  OfflinePackService serviceFor(String version) => OfflinePackService(
        store: OfflineFileStore(rootPath: root.path),
        client: backend(version),
        baseUrl: () => _baseUrl,
        maxTileZoom: 15,
      );

  /// The pack reads and writes real files, which only progress outside the
  /// widget tester's fake clock.
  Future<void> openScreen(WidgetTester tester, OfflinePackService pack) async {
    await tester.runAsync(() async {
      await pack.load();
      await tester.pumpWidget(MaterialApp(home: OfflineMapScreen(pack: pack)));
      await tester.pump();
      await pack.checkForUpdate();
    });
    await tester.pumpAndSettle();
  }

  String subtitle(WidgetTester tester) => tester
      .widget<Text>(find.byKey(const ValueKey('offline-pack-subtitle')))
      .data!;

  testWidgets('download and pause show MB without file counts or percentages',
      (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final pack = _ProgressPack();
    await tester.pumpWidget(MaterialApp(home: OfflineMapScreen(pack: pack)));
    await tester.pump();

    expect(subtitle(tester), '13.5 MB downloaded');
    expect(
        tester
            .widget<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator))
            .value,
        isNull);

    pack.show(pack.status.copyWith(bytesInFlight: 1024 * 1024));
    await tester.pump();
    expect(subtitle(tester), '14.0 MB downloaded');

    pack.show(pack.status.copyWith(
      state: OfflinePackState.incomplete,
      bytesOnDisk: 14 * 1024 * 1024,
      bytesInFlight: 0,
    ));
    await tester.pump();
    expect(subtitle(tester), '14.0 MB downloaded • Paused');
    expect(
        tester
            .widget<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator))
            .value,
        0);
    expect(find.byKey(const ValueKey('offline-resume-button')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    pack.dispose();
  });

  testWidgets('with nothing stored the screen offers a download',
      (tester) async {
    final pack = serviceFor('v1');
    await openScreen(tester, pack);

    expect(subtitle(tester), 'Map, campus data, and photos');
    expect(
        find.byKey(const ValueKey('offline-download-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('offline-update-card')), findsNothing);
    expect(find.byKey(const ValueKey('offline-delete-button')), findsNothing);
    expect(find.text('Download the map to receive update notices.'),
        findsOneWidget);
    // Nothing is fetched just by looking at the screen.
    expect(requests, isEmpty);
  });

  testWidgets('a stored pack reports itself ready and offers deletion',
      (tester) async {
    final pack = serviceFor('v1');
    await tester.runAsync(() => pack.download());
    requests.clear();
    await openScreen(tester, pack);

    expect(subtitle(tester), contains('Offline Ready'));
    expect(pack.status.bytesOnDisk, greaterThan(0));
    expect(find.byKey(const ValueKey('offline-delete-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('offline-download-button')), findsNothing);
    expect(find.byKey(const ValueKey('offline-update-card')), findsNothing);
    expect(find.textContaining('Last checked'), findsOneWidget);
    // Only the update check talked to the network.
    expect(requests.single, endsWith('/campus/offline/manifest'));
  });

  testWidgets('a newer dataset is announced, and nothing is replaced',
      (tester) async {
    await tester.runAsync(() => serviceFor('v1').download());

    // The same cache, now talking to a backend with a newer dataset.
    final pack = serviceFor('v2');
    requests.clear();
    await openScreen(tester, pack);

    expect(find.byKey(const ValueKey('offline-update-card')), findsOneWidget);
    expect(find.text('A newer campus map is available'), findsOneWidget);
    expect(find.text('Download update'), findsOneWidget);
    expect(find.textContaining('installed when you choose'), findsOneWidget);

    // The stored map is untouched until the user asks for the update.
    expect(pack.status.installedVersion, 'v1');
    expect(pack.status.updateVersion, 'v2');
    expect(pack.buildings, isNotNull);
    expect(subtitle(tester), contains('Offline Ready'));
    expect(requests.where((url) => url.endsWith('/offline/bundle')), isEmpty);
    expect(
        requests.where((url) => url.contains('tile.openstreetmap')), isEmpty);
  });

  testWidgets('an unfinished download can be resumed', (tester) async {
    late OfflinePackService pack;
    pack = OfflinePackService(
      store: OfflineFileStore(rootPath: root.path),
      client: MockClient((request) async {
        final url = request.url.toString();
        if (url.endsWith('/campus/offline/bundle')) {
          return http.Response(jsonEncode(_bundle('v1')), 200);
        }
        if (url.contains('tile.openstreetmap.org')) {
          pack.pause();
        }
        return http.Response.bytes([0x89, 0x50, 0x4E, 0x47], 200);
      }),
      baseUrl: () => _baseUrl,
      maxTileZoom: 15,
    );
    await tester.runAsync(() => pack.download());
    await openScreen(tester, pack);

    expect(subtitle(tester), contains('Paused'));
    expect(find.byKey(const ValueKey('offline-resume-button')), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    // Reopening the app reports what is left rather than resuming silently.
    expect(find.textContaining('Resume to complete it'), findsOneWidget);
  });

  testWidgets('deleting asks first and keeps the map when declined',
      (tester) async {
    final pack = serviceFor('v1');
    await tester.runAsync(() => pack.download());
    await openScreen(tester, pack);

    await tester.tap(find.byKey(const ValueKey('offline-delete-button')));
    await tester.pumpAndSettle();
    expect(find.text('Delete offline map?'), findsOneWidget);

    await tester.tap(find.text('Keep'));
    await tester.pumpAndSettle();

    expect(pack.status.isReady, isTrue);
    expect(pack.status.installedVersion, 'v1');
    expect(find.byKey(const ValueKey('offline-delete-button')), findsOneWidget);
  });
}
