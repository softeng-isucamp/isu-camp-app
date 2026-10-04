import 'package:flutter/material.dart';

import 'features/auth/screens/get_started_screen.dart';
import 'features/auth/services/remembered_session_store.dart';
import 'features/dashboard/screens/dashboard_screen.dart';

void main() {
  // Keep full diagnostics for intermittent debug failures. Flutter normally
  // abbreviates later errors to "Another exception was thrown".
  assert(() {
    FlutterError.presentError = (details) {
      FlutterError.dumpErrorToConsole(details, forceReport: true);
    };
    return true;
  }());
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
      home: FutureBuilder<bool>(
        future: RememberedSessionStore.restore(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Scaffold(
                body: Center(child: CircularProgressIndicator()));
          }
          return snapshot.data!
              ? const DashboardScreen()
              : const GetStartedScreen();
        },
      ),
    );
  }
}
