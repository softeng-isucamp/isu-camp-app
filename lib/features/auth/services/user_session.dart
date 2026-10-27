class UserSession {
  static String currentUsername = 'UserA1B2c3';
  static String currentEmail = '';
  static String? accessToken;

  static void setRegisteredUser({
    required String username,
    String email = '',
  }) {
    currentUsername = username.isNotEmpty ? username : 'UserA1B2c3';
    if (email.isNotEmpty) currentEmail = email;
  }

  static void setLoggedInUser({
    required String username,
    String? token,
    String email = '',
  }) {
    accessToken = token;
    currentUsername = username.isNotEmpty ? username : 'UserA1B2c3';
    currentEmail = email;
  }

  static void logout() {
    accessToken = null;
    currentUsername = 'UserA1B2c3';
    currentEmail = '';
  }
}
