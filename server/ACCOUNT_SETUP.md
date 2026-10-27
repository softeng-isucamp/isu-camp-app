# CAPTCHA and profile setup

The login checkbox is replaced by Google reCAPTCHA v2 Checkbox. The app opens a
challenge hosted by its configured API, and `/auth/login` verifies the returned
`captcha_token` with Google before reading credentials. Missing configuration,
invalid/expired tokens, and provider failures reject login; there is no bypass.

Configure these variables in the ignored `server/.env` and deployment environment:

```dotenv
RECAPTCHA_SITE_KEY=your_public_v2_checkbox_site_key
RECAPTCHA_SECRET_KEY=your_private_v2_secret_key
RECAPTCHA_ALLOWED_HOSTNAMES=localhost,api.kumpas.live
RECAPTCHA_PARENT_ORIGINS=http://localhost:5173,https://your-app-domain.example
```

## First-time local setup

1. Open [Google's reCAPTCHA registration page](https://www.google.com/recaptcha/admin/create).
   Register **reCAPTCHA v2 → "I'm not a robot" Checkbox**, with `localhost`
   as a domain for local browser development. Domain entries do not include
   `http://`, a port, or a path.
2. Copy the real site key and secret key into `server/.env`, using the variable
   names above. Keep the secret in this ignored backend file; do not send it in
   chat or put it in Flutter. For local web, set allowed hostnames to `localhost`
   and parent origins to `http://localhost:5173`.
3. Restart the running backend so it reloads the environment:

   ```powershell
   cd server
   .\.venv\Scripts\python.exe -m uvicorn app.main:app --host 0.0.0.0 --port 8000
   ```

4. Stop and restart Flutter using **ISU-CAMP (Chrome)** or **ISU-CAMP (Edge)**
   in VS Code. Both profiles use port 5173. Alternatively, from the repository root:

   ```powershell
   flutter run -d chrome --web-port=5173 --dart-define=API_BASE_URL=http://localhost:8000
   ```

5. Check the backend before opening the challenge:

   ```powershell
   Invoke-RestMethod 'http://localhost:8000/auth/captcha/config?parent_origin=http://localhost:5173'
   ```

   It should return `provider: recaptcha-v2`. Then open verification in the app
   and complete Google's challenge. A successful config check alone does not
   prove the Google keys are valid; complete a login to test server verification.

## Troubleshooting

- **503 / `captcha_not_configured`**: site key, secret key, or allowed hostnames
  are missing from the backend environment. Internet access alone cannot fix this.
- **403 / `captcha_origin_not_allowed`**: the browser origin is not in
  `RECAPTCHA_PARENT_ORIGINS`. Use the fixed port above and the exact hostname
  (`localhost` and `127.0.0.1` are different origins).
- **404**: the selected backend does not have the new CAPTCHA routes deployed.
- **Cannot reach service / timeout**: check that the selected API is running and
  reachable from the device. Browser CORS or mixed-content restrictions may also
  block a request.
- **Google reports an invalid key or domain**: verify that the key is for v2
  Checkbox and that the CAPTCHA page's hostname is registered in Google's console.

## Deployment and profile updates

Register the CAPTCHA page's hostname (the API hostname) in the Google console.
Use separate development and production key pairs. Allowed hostnames must match
Google's verification response. For Android emulators and physical devices, point
`API_BASE_URL` to a registered HTTPS hostname rather than an emulator or LAN IP.
Never commit the secret or put it in
Flutter, and do not use Google's always-passing test key in production.

For Flutter web, the parent origin must exactly match the web app, including
port; choose a fixed local port with `flutter run -d chrome --web-port=5173`.
The web frame checks both message origin and source, and the server only sends
tokens to configured parent origins. Android/iOS/macOS use the same hosted
challenge in a WebView. Native Windows/Linux verification is not supported by
this WebView package; use Flutter web on those systems.

Restart the backend after configuring the keys. When targeting the live API,
deploy these routes together with the Flutter app. An older deployed server
without `/auth/captcha/config`, `/auth/captcha`, and `/profile` cannot support the
new flows. No live deployment is performed by this change.

Provider reference: https://developers.google.com/recaptcha/docs/verify

`GET /profile` returns the signed-in user's username and registered email.
`PATCH /profile` accepts only `username`, and derives the user id from the Bearer
session. Email remains read-only. Usernames use 3–30 ASCII letters, digits, or
underscores. Case-insensitive duplicate names are rejected.

To enforce case-insensitive uniqueness even during concurrent updates, apply the
following index through your existing database migration process. Resolve any
existing duplicate names first; this change does not run migrations on live data.

```sql
CREATE UNIQUE INDEX IF NOT EXISTS user_username_lower_unique
ON public."user" (lower(username));
```
