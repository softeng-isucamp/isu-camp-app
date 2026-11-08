import 'package:flutter_test/flutter_test.dart';
import 'package:isu_camp_app/core/error_messages.dart';
import 'package:isu_camp_app/features/auth/services/auth_service.dart';

void main() {
  test('unexpected transport and parsing failures never expose diagnostics', () {
    for (final error in [
      Exception('ClientException: secret-host/token'),
      const FormatException('Unexpected token: private payload'),
      Exception('database constraint users_email_key'),
    ]) {
      expect(ErrorMessages.present(error, 'Could not sign in. Please try again.'),
          'Could not sign in. Please try again.');
    }
  });

  test('legacy OTP wording is friendly without losing attempts or expiry', () {
    expect(ErrorMessages.present('Invalid OTP. 1 attempt(s) remaining.', ''),
        'That code is incorrect. 1 attempt remaining.');
    expect(ErrorMessages.present('Invalid OTP. 4 attempt(s) remaining.', ''),
        'That code is incorrect. 4 attempts remaining.');
    expect(ErrorMessages.present('OTP expired. Please request a new OTP.', ''),
        'Verification code expired. Please request a new code.');
    const error = OtpException('Invalid OTP. 4 attempt(s) remaining.',
        attemptsRemaining: 4, statusCode: 400);
    expect(error.isIncorrectCode, isTrue);
    expect(AuthService.verificationErrorMessage(error),
        'That code is incorrect. 4 attempts remaining.');
    expect(error.attemptsRemaining, 4);
  });

  test('known session and history errors retain useful recovery once', () {
    expect(ErrorMessages.present(Exception('Your session has expired. Please log in again.'), ''),
        'Your session has expired. Please log in again.');
    expect(ErrorMessages.present(Exception('History was not saved. Please try again.'), ''),
        'History was not saved. Please try again.');
  });

  test('route failures retain travel mode and available origin alternative', () {
    expect(ErrorMessages.present('No connected bicycle route to this building is available on permitted pathways.', ''),
        'No bicycle route to this building is available.');
    expect(ErrorMessages.present('No permitted car pathway within 200 m. Choose a campus building or the main gate.', ''),
        'No car route starts within 200 m of this location. Choose a campus building or the main gate.');
  });
}
