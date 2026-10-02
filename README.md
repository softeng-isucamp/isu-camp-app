## User App repository for ISU-CAMP

### Local Android emulator development

Start the repository backend in a separate PowerShell terminal (requires the
server virtual environment and configured `server/.env`):

```powershell
cd server
.\venv\Scripts\python.exe -m uvicorn app.main:app --host 127.0.0.1 --port 8000
```

If the backend is already running on port 8000, reuse it. From the repository
root, launch the app against that backend:

```powershell
flutter run -d emulator-5554 --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

`10.0.2.2` connects the Android emulator to the host PC. HTTP is enabled only in
the Android debug manifest. Keep the backend running while testing. Changing
`API_BASE_URL` requires restarting the Flutter run, not just hot reload.

Without the override, Android uses `http://10.0.2.2:8000`; web and desktop use
`http://localhost:8000`. For local browser development, select
`Chrome - local backend` in VS Code or run `flutter run -d chrome`.
To use the deployed backend, select `App - live backend` in VS Code or pass
`--dart-define=API_BASE_URL=https://api.kumpas.live`. The deployed API
currently requires a CAPTCHA token that this checkout does not generate. Local
development uses the matching repository backend; production login still needs
the deployed backend and CAPTCHA integration to be aligned.
