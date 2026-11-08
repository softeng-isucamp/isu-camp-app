# Error-message assessment

All 209 original extraction candidates have a disposition: 15 Internal only, 82 Keep, 58 Not an error, 54 Reworded.

This assessment supersedes the earlier provisional audits.

## Scope and implementation

Flutter display boundaries now translate recognized server messages and hide unrecognized exception diagnostics behind an operation-specific fallback. Backend responses, HTTP codes, verification metadata, regex-based attempt parsing and account/session operations remain unchanged. Known useful password, session, duplicate-account and validation messages are retained. The login lockout snackbar uses the Retry-After countdown. History-save errors are displayed once without a repeated prefix.

The candidate extraction was noisy: success messages, URLs, comments, labels, legal text and parser tokens were not user-facing errors. Internal offline download failures remain diagnostic strings: `_fetchInto` catches them and reports a controlled download status. Baseline source references in the CSV intentionally refer to the pre-change checkout.

## Verification and limits

Existing Flutter tests cover auth, profile/security, history, route failures and offline state transitions. New presentation tests cover hidden diagnostics, legacy OTP wording and attempt counts, session recovery, and route mode preservation. Flutter web captures cover representative visible validation and verification states using synthetic input and a local fixture API; no real email or accounts are used. These screenshots do not claim every device/platform-specific failure was induced. New backend messages safely fall back until explicitly reviewed and mapped.

## Candidate-by-candidate assessment

