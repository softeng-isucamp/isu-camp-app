/// Presentation-only translations. Unknown exception text never reaches users.
/// Server wording remains compatible with older app versions.
class ErrorMessages {
  static const replacements = <String, String>{
"Unsupported transport mode.": "Choose a different travel mode.",
"This building has no active entrance linked to the routing network.": "Directions to this building are unavailable.",
"The starting building has no active entrance linked to the routing network.": "Directions from this building are unavailable. Choose another starting point.",
"Could not load history.": "Could not load your history. Please try again.",

    "Code verification failed.": "Could not verify the code. Please try again.",
    "Could not load the published offline map. Check your connection and try again.":
        "Could not load the offline map. Check your connection and try again.",
    "Could not verify the CAPTCHA. Please try again.":
        "Could not complete human verification. Please try again.",
    "Email has not been verified.":
        "Verify your email before setting your password.",
    "Failed to create account.":
        "Could not create your account. Please try again.",
    "Failed to create user account.":
        "Could not create your account. Please try again.",
    "Failed to create user information.":
        "Could not create your account. Please try again.",
    "Failed to reset password.":
        "Could not reset your password. Please try again.",
    "Failed to send password reset code.":
        "Could not send the password reset code. Please try again.",
    "Failed to send verification code.":
        "Could not send the verification code. Please try again.",
    "Failed to send verification code. Please try again.":
        "Could not send the verification code. Please try again.",
    "Failed to update password.":
        "Could not update your password. Please try again.",
    "GPS is unavailable. Check Location Services and permissions.":
        "Could not find your location. Check location services and app permissions.",
    "History request failed.": "Could not load your history. Please try again.",
    "Human verification has not been set up yet. Please contact support.":
        "Human verification is unavailable. Please try again later.",
    "Human verification is not available on this server yet. Please contact support.":
        "Human verification is unavailable. Please try again later.",
    "Human verification is not configured on the server. Please contact support.":
        "Human verification is unavailable. Please try again later.",
    "Human verification is not enabled for this app address. Please contact support.":
        "Human verification is unavailable here. Please try again later.",
    "Invalid OTP.": "That code is incorrect. Please try again.",
    "Invalid username/email or password.":
        "Check your username or email and password, then try again.",
    "Login failed.": "Could not sign in. Please try again.",
    "No pending signup found.":
        "Your account setup is no longer available. Please create your account again.",
    "No pending verification found.":
        "No verification code was requested. Please request a code.",
    "OTP expired. Please request a new OTP.":
        "Verification code expired. Please request a new code.",
    "OTP has expired. Please request a new OTP.":
        "Verification code expired. Please request a new code.",
    "OTP verification failed.": "Could not verify the code. Please try again.",
    "Please enter a valid email address.": "Enter a valid email address.",
    "Please enter and confirm your new password.":
        "Enter and confirm your new password.",
    "Please enter and confirm your password.":
        "Enter and confirm your password.",
    "Please enter your current password.": "Enter your current password.",
    "Please enter your username or email.": "Enter your username or email.",
    "Please fill in both Username and Email.":
        "Enter your username and email address.",
    "Please fill in both Username and Password.":
        "Enter your username or email and password.",
    "Please meet all password requirements.": "Meet all password requirements.",
    "Please meet all required password criteria.":
        "Meet all password requirements.",
    "Please select Student, Staff, or Visitor.":
        "Select Student, Staff, or Visitor.",
    "Please verify your OTP first.": "Verify your code before continuing.",
    "Stopped after a connection or file verification problem. Resume to try again.":
        "The download stopped. Select Resume to try again.",
    "That is already your email.": "Enter a different email address.",
    "The main gate could not be identified uniquely in the routing network.":
        "A route from the main gate is unavailable.",
    "The published campus data is invalid. Try again later.":
        "The offline map could not be prepared. Try again later.",
    "The server has not published a valid precomputed offline pack yet. Try again later.":
        "The offline map is not available yet. Try again later.",
    "Too many OTP attempts. Please request a new OTP.":
        "Too many incorrect codes. Please request a new code.",
    "Too many incorrect attempts. Please request a new OTP.":
        "Too many incorrect codes. Please request a new code.",
    "Unable to load routes for this transport mode.":
        "Could not load routes for this travel mode.",
    "User information not found.": "Could not find your account details.",
    "Verification expired. Please request a new OTP.":
        "Verification code expired. Please request a new code.",
  };

