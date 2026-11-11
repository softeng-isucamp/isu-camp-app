import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'features/auth/screens/get_started_screen.dart';
import 'features/auth/screens/login_screen.dart';
import 'features/auth/services/account_session.dart';
import 'features/dashboard/screens/dashboard_screen.dart';
import 'features/offline/services/offline_pack_service.dart';

void main() {
  // Keep full diagnostics for intermittent debug failures. Flutter normally
  // abbreviates later errors to "Another exception was thrown".
  assert(() {
    FlutterError.presentError = (details) {
      FlutterError.dumpErrorToConsole(details, forceReport: true);
    };
    return true;
  }());
  WidgetsFlutterBinding.ensureInitialized();
  // The bundled fonts are OFL-licensed, which requires shipping their licenses.
  LicenseRegistry.addLicense(() async* {
    for (final family in const ['Montserrat', 'AntonSC']) {
      final license =
          await rootBundle.loadString('assets/google_fonts/OFL-$family.txt');
      yield LicenseEntryWithLineBreaks(['google_fonts'], license);
    }
  });
  // Make whatever is already downloaded usable before the first frame.
  OfflinePackService.instance.load();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KUMPAS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true),
      navigatorKey: AccountSession.navigatorKey,
      home: FutureBuilder<LaunchSession>(
        future: AccountSession.restoreOnLaunch(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Scaffold(
                body: Center(child: CircularProgressIndicator()));
          }
          return switch (snapshot.data!) {
            LaunchSession.signedIn => const DashboardScreen(),
            LaunchSession.signedOut => const GetStartedScreen(),
            LaunchSession.deactivated => const LoginScreen(
                initialMessage: AccountSession.deactivatedMessage),
          };
        },
      ),
    );
  }
}
