## User App repository for ISU-CAMP

### API backend

The app uses a local API by default. To run against
the repository backend on your own machine, start it in a separate PowerShell
terminal (requires the server virtual environment and configured `server/.env`):

```powershell
cd server
.\venv\Scripts\python.exe -m uvicorn app.main:app --host 0.0.0.0 --port 8000
```

From the repository root, use the address for your target device:

```powershell
# Web or desktop, backend on this machine
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000

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
`Chrome - local backend` in VS Code or run `flutter run -d chrome`.
To use the deployed backend, select `App - live backend` in VS Code or pass
`--dart-define=API_BASE_URL=https://api.kumpas.live`. The deployed API
currently requires a CAPTCHA token that this checkout does not generate. Local
development uses the matching repository backend; production login still needs
the deployed backend and CAPTCHA integration to be aligned.
