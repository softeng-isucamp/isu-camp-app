import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../screens/login_screen.dart';
import 'auth_service.dart';
import 'remembered_session_store.dart';
import 'user_session.dart';

/// Thrown by a protected call after the server reported the account as
/// deactivated. The user has already been signed out when this is thrown.
class AccountDeactivatedException implements Exception {
  const AccountDeactivatedException();

  @override
  String toString() => AccountSession.deactivatedMessage;
}

/// What the app should open with after checking a remembered session.
enum LaunchSession { signedIn, signedOut, deactivated }

/// Signs the user out when an administrator deactivates their account.
class AccountSession {
  static const deactivatedMessage =
      'This account has been deactivated. Please contact the ISU CAMP administrator.';

  /// Attached to the app's [MaterialApp] so a sign-out can leave any screen.
  static final navigatorKey = GlobalKey<NavigatorState>();

  /// The server marks this refusal with `X-Account-Status: inactive`; any other
  /// 403 or error is not treated as a deactivation.
  static bool isDeactivated(http.BaseResponse response) =>
      response.statusCode == 403 &&
      response.headers['x-account-status']?.trim().toLowerCase() == 'inactive';

  /// Every protected service passes its response through here first.
  static Future<void> checkResponse(http.BaseResponse response) async {
    if (!isDeactivated(response)) return;
    await signOutDeactivated();
    throw const AccountDeactivatedException();
  }

  /// Clears the in-memory and remembered session, then returns to the login
  /// screen showing why. Several requests can be refused at once; only the one
  /// that still finds a signed-in session navigates.
  static Future<void> signOutDeactivated() async {
    final wasSignedIn = UserSession.accessToken != null;
    await _clearSession();
    final navigator = navigatorKey.currentState;
    if (!wasSignedIn || navigator == null) return;
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const LoginScreen(initialMessage: deactivatedMessage),
      ),
      (_) => false,
    );
  }

  static Future<void> _clearSession() async {
    UserSession.logout();
    try {
      await RememberedSessionStore.clear();
    } catch (_) {
      // The token is already gone from memory and the server refuses it anyway.
    }
  }

  /// Restores a remembered session and, when the server can be reached, asks it
  /// whether the account is still active. Only the deactivation signal signs the
  /// user out; offline, timeouts and server errors keep the session.
  static Future<LaunchSession> restoreOnLaunch(
      {Duration timeout = const Duration(seconds: 5)}) async {
    if (!await RememberedSessionStore.restore()) return LaunchSession.signedOut;
    try {
      final response = await http.get(
        Uri.parse('${AuthService.baseUrl}/profile'),
        headers: {'Authorization': 'Bearer ${UserSession.accessToken}'},
      ).timeout(timeout);
      if (isDeactivated(response)) {
        await _clearSession();
        return LaunchSession.deactivated;
      }
    } catch (_) {
      // Offline or unreachable: keep the session; the server still checks
      // every protected request.
    }
    return LaunchSession.signedIn;
  }
}
