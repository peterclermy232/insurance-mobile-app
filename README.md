# Crop Insurance Field

Offline-first Flutter app for crop-insurance field officers (Ministry of
Agriculture crop insurance programme, Kenya). Agents register farmers and
farms, prepare quotations and report claims; assessors run field inspections
and report claims; managers can do everything. Every record is saved on the
device first and synced later, so the app works with no connectivity.

Requires Flutter 3.22 (Dart 3.4).

## Running

```sh
flutter pub get
flutter run
```

### Choosing the server

The API base URL is set at build time with `--dart-define=API_BASE_URL=...`.
The default is the Render deployment:
`https://crop-insurance-api-46ql.onrender.com/api/v1`.

Local Django server (`python manage.py runserver 8000`):

| Where the app runs | Command |
|---|---|
| Android emulator | `flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1` |
| iOS simulator / desktop | `flutter run --dart-define=API_BASE_URL=http://localhost:8000/api/v1` |
| Physical phone on the same Wi-Fi | `flutter run --dart-define=API_BASE_URL=http://<your-computer-LAN-IP>:8000/api/v1` (start Django with `runserver 0.0.0.0:8000`) |

Debug Android builds allow plain `http://` (see
`android/app/src/debug/AndroidManifest.xml`); release builds need HTTPS.

The Render free tier sleeps when idle and takes about 50 seconds to wake up.
Sync and login use long timeouts (up to 90 s) and the app shows
"Waking up the server..." while it waits.

## Architecture

```
lib/
  main.dart, app.dart          wiring (provider) and the sign-in gate
  core/
    config/                    AppConfig (base URL, timeouts, allowed roles)
    db/                        SQLite schema (AppDatabase), sync_meta store, repository base
    network/                   ApiClient (Dio, token refresh), connectivity, errors
    auth/                      AuthController, TokenStore (flutter_secure_storage), UserSession
    sync/                      SyncEngine, entity mappers, SyncController (triggers + UI state)
    location/, media/          GPS capture, photo capture + upload queue
    theme/, widgets/, utils/   Material 3 theme, shared widgets, formatters, logger
  features/<feature>/{data,models,screens,widgets}
    auth, home, farmers, farms, quotations, claims, inspections, sync
```

State management is `provider`: `AuthController`, `SyncController`,
`ConnectivityService` and `DataChanges` (bumped after every local write and
every sync so lists reload) are `ChangeNotifier`s; repositories are plain
providers.

## Offline sync

The backend contract is in [docs/SYNC_API.md](docs/SYNC_API.md).

- Every syncable row has a `client_uuid` (UUID v4), `server_id`,
  `sync_status` (`pending` / `synced` / `error` / `pending_parent`),
  `sync_error` and `updated_at`.
- A sync sends only pending rows to `POST /sync/`, parents first. A child
  references its parent by `<parent>_uuid` until the parent has a server id,
  then by `<parent>: id`.
- The whole response (per-item results, `updates`, `reference`, then
  `last_sync = server_time`) is applied in one SQLite transaction. If anything
  fails nothing is applied, so local data is never lost and re-sending is safe.
- Results: `created`/`updated` store the server id and server copy;
  `duplicate` links the farmer to the existing one and tells the officer;
  `locked` takes the office copy; `pending_parent` stays queued; `error`
  shows the server's messages on the record until the officer fixes it.
- Edits made while a sync is in flight stay pending for the next sync.
- Photos are queued in the `media` table and uploaded to `POST /upload/` once
  the owning record has a server id (HTTP 409 `pending_parent` = retry later).
- Triggers: "Sync now", connectivity coming back, app start (when online) and
  after login (full download). Concurrent requests join the running sync.

Officers who have signed in before can open the app and capture data offline
even when their tokens have expired. When a sync needs a new session the app
shows "Sign in again to sync" instead of locking the officer out. Signing out
warns about unsynced records and keeps them on the device.

## Tests

```sh
flutter analyze
flutter test
```

`test/sync_engine_test.dart` covers the engine with an SQLite FFI database
and a fake transport; `test/api_client_test.dart` covers token refresh and
the auth rules; `test/database_test.dart` covers schema creation/upgrade.

`test/integration/live_backend_test.dart` runs a full offline field visit
against a real server and is skipped unless `LIVE_API_BASE_URL` is set:

```sh
# in the Django project (local SQLite only)
DATABASE_URL= DEBUG=True bin/python manage.py seed_test_users --password 'Local@Test1'
DATABASE_URL= DEBUG=True bin/python manage.py runserver 8001

# in this project
LIVE_API_BASE_URL=http://localhost:8001/api/v1 flutter test test/integration
```

It expects an ACTIVE product named "IT Maize Cover", an office farmer with a
WRITTEN policy `POL-IT-1`, and a farmer with ID number `99000002` in the
DEFAULT organisation.
