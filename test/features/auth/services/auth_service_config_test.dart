import 'package:flutter_test/flutter_test.dart';
import 'package:isu_camp_app/features/auth/services/auth_service.dart';

void main() {
  test('uses the API base URL supplied at build time', () {
    const expected = String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'https://api.kumpas.live',
    );
    expect(AuthService.baseUrl, expected);
  });
}