| ID | Original | Assessment | Resulting wording |
|---|---|---|---|
| 1 | Invalid offline pack file | Internal only | Unchanged |
| 2 | The server has not published a precomputed offline pack | Internal only | Unchanged |
| 3 | Invalid offline pack metadata | Internal only | Unchanged |
| 4 | Offline pack total does not match its files | Internal only | Unchanged |
| 5 | The downloaded campus map is already up to date. | Not an error | Unchanged |
| 6 | Campus map updated. Offline navigation is using the new data. | Not an error | Unchanged |
| 7 | Campus map downloaded. Offline navigation is now active. | Not an error | Unchanged |
| 8 | Delete offline map? | Not an error | Unchanged |
| 9 | Offline map deleted from storage. | Not an error | Unchanged |
| 10 | Offline Map | Not an error | Unchanged |
| 11 | To use KUMPAS offline, start by downloading the map.  | Not an error | Unchanged |
| 12 | ${status.sizeLabel} • Offline Ready | Not an error | Unchanged |
| 13 | Delete offline map | Not an error | Unchanged |
| 14 | Offline Building Search | Not an error | Unchanged |
| 15 | Turn-by-Turn Offline Routing | Not an error | Unchanged |
| 16 | ${_baseUrl()}/campus/offline/manifest | Not an error | Unchanged |
| 17 | The offline map pack is being prepared. Try again later. | Keep | The offline map pack is being prepared. Try again later. |
| 18 | The server has not published a valid precomputed offline pack yet. Try again later. | Reworded | The offline map is not available yet. Try again later. |
| 19 | Could not load the published offline map. Check your connection and try again. | Reworded | Could not load the offline map. Check your connection and try again. |
| 20 | Could not prepare offline storage. Check your free space and try again. | Keep | Could not prepare offline storage. Check your free space and try again. |
| 21 | Could not download the campus data. Check your connection and try again. | Keep | Could not download the campus data. Check your connection and try again. |
| 22 | The published campus data is invalid. Try again later. | Reworded | The offline map could not be prepared. Try again later. |
| 23 | Could not read the offline map. Try again later. | Keep | Could not read the offline map. Try again later. |
| 24 | Paused. Resume to finish downloading the offline map. | Keep | Paused. Resume to finish downloading the offline map. |
| 25 | Stopped after a connection or file verification problem. Resume to try again. | Reworded | The download stopped. Select Resume to try again. |
| 26 | Offline pack file is unavailable. | Internal only | Unchanged |
| 27 | Offline pack file exceeds its published size. | Internal only | Unchanged |
| 28 | ${_baseUrl()}/campus/offline/packs/${manifest.version}/${file.path} | Not an error | Unchanged |
| 29 | Offline pack checksum did not match. | Internal only | Unchanged |
| 30 | Download the offline map to get directions without a connection. | Not an error | Unchanged |
| 31 | The main gate could not be identified uniquely in the routing network. | Reworded | A route from the main gate is unavailable. |
| 32 | No ${label.toLowerCase()} starting point is available on permitted pathways. | Reworded | No starting point is available for this {travel mode} route. |
| 33 | No connected ${label.toLowerCase()} route to this building is available on permitted pathways. | Reworded | No {travel mode} route to this building is available. |
| 34 | Your offline map still works. Download the update when you  | Not an error | Unchanged |
| 35 | Our goal is to make campus navigation faster, easier, and more accessible by providing interactive maps, location searching, route recommendations, and offline navigation capabilities. Through KUMPAS, we aim to reduce confusion when finding unfamiliar locations and provide users with a more convenient way to navigate the campus. | Not an error | Unchanged |
| 36 | Unable to load campus locations. Check your connection and try again. | Keep | Unable to load campus locations. Check your connection and try again. |
| 37 | Location permission is needed to show your position. | Keep | Location permission is needed to show your position. |
| 38 | GPS is unavailable. Check Location Services and permissions. | Reworded | Could not find your location. Check location services and app permissions. |
| 39 | Current location is unavailable. You can choose another starting point. | Keep | Current location is unavailable. You can choose another starting point. |
| 40 | Please log in again to save your navigation history. | Keep | Please log in again to save your navigation history. |
| 41 | History was not saved. ${error.toString().replaceFirst( | Reworded | Known history error once, or: Could not save your navigation history. |
| 42 | No mapped route is available. | Keep | No mapped route is available. |
| 43 | Route update failed. ${error.toString().replaceFirst( | Reworded | Known route error, or: Could not update your route. |
| 44 | tiles-${OfflinePackService.instance.status.installedVersion ??  | Not an error | Unchanged |
| 45 | No campus locations available yet. | Keep | No campus locations available yet. |
| 46 | Recenter and follow direction | Not an error | Unchanged |
| 47 | Could not clear the saved session. Please try logging out again. | Keep | Could not clear the saved session. Please try logging out again. |
| 48 | This destination is no longer available. Refresh the map and try again. | Keep | This destination is no longer available. Refresh the map and try again. |
| 49 | Photo unavailable | Not an error | Unchanged |
| 50 | No other campus buildings are available. | Keep | No other campus buildings are available. |
| 51 | No ${routeModeLabel(_selectedMode).toLowerCase()} route is available on permitted pathways. | Reworded | No {travel mode} route is available. |
| 52 | Could not load your profile. Check your connection and try again. | Keep | Could not load your profile. Check your connection and try again. |
| 53 | Username updated. This device could not refresh its saved profile. | Keep | Username updated. This device could not refresh its saved profile. |
| 54 | Could not save your username. Check your connection and try again. | Keep | Could not save your username. Check your connection and try again. |
| 55 | Could not load your account. | Keep | Could not load your account. |
| 56 | Verification code expired. Please request a new code. | Keep | Verification code expired. Please request a new code. |
| 57 | Password setup session expired. Please try again. | Keep | Password setup session expired. Please try again. |
| 58 | Enter the 6-digit verification code sent to $sentTo. | Not an error | Unchanged |
| 59 | Enter the 6-digit verification code sent to $email. | Not an error | Unchanged |
| 60 | Email updated. This device could not refresh its saved profile. | Keep | Email updated. This device could not refresh its saved profile. |
| 61 | Enter a valid email address. | Keep | Enter a valid email address. |
| 62 | That is already your email. | Reworded | Enter a different email address. |
| 63 | We will send a verification code to your new email. Your email changes once you enter it. | Not an error | Unchanged |
| 64 | Please log in again to access your history. | Keep | Please log in again to access your history. |
| 65 | History request failed. | Reworded | Could not load your history. Please try again. |
| 66 | Unable to load routes for this transport mode. | Reworded | Could not load routes for this travel mode. |
| 67 | Could not load campus locations. | Keep | Could not load campus locations. |
| 68 | Please log in again to edit your profile. | Keep | Please log in again to edit your profile. |
| 69 | Could not update your profile. Please try again. | Keep | Could not update your profile. Please try again. |
| 70 | Could not send the verification code. | Keep | Could not send the verification code. |
| 71 | Code verification failed. | Reworded | Could not verify the code. Please try again. |
| 72 | Could not update your password. | Keep | Could not update your password. |
| 73 | Select a result to see its building, floor, room, or location details. | Not an error | Unchanged |
| 74 | Select your starting point and destination, then tap Get Directions. | Not an error | Unchanged |
| 75 | Select your preferred route: | Not an error | Unchanged |
| 76 | Use Offline Mode | Not an error | Unchanged |
| 77 | Download the campus map and required navigation data while connected to the internet. | Not an error | Unchanged |
| 78 | If you encounter incorrect location information, missing locations, or other issues while using KUMPAS, please contact the system administrator or report the issue through the provided support option. | Not an error | Unchanged |
| 79 | Please contact  | Not an error | Unchanged |
| 80 | Verification code expired. Please create your account again. | Keep | Verification code expired. Please create your account again. |
| 81 | Account setup session expired. Please try again. | Keep | Account setup session expired. Please try again. |
| 82 | Please fill in both Username and Email. | Reworded | Enter your username and email address. |
| 83 | Please select Student, Staff, or Visitor. | Reworded | Select Student, Staff, or Visitor. |
| 84 | Please enter a valid email address. | Reworded | Enter a valid email address. |
| 85 | Please enter and confirm your password. | Reworded | Enter and confirm your password. |
| 86 | Passwords do not match. | Keep | Passwords do not match. |
| 87 | Please meet all required password criteria. | Reworded | Meet all password requirements. |
| 88 | Please agree to the Terms & Conditions and Privacy Policy. | Keep | Please agree to the Terms & Conditions and Privacy Policy. |
| 89 | Account created, but this device could not remember your session. | Not an error | Unchanged |
| 90 | Offline maps may become outdated and should be updated when an internet connection is available. | Not an error | Unchanged |
| 91 | Users must not misuse the application or access it for unauthorized purposes. | Not an error | Unchanged |
| 92 | Offline Data – downloaded maps and navigation information may be stored on your device for offline use. | Not an error | Unchanged |
| 93 | Enter your username and email to get started. | Not an error | Unchanged |
| 94 | Select account type | Not an error | Unchanged |
| 95 | Already have account? Log in | Not an error | Unchanged |
| 96 | . Enter it below to verify your email. | Not an error | Unchanged |
| 97 | Too many incorrect codes. Try again in ${_security.format(_security.verificationLockRemaining)} | Keep | Too many incorrect codes. Try again in ${_security.format(_security.verificationLockRemaining)} |
| 98 | Code expires in ${_security.format(_security.codeRemaining)} • ${_security.attemptsRemaining} attempts left | Not an error | Unchanged |
| 99 | Enter password | Not an error | Unchanged |
| 100 | Re-enter password | Not an error | Unchanged |
| 101 | Too many failed attempts. Try again in ${_formatLockoutTime()}. | Keep | Too many failed attempts. Try again in ${_formatLockoutTime()}. |
| 102 | Please fill in both Username and Password. | Reworded | Enter your username or email and password. |
| 103 | Please complete human verification. | Keep | Please complete human verification. |
| 104 | Signed in, but this device could not remember your session. | Not an error | Unchanged |
| 105 | Enter your username or email. We will send a verification code to your registered email. | Not an error | Unchanged |
| 106 | Please enter your username or email. | Reworded | Enter your username or email. |
| 107 | Enter the 6-digit verification code sent to your registered email. | Not an error | Unchanged |
| 108 | Try again in ${_formatLockoutTime()} | Not an error | Unchanged |
| 109 | ${(6 - _failedLoginAttempts).clamp(0, 6)} login attempts remaining | Reworded | {N} sign-in attempt(s) remaining |
| 110 | The verification service took too long to respond. Please try again. | Keep | The verification service took too long to respond. Please try again. |
| 111 | Could not reach the verification service. Please try again later. | Keep | Could not reach the verification service. Please try again later. |
| 112 | Human verification is not available on this server yet. Please contact support. | Reworded | Human verification is unavailable. Please try again later. |
| 113 | Human verification has not been set up yet. Please contact support. | Reworded | Human verification is unavailable. Please try again later. |
| 114 | Human verification is not enabled for this app address. Please contact support. | Reworded | Human verification is unavailable here. Please try again later. |
| 115 | The verification service is temporarily unavailable. Please try again later. | Keep | The verification service is temporarily unavailable. Please try again later. |
| 116 | invalid otp | Not an error | Unchanged |
| 117 | Could not complete verification. Check your connection and try again. | Keep | Could not complete verification. Check your connection and try again. |
| 118 | (\d+)\s+attempt\(s\)\s+remaining | Not an error | Unchanged |
| 119 | too many | Not an error | Unchanged |
| 120 | Login failed. | Reworded | Could not sign in. Please try again. |
| 121 | Failed to send verification code. | Reworded | Could not send the verification code. Please try again. |
| 122 | OTP verification failed. | Reworded | Could not verify the code. Please try again. |
| 123 | Failed to create account. | Reworded | Could not create your account. Please try again. |
| 124 | Failed to send password reset code. | Reworded | Could not send the password reset code. Please try again. |
| 125 | Failed to reset password. | Reworded | Could not reset your password. Please try again. |
| 126 | Verification could not load. Close and try again. | Keep | Verification could not load. Close and try again. |
| 127 | Human verification could not open. Please try again later. | Keep | Human verification could not open. Please try again later. |
| 128 | Try again in ${security.format(security.verificationLockRemaining)} | Not an error | Unchanged |
| 129 | Code expires in ${security.format(security.codeRemaining)} • ${security.attemptsRemaining} attempts left | Not an error | Unchanged |
| 130 | Please enter your current password. | Reworded | Enter your current password. |
| 131 | Please enter and confirm your new password. | Reworded | Enter and confirm your new password. |
| 132 | Please meet all password requirements. | Reworded | Meet all password requirements. |
| 133 | Enter current password | Not an error | Unchanged |
| 134 | Enter new password | Not an error | Unchanged |
| 135 | Re-enter new password | Not an error | Unchanged |
| 136 | Email is already registered. | Keep | Email is already registered. |
| 137 | Username is already taken. | Keep | Username is already taken. |
| 138 | Too many OTP attempts. Please request a new OTP. | Reworded | Too many incorrect codes. Please request a new code. |
| 139 | OTP has expired. Please request a new OTP. | Reworded | Verification code expired. Please request a new code. |
| 140 | Invalid OTP. | Reworded | That code is incorrect. Please try again. |
| 141 | Password must be at least 8 characters long. | Keep | Password must be at least 8 characters long. |
| 142 | Password must contain an uppercase letter. | Keep | Password must contain an uppercase letter. |
| 143 | Password must contain a lowercase letter. | Keep | Password must contain a lowercase letter. |
| 144 | Password must contain a number. | Keep | Password must contain a number. |
| 145 | Password must contain a symbol. | Keep | Password must contain a symbol. |
| 146 | Failed to create user information. | Reworded | Could not create your account. Please try again. |
| 147 | Failed to create user account. | Reworded | Could not create your account. Please try again. |
| 148 | Unavailable building | Not an error | Unchanged |
| 149 | Could not load history | Internal only | Unchanged |
| 150 | Could not load history. Please try again. | Keep | Could not load history. Please try again. |
| 151 | This building is no longer available. | Keep | This building is no longer available. |
| 152 | History was not saved. Please try again. | Keep | History was not saved. Please try again. |
| 153 | Could not save history | Internal only | Unchanged |
| 154 | Could not save history. Please try again. | Keep | Could not save history. Please try again. |
| 155 | Could not clear history | Internal only | Unchanged |
| 156 | Could not clear history. Please try again. | Keep | Could not clear history. Please try again. |
| 157 | Could not delete history | Internal only | Unchanged |
| 158 | Could not delete history. Please try again. | Keep | Could not delete history. Please try again. |
| 159 | Campus photo not found. | Keep | Campus photo not found. |
| 160 | Campus photo is unavailable. | Keep | Campus photo is unavailable. |
| 161 | Could not load campus photo | Internal only | Unchanged |
| 162 | Campus photos are temporarily unavailable. | Keep | Campus photos are temporarily unavailable. |
| 163 | The whole transport graph; the offline pack routes from these same rows. | Not an error | Unchanged |
| 164 | Could not compute campus routes | Internal only | Unchanged |
| 165 | Campus routes are temporarily unavailable. | Keep | Campus routes are temporarily unavailable. |
| 166 | Could not load campus buildings | Internal only | Unchanged |
| 167 | Campus locations are temporarily unavailable. | Keep | Campus locations are temporarily unavailable. |
| 168 | Offline pack file not found. | Keep | Offline pack file not found. |
| 169 | Could not build the offline campus bundle | Internal only | Unchanged |
| 170 | The offline map download is temporarily unavailable. | Keep | The offline map download is temporarily unavailable. |
| 171 | Return remaining lockout seconds for an identifier, or 0 if unlocked. | Not an error | Unchanged |
| 172 | Record a failed attempt and return (attempt count, lockout seconds). | Not an error | Unchanged |
| 173 | Too many failed login attempts. Please try again in 5 minutes. | Reworded | Too many failed attempts. Try again in {mm:ss}. |
| 174 | Invalid username/email or password. | Reworded | Check your username or email and password, then try again. |
| 175 | User account not found. | Keep | User account not found. |
| 176 | Account not found. | Keep | Account not found. |
| 177 | User information not found. | Reworded | Could not find your account details. |
| 178 | Failed to update password. | Reworded | Could not update your password. Please try again. |
| 179 | Could not load your profile. Please try again. | Keep | Could not load your profile. Please try again. |
| 180 | Could not save your username. Please try again. | Keep | Could not save your username. Please try again. |
| 181 | That email is already in use. | Keep | That email is already in use. |
| 182 | Current password is incorrect. | Keep | Current password is incorrect. |
| 183 | Could not update your password. Please try again. | Keep | Could not update your password. Please try again. |
| 184 | Could not update your email. Please try again. | Keep | Could not update your email. Please try again. |
| 185 | Human verification is not configured on the server. Please contact support. | Reworded | Human verification is unavailable. Please try again later. |
| 186 | Could not verify the CAPTCHA. Please try again. | Reworded | Could not complete human verification. Please try again. |
| 187 | Human verification expired or failed. Please try again. | Keep | Human verification expired or failed. Please try again. |
| 188 | No {label.lower()} starting point is available on permitted pathways. | Reworded | No starting point is available for this {travel mode} route. |
| 189 | No connected {label.lower()} route to this building is available on permitted pathways. | Reworded | No {travel mode} route to this building is available. |
| 190 | Please log in to access your history. | Keep | Please log in to access your history. |
| 191 | Your session has expired. Please log in again. | Keep | Your session has expired. Please log in again. |
| 192 | Content hash of the offline dataset; equal payloads always hash equally. | Not an error | Unchanged |
| 193 | Every cover photo the offline pack has to store, buildings and rooms. | Not an error | Unchanged |
| 194 | Too many incorrect attempts. Please try again later. | Keep | Too many incorrect attempts. Please try again later. |
| 195 | Please wait before requesting another code. | Keep | Please wait before requesting another code. |
| 196 | Too many code requests. Please try again later. | Keep | Too many code requests. Please try again later. |
| 197 | Password must be at least 8 characters. | Keep | Password must be at least 8 characters. |
| 198 | Password must contain at least one uppercase letter. | Keep | Password must contain at least one uppercase letter. |
| 199 | Password must contain at least one lowercase letter. | Keep | Password must contain at least one lowercase letter. |
| 200 | Password must contain at least one number. | Keep | Password must contain at least one number. |
| 201 | Password must contain at least one special character. | Keep | Password must contain at least one special character. |
| 202 | New password must be different from your current password. | Keep | New password must be different from your current password. |
| 203 | Failed to send verification code. Please try again. | Reworded | Could not send the verification code. Please try again. |
| 204 | No verification request found. Please request a new code. | Keep | No verification request found. Please request a new code. |
| 205 | OTP expired. Please request a new OTP. | Reworded | Verification code expired. Please request a new code. |
| 206 | Too many incorrect attempts. Please request a new OTP. | Reworded | Too many incorrect codes. Please request a new code. |
| 207 | Invalid OTP. {remaining} attempt(s) remaining. | Reworded | That code is incorrect. {N} attempt(s) remaining. |
| 208 | Please verify your OTP first. | Reworded | Verify your code before continuing. |
| 209 | Verification expired. Please request a new OTP. | Reworded | Verification code expired. Please request a new code. |
