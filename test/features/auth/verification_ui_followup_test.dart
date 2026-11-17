import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isu_camp_app/core/app_theme.dart';
import 'package:isu_camp_app/features/auth/services/verification_security_controller.dart';
import 'package:isu_camp_app/features/auth/widgets/verification_sheets.dart';
import 'package:isu_camp_app/features/auth/widgets/otp_code_input.dart';

void main() {
  testWidgets('OTP is named and still auto-submits one six-digit native input',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final code = TextEditingController();
    String? submitted;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: OtpCodeInput(
                controller: code,
                onCompleted: (v) => submitted = v,
                onActivity: () {}))));
    expect(find.bySemanticsLabel(RegExp('6-digit verification code')),
        findsWidgets);
    await tester.enterText(
        find.byKey(const ValueKey('otp_code_input')), '123456');
    expect(submitted, '123456');
    expect(find.byType(TextField), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    code.dispose();
    semantics.dispose();
  });

  for (final fails in [false, true]) {
    testWidgets(
        'pending password save resists dismissal and ${fails ? 'retains errors for retry' : 'reports completion'}',
        (tester) async {
      final security = VerificationSecurityController(onTimeout: (_) {})
        ..startOtpChallenge()
        ..beginPasswordSetup();
      final pending = Completer<void>();
      bool? result;
      await tester.binding.setSurfaceSize(const Size(430, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
          theme: AppTheme.light,
          home: Builder(
              builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () async {
                        result = await SetNewPasswordSheet.show(context,
                            security: security,
                            onSubmit: (_, __, ___) => pending.future,
                            requireCurrentPassword: true);
                      },
                      child: const Text('Open'))))));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), 'OldPass1!');
      await tester.enterText(find.byType(TextField).at(1), 'NewPass2!');
      await tester.enterText(find.byType(TextField).at(2), 'NewPass2!');
      await tester.tap(find.byTooltip('Show new password'));
      await tester.pump();
      expect(find.byTooltip('Hide new password'), findsOneWidget);
      await tester.ensureVisible(find.text('Update Password'));
      await tester.tap(find.text('Update Password'));
      await tester.pump();
      await tester.tapAt(const Offset(5, 5));
      await tester.drag(find.text('Set New Password'), const Offset(0, 450));
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(SetNewPasswordSheet), findsOneWidget);
      expect(result, isNull);
      expect(
          tester
              .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.close))
              .onPressed,
          isNull);
      if (fails) {
        pending.completeError(Exception('Please retry this save.'));
        await tester.pumpAndSettle();
        expect(find.byType(SetNewPasswordSheet), findsOneWidget);
        expect(find.text('Could not update your password. Please try again.'),
            findsOneWidget);
        expect(
            tester
                .widget<TextField>(find.byType(TextField).at(1))
                .controller!
                .text,
            'NewPass2!');
        await tester.tap(find.byTooltip('Close password editor'));
        await tester.pumpAndSettle();
        expect(result, isFalse);
      } else {
        pending.complete();
        await tester.pumpAndSettle();
        expect(find.byType(SetNewPasswordSheet), findsNothing);
        expect(result, isTrue);
      }
      await tester.pumpWidget(const SizedBox());
      security.dispose();
    });
  }
}
