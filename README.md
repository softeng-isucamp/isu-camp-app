## User App repository for ISU-CAMP

### API backend

The app uses a local API by default. To run against
the repository backend on your own machine, start it in a separate PowerShell
terminal (requires the server virtual environment and configured `server/.env`):

```powershell
cd server
.\.venv\Scripts\python.exe -m uvicorn app.main:app --host 0.0.0.0 --port 8000
```

From the repository root, use the address for your target device:

```powershell
# Web or desktop, backend on this machine
flutter run -d chrome --web-port=5173 --dart-define=API_BASE_URL=http://localhost:8000

# Android emulator, backend on the host machine
flutter run -d emulator-5554 --dart-define=API_BASE_URL=http://10.0.2.2:8000

# Physical phone on the same Wi-Fi; replace with your computer's LAN IP
flutter run --dart-define=API_BASE_URL=http://192.168.x.x:8000
```

`10.0.2.2` connects the Android emulator to the host PC. For a physical phone,
allow inbound connections to port 8000 and use the computer's LAN IP. HTTP is
enabled only in the Android debug manifest. Keep the backend running while
testing. Changing `API_BASE_URL` requires restarting the Flutter run, not just
hot reload. To explicitly select the live API, pass
`--dart-define=API_BASE_URL=https://api.kumpas.live`.

Without the override, Android uses `http://10.0.2.2:8000`; web and desktop use
`http://localhost:8000`. For local browser development, select
`ISU-CAMP (Chrome)` or `ISU-CAMP (Edge)` in VS Code, both on port 5173.
To use the deployed backend, pass
`--dart-define=API_BASE_URL=https://api.kumpas.live`. Login now uses real reCAPTCHA
with backend token verification. Configure the provider keys and deploy the matching
backend routes before using these flows. See [CAPTCHA and profile setup](server/ACCOUNT_SETUP.md).

Campus buildings and rooms return photo URLs instead of embedded image bytes.
The public `/campus/photos/building/{photo_id}` and
`/campus/photos/location/{photo_id}` routes serve individual stored images with
their image content type, five-minute caching, and ETag revalidation. Deploy the
updated backend to enable these URLs. When running behind a reverse proxy,
preserve the external Host and configure trusted forwarded HTTPS headers so the
returned URLs use the same public API origin as the app.

### Offline mode

Users turn offline mode on from **Profile → Offline Map → Download**. The
download stores three things under the app's support directory:

- `bundle.json` — every building, room, and the whole routing graph
  (`route_node`, `pathway`, `pathway_allowed_mode`, `path_point`).
- `photos/` — the cover photo of each building and room.
- `tiles/` — the OpenStreetMap tiles covering the campus bounds at zooms 15-19
  (1,126 tiles, roughly 20 MB).

With the pack in place the map draws from disk, search runs against the stored
buildings, and directions are computed on the device by
`lib/features/offline/services/offline_routing_engine.dart`, a Dart port of
`server/app/utils/routing.py`. Both produce identical routes; a parity fixture
in `test/features/offline/offline_routing_engine_test.dart` fails if they drift.
A change to one needs the matching change in the other.

The app still prefers the live backend whenever it answers. The stored pack is
used only when a request never reaches the server (a timeout or a failed
socket); a real HTTP error is always reported as the backend sent it.

Two backend routes support this:

- `GET /campus/offline/bundle` — the whole dataset, with an `ETag` so an
  unchanged bundle revalidates as `304` instead of downloading again.
- `GET /campus/offline/manifest` — the version and what a download would cost,
  without the payload, for cheap update checks.

The version is a content hash of the dataset with photo hosts normalised away,
so moving between `localhost`, `10.0.2.2`, and `api.kumpas.live` does not look
like a new version.

**Updates are never installed automatically.** When the backend publishes a
newer version the app records it and shows a notice — a banner on the map, a
badge on the Offline Map row, and an update card on the offline screen. The
stored map keeps working untouched until the user taps *Download update*. A
download can be paused and resumed; finished files are kept and skipped on the
next run.

Downloading tiles in bulk is subject to the
[OpenStreetMap tile usage policy](https://operations.osmfoundation.org/policies/tiles/).
The download is capped to the campus bounds, runs four requests at a time, and
identifies itself with `campusDownloadUserAgent`. For wider deployment, point
`campusTileUrlTemplate` at your own tile server or a commercial provider.

Offline mode needs a writable app directory, so it is offered on Android, iOS,
Windows, macOS, and Linux. On the web build the screen reports it as available
only in the installed app.