  static const _known = <String>{
    "A route from the main gate is unavailable.",
    "Account created successfully! Welcome to ISU-CAMP.",
    "Account created, but this device could not remember your session.",
    "Account not found.",
    "Account setup session expired. Please try again.",
    "Campus locations are temporarily unavailable.",
    "Campus photo is unavailable.",
    "Campus photo not found.",
    "Campus photos are temporarily unavailable.",
    "Campus routes are temporarily unavailable.",
    "Check your username or email and password, then try again.",
    "Choose a different travel mode.",
    "Code verification failed.",
    "Could not clear history. Please try again.",
    "Could not clear the saved session. Please try logging out again.",
    "Could not complete human verification. Please try again.",
    "Could not complete verification. Check your connection and try again.",
    "Could not create your account. Please try again.",
    "Could not delete history. Please try again.",
    "Could not download the campus data. Check your connection and try again.",
    "Could not find your account details.",
    "Could not find your location. Check location services and app permissions.",
    "Could not load campus locations.",
    "Could not load history. Please try again.",
    "Could not load routes for this travel mode.",
    "Could not load the offline map. Check your connection and try again.",
    "Could not load the published offline map. Check your connection and try again.",
    "Could not load your account.",
    "Could not load your history. Please try again.",
    "Could not load your profile. Check your connection and try again.",
    "Could not load your profile. Please try again.",
    "Could not prepare offline storage. Check your free space and try again.",
    "Could not reach the verification service. Please try again later.",
    "Could not read the offline map. Try again later.",
    "Could not reset your password. Please try again.",
    "Could not save history. Please try again.",
    "Could not save your account type. Please try again.",
    "Could not save your profile. Check your connection and try again.",
    "Could not save your profile. Please try again.",
    "Could not save your username. Check your connection and try again.",
    "Could not save your username. Please try again.",
    "Could not send the password reset code. Please try again.",
    "Could not send the verification code.",
    "Could not send the verification code. Please try again.",
    "Could not sign in. Please try again.",
    "Could not update your email. Please try again.",
    "Could not update your password.",
    "Could not update your password. Please try again.",
    "Could not update your profile. Please try again.",
    "Could not verify the CAPTCHA. Please try again.",
    "Could not verify the code. Please try again.",
    "Current location is unavailable. You can choose another starting point.",
    "Current password is incorrect.",
    "Directions from this building are unavailable. Choose another starting point.",
    "Directions to this building are unavailable.",
    "Email has not been verified.",
    "Email is already registered.",
    "Email updated. This device could not refresh its saved profile.",
    "Enter a different email address.",
    "Enter a valid email address.",
    "Enter and confirm your new password.",
    "Enter and confirm your password.",
    "Enter your current password.",
    "Enter your username and email address.",
    "Enter your username or email and password.",
    "Enter your username or email.",
    "Failed to create account.",
    "Failed to create user account.",
    "Failed to create user information.",
    "Failed to reset password.",
    "Failed to send password reset code.",
    "Failed to send verification code.",
    "Failed to send verification code. Please try again.",
    "Failed to update password.",
    "GPS is unavailable. Check Location Services and permissions.",
    "History request failed.",
    "History was not saved. Please try again.",
    "Human verification could not open. Please try again later.",
    "Human verification expired or failed. Please try again.",
    "Human verification has not been set up yet. Please contact support.",
    "Human verification is available on Android, iOS, macOS, and web.",
    "Human verification is not available on this server yet. Please contact support.",
    "Human verification is not configured on the server. Please contact support.",
    "Human verification is not enabled for this app address. Please contact support.",
    "Human verification is unavailable here. Please try again later.",
    "Human verification is unavailable. Please try again later.",
    "Invalid OTP.",
    "Invalid username/email or password.",
    "Login failed.",
    "Meet all password requirements.",
    "New password must be different from your current password.",
    "No buildings found.",
    "No campus locations available yet.",
    "No interior rooms or offices in this facility.",
    "No mapped route is available.",
    "No matching destinations found.",
    "No navigation history yet.\\\\nPreviewed and started routes will appear here.",
    "No other campus buildings are available.",
    "No pending signup found.",
    "No pending verification found.",
    "No verification code was requested. Please request a code.",
    "No verification request found. Please request a new code.",
    "OTP expired. Please request a new OTP.",
    "OTP has expired. Please request a new OTP.",
    "OTP verification failed.",
    "Offline pack file not found.",
    "Password must be at least 8 characters long.",
    "Password must be at least 8 characters.",
    "Password must contain a lowercase letter.",
    "Password must contain a number.",
    "Password must contain a symbol.",
    "Password must contain an uppercase letter.",
    "Password must contain at least one lowercase letter.",
    "Password must contain at least one number.",
    "Password must contain at least one special character.",
    "Password must contain at least one uppercase letter.",
    "Password reset closed because there was no activity.",
    "Password setup session expired. Please try again.",
    "Password updated successfully. You can now log in.",
    "Password updated.",
    "Passwords do not match.",
    "Please agree to the Terms & Conditions and Privacy Policy.",
    "Please complete human verification.",
    "Please enter a valid email address.",
    "Please enter and confirm your new password.",
    "Please enter and confirm your password.",
    "Please enter your current password.",
    "Please enter your username or email.",
    "Please fill in both Username and Email.",
    "Please fill in both Username and Password.",
    "Please log in again to access your history.",
    "Please log in again to edit your profile.",
    "Please log in again to save your navigation history.",
    "Please log in to access your history.",
    "Please meet all password requirements.",
    "Please meet all required password criteria.",
    "Please select Student, Staff, or Visitor.",
    "Please verify your OTP first.",
    "Please wait before requesting another code.",
    "Select Student, Staff, or Visitor.",
    "Session service is not configured.",
    "Stopped after a connection or file verification problem. Resume to try again.",
    "That code is incorrect. Please try again.",
    "That email is already in use.",
    "That is already your email.",
    "The download stopped. Select Resume to try again.",
    "The main gate could not be identified uniquely in the routing network.",
    "The offline map could not be prepared. Try again later.",
    "The offline map download is temporarily unavailable.",
    "The offline map is not available yet. Try again later.",
    "The offline map pack is being prepared. Try again later.",
    "The published campus data is invalid. Try again later.",
    "The server has not published a valid precomputed offline pack yet. Try again later.",
    "The verification service is temporarily unavailable. Please try again later.",
    "The verification service took too long to respond. Please try again.",
    "This building has no active entrance linked to the routing network.",
    "This building is no longer available.",
    "This destination is no longer available. Refresh the map and try again.",
    "This room does not belong to the selected building.",
    "This will remove all your saved destinations.",
    "Too many OTP attempts. Please request a new OTP.",
    "Too many code requests. Please try again later.",
    "Too many failed login attempts. Please try again in 5 minutes.",
    "Too many incorrect attempts. Please request a new OTP.",
    "Too many incorrect attempts. Please try again later.",
    "Too many incorrect codes. Please request a new code.",
    "Unable to load routes for this transport mode.",
    "Use 3\\u201330 letters, numbers, or underscores for your username.",
    "User account not found.",
    "User information not found.",
    "Username \\u2013 used to create and identify your account.",
    "Username is already taken.",
    "Profile updated.",
    "Profile updated. This device could not refresh its saved profile.",
    "Username updated.",
    "Username updated. This device could not refresh its saved profile.",
    "Verification code expired. Please create your account again.",
    "Verification code expired. Please request a new code.",
    "Verification code sent to your registered email.",
    "Verification could not load. Close and try again.",
    "Verification expired. Please request a new OTP.",
    "Verify your code before continuing.",
    "Verify your email before setting your password.",
    "Your account setup is no longer available. Please create your account again.",
    "Your code will be verified automatically.",
    "Your current route progress will be cleared.",
    "Your information is used to provide account navigation and app functionality and is not intentionally sold for advertising purposes. Reasonable measures are taken to protect your information from unauthorized access.\\\\n\\\\nBy creating an account, you acknowledge that you have read and understood this Privacy Policy.",
    "Your session has expired. Please log in again.",

  };

