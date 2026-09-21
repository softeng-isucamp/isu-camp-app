import 'package:flutter_test/flutter_test.dart';
import 'package:isu_camp_app/features/auth/services/auth_service.dart';

/// Run twice:
///   flutter test test/api_base_url_test.dart
///   flutter test test/api_base_url_test.dart --dart-define=API_BASE_URL=http://192.168.1.50:5000
///   flutter test test/api_base_url_test.dart --dart-define=API_BASE_URL=not-a-url
const override = String.fromEnvironment('API_BASE_URL');

void main() {
  test('base URL resolution matches the build configuration', () {
    if (override.isEmpty) {
      // Tests run in debug, where the emulator/loopback defaults are usable.
      expect(AuthService.configurationError, isNull);
      expect(AuthService.baseUrl, contains(':5000'));
      expect(AuthService.endpoint('/campus/buildings').path, '/campus/buildings');
    } else if (Uri.tryParse(override)?.host.isNotEmpty ?? false) {
      expect(AuthService.configurationError, isNull);
      expect(AuthService.baseUrl, override);
      final uri = AuthService.endpoint('/campus/buildings');
      expect(uri.toString(), '$override/campus/buildings');
      expect(uri.host, Uri.parse(override).host);
    } else {
      // A malformed --dart-define must be reported, not silently used.
      expect(AuthService.configurationError, isNotNull);
      expect(AuthService.configurationError, contains('not a valid URL'));
      expect(() => AuthService.endpoint('/campus/buildings'),
          throwsA(isA<ApiException>()));
    }
  });

  test('query strings survive endpoint()', () {
    if (AuthService.configurationError != null) return;
    expect(AuthService.endpoint('/history?offset=100').query, 'offset=100');
  });
}
