import 'package:flutter/material.dart';
import 'package:isu_camp_app/features/auth/services/auth_service.dart';
import 'package:isu_camp_app/features/auth/widgets/verification_sheets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isu_camp_app/features/auth/services/verification_security_controller.dart';

void main() {
  testWidgets('OTP challenge expires using an absolute deadline',
      (tester) async {
    var now = DateTime(2026);
    VerificationTimeoutReason? timeoutReason;
    final controller = VerificationSecurityController(
      now: () => now,
      codeLifetime: const Duration(seconds: 2),
      inactivityDuration: const Duration(seconds: 20),
      onTimeout: (reason) => timeoutReason = reason,
    );

    controller.startOtpChallenge();
    now = now.add(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 1));

    expect(timeoutReason, VerificationTimeoutReason.codeExpired);
    expect(controller.stage, VerificationStage.expired);
    controller.dispose();
  });

  testWidgets('user activity resets only the inactivity deadline',
      (tester) async {
    var now = DateTime(2026);
    VerificationTimeoutReason? timeoutReason;
    final controller = VerificationSecurityController(
      now: () => now,
      codeLifetime: const Duration(seconds: 20),
      inactivityDuration: const Duration(seconds: 2),
      inactivityWarning: const Duration(seconds: 1),
      onTimeout: (reason) => timeoutReason = reason,
    );

    controller.startOtpChallenge();
    final originalCodeExpiry = controller.codeExpiresAt;
    now = now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    controller.recordActivity();
    now = now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    expect(timeoutReason, isNull);
    expect(controller.codeExpiresAt, originalCodeExpiry);

    now = now.add(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 1));
    expect(timeoutReason, VerificationTimeoutReason.inactivity);
    controller.dispose();
  });

  testWidgets('resending refreshes the code without restoring wrong guesses',
      (tester) async {
    final controller = VerificationSecurityController(
      resendCooldown: Duration.zero,
      onTimeout: (_) {},
    );
    controller.startOtpChallenge();
    controller.recordIncorrectAttempt(serverRemaining: 3);
    controller.recordResend();
    expect(controller.attemptsRemaining, 3);
    expect(controller.canVerify, isTrue);
    controller.dispose();
  });

  testWidgets('the code sheet still shows server attempts after a resend',
      (tester) async {
    final controller = VerificationSecurityController(
      resendCooldown: Duration.zero,
      onTimeout: (_) {},
    )..startOtpChallenge();
    var resends = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: VerifyCodeSheet(
      security: controller,
      description: 'Enter the code sent to demo@example.com.',
      onVerify: (_) async => throw const OtpException(
          'Invalid OTP. 3 attempt(s) remaining.',
          attemptsRemaining: 3),
      onResend: () async {
        resends++;
      },
    ))));
    await tester.enterText(
        find.byKey(const ValueKey('otp_code_input')), '111111');
    await tester.pumpAndSettle();
    expect(find.textContaining('3 attempts left'), findsOneWidget);
    await tester.tap(find.text('Resend'));
    await tester.pumpAndSettle();
    expect(resends, 1);
    expect(find.textContaining('3 attempts left'), findsOneWidget);
    expect(find.textContaining('5 attempts left'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('attempt and resend limits enter their lockout states',
      (tester) async {
    final now = DateTime(2026);
    final controller = VerificationSecurityController(
      now: () => now,
      maximumAttempts: 2,
      maximumResends: 2,
      resendCooldown: Duration.zero,
      onTimeout: (_) {},
    );

    controller.startOtpChallenge();
    controller.recordIncorrectAttempt();
    expect(controller.attemptsRemaining, 1);
    controller.recordIncorrectAttempt();
    expect(controller.attemptsRemaining, 0);
    expect(controller.isVerificationLocked, isTrue);

    controller.recordResend();
    controller.recordResend();
    expect(controller.isResendLocked, isTrue);
    controller.dispose();
  });
}
