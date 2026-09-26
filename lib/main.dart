import 'package:flutter/material.dart';

import 'features/auth/screens/get_started_screen.dart';
import 'features/auth/services/user_session.dart';
import 'features/dashboard/screens/dashboard_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Keep full diagnostics for intermittent debug failures. Flutter normally
  // abbreviates later errors to "Another exception was thrown".
  assert(() {
    FlutterError.presentError = (details) {
      FlutterError.dumpErrorToConsole(details, forceReport: true);
    };
    return true;
  }());
  await UserSession.restore();
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
      home: UserSession.isLoggedIn
          ? const DashboardScreen()
          : const GetStartedScreen(),
    );
  }
}