  static String present(Object error, String fallback) {
    final message = error.toString().replaceFirst(RegExp(r'^Exception: '), '');
    final replacement = replacements[message];
    if (replacement != null) return replacement;
    final attempts = RegExp(r'^Invalid OTP\. (\d+) attempt\(s\) remaining\.$')
        .firstMatch(message);
    if (attempts != null) {
      final count = int.parse(attempts.group(1)!);
      return 'That code is incorrect. $count ${count == 1 ? 'attempt' : 'attempts'} remaining.';
    }
    final route = RegExp(
            r'^No (?:connected )?(walking|bicycle|motorcycle|car|vehicle|driving) (starting point|route to this building) is available on permitted pathways\.$')
        .firstMatch(message);
    if (route != null) {
      return route.group(2) == 'starting point'
          ? 'No starting point is available for this ${route.group(1)} route.'
          : 'No ${route.group(1)} route to this building is available.';
    }
    for (final mode in const ['walking', 'car', 'motorcycle', 'bicycle']) {
      if (message == 'No $mode route to this building is available.' ||
          message == 'No starting point is available for this $mode route.' ||
          message == 'No $mode route is available.') return message;
      if (message == 'No permitted $mode pathway within 200 m. Choose a campus building or the main gate.') {
        return 'No $mode route starts within 200 m of this location. Choose a campus building or the main gate.';
      }
    }
    return _known.contains(message) ? message : fallback;
  }
}
