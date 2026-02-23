# FHIRant Mobile App — Implementation Plan & Status

## Context

FHIRant is a fully-featured FHIR R4 server running as a CLI Dart process. The goal is to wrap it in a Flutter app so it runs on a phone — a FHIR server in your pocket. **Android** gets a foreground service (server survives backgrounding). **iOS** runs while the app is in the foreground.

The good news: `fhirant_server`, `fhirant_db`, and `fhirant_logging` are already pure Dart with no Flutter deps. `dart:io` (including `shelf_io.serve()`) works on Flutter mobile. The work is: (1) small surgical changes to existing packages for mobile compatibility, (2) a new Flutter app package with dashboard UI and Android foreground service.

---

## Implementation Status

| Step | Description | Status |
|------|-------------|--------|
| 1 | Modify FhirAntServer — request log stream + configurable rate limiter | DONE |
| 2 | Make FhirantLogging file path configurable | DONE |
| 3 | Fix favicon handler for mobile | DONE |
| 4 | Create Flutter app package skeleton | DONE |
| 5 | Database service for mobile | DONE |
| 6 | Server service wrapper | DONE |
| 7 | Server state (ChangeNotifier) | DONE |
| 8 | Android foreground service config | DONE |
| 9 | iOS permissions config | DONE |
| 10 | Dashboard UI (4 Material 3 cards) | DONE |
| 11 | main.dart wiring | DONE |
| 12 | Verify existing tests still pass | DONE (291 server + 108 db) |
| 13 | flutter analyze passes | DONE (0 issues) |
| — | Build APK and test on device | **NOT DONE** |
| — | Build iOS and test on device/simulator | **NOT DONE** |

---

## What Was Changed in Existing Packages

### `packages/fhirant_server/lib/src/fhirant_server.dart`
- Added `RequestLogEntry` data class (timestamp, method, path, statusCode, durationMs, clientIp)
- Added `StreamController<RequestLogEntry>.broadcast()` field + `Stream<RequestLogEntry> get requestLog`
- In `_logRequestsMiddleware()`, emits entries to the stream after every request (in addition to existing `print()`)
- Stream controller closed in `stop()`
- Added constructor params `maxRequests` (default 10) and `rateLimitDuration` (default `Duration(seconds: 60)`), wired into `createHandler()` instead of hardcoded values
- All changes are backwards-compatible — existing callers using defaults are unaffected

### `packages/fhirant_server/lib/fhirant_server.dart` (barrel)
- Added `export 'src/fhirant_server.dart';` so the app can import `FhirAntServer` and `RequestLogEntry`

### `packages/fhirant_logging/lib/fhirant_logging.dart`
- `initialize()` now takes optional named param `{String? logFilePath = 'server_logs.json'}`
- Stored in `_logFilePath` field
- `_writeToFile()` is a no-op when `_logFilePath == null`
- Default behavior unchanged for CLI — the default value is `'server_logs.json'` so existing call sites work identically

### `packages/fhirant_server/lib/src/handlers/favico_handler.dart`
- Changed `catch` to return `Response.notFound('Favicon not found')` instead of `Response.internalServerError(body: 'Error serving favicon: $e')` — favicon is non-critical and the file won't exist on mobile

---

## What Was Created: Flutter App (`packages/fhirant/`)

### Package name: `fhirant`
### Org: `dev.fhirfli` (matches existing monorepo convention)

### File Structure
```
packages/fhirant/
├── android/
│   └── app/src/main/AndroidManifest.xml  (permissions + foreground service)
├── ios/
│   └── Runner/Info.plist                  (local network permission)
├── lib/
│   ├── main.dart                          # App entry point
│   └── src/
│       ├── services/
│       │   ├── database_service.dart      # SQLCipher + path_provider + secure key
│       │   └── server_service.dart        # FhirAntServer lifecycle wrapper
│       ├── state/
│       │   └── server_state.dart          # ChangeNotifier for UI
│       ├── screens/
│       │   └── dashboard_screen.dart      # Single scrollable screen
│       └── widgets/
│           ├── server_control_card.dart   # Start/stop + status
│           ├── network_info_card.dart     # IP + port + QR code
│           ├── resource_counts_card.dart  # Resource type counts
│           └── request_log_card.dart      # Live scrolling log
├── pubspec.yaml
└── analysis_options.yaml
```

### Dependencies
- `fhir_r4`, `fhirant_server`, `fhirant_db`, `fhirant_logging` (path deps)
- `drift: ^2.29.0`, `sqlite3: ^2.4.6`, `sqlcipher_flutter_libs: ^0.6.4`
- `path_provider: ^2.1.5`, `flutter_secure_storage: ^9.2.4`
- `network_info_plus: ^6.1.1`, `provider: ^6.1.2`
- `qr_flutter: ^4.1.0`, `flutter_foreground_task: ^8.13.4`
- Same `dependency_overrides` for fhir_r4/path/mapping/validation as other packages

### How Each File Works

**`lib/main.dart`:**
1. `WidgetsFlutterBinding.ensureInitialized()`
2. Initializes `FhirantLogging` with log file in app documents dir (or `null` to skip)
3. Initializes `FlutterForegroundTask` on Android (low-importance notification, wake lock, wifi lock)
4. Creates `DatabaseService` and calls `initialize()` (sets up SQLCipher + encrypted DB)
5. Creates `ServerService` wrapping the DB service
6. Runs app with `ChangeNotifierProvider<ServerState>`
7. `FhirantApp` widget observes lifecycle — on iOS, stops server when app goes to background

**`lib/src/services/database_service.dart`:**
- On Android: calls `open.overrideFor(OperatingSystem.android, openCipherOnAndroid)` for SQLCipher native lib
- Gets/generates encryption key via `flutter_secure_storage` (persisted in OS Keychain/Keystore)
- Creates DB file at `<app_docs>/fhirant_data/fhirant.db`
- Creates `NativeDatabase` with PRAGMA key encryption setup
- Creates `FhirAntDb(executor)` and calls `initialize()`
- Also provides `getExportDir()` for bulk data export files

**`lib/src/services/server_service.dart`:**
- `start(port)` — gets/generates JWT secret from secure storage, gets export dir, creates `FhirAntServer` with 100 req/60s rate limit, calls `startHttp(port)`
- `stop()` — calls server stop, nulls out the reference
- Exposes `isRunning`, `port`, `requestLog` stream

**`lib/src/state/server_state.dart`:**
- `ServerStatus` enum: stopped, starting, running, stopping, error
- Holds last ~200 `RequestLogEntry` items in a `Queue` (circular buffer)
- `startServer()`: starts server, subscribes to request log stream, starts 10s periodic resource count refresh, starts Android foreground task, detects WiFi IP
- `stopServer()`: stops Android foreground task, cancels timers/subscriptions, stops server
- `_refreshResourceCounts()`: calls `db.getResourceTypes()` + `db.getResourceCount()` per type
- `_detectWifiIp()`: tries `NetworkInfo().getWifiIP()`, falls back to `NetworkInterface.list()` for non-loopback IPv4
- Exposes `serverUrl` as `http://<ip>:<port>` when running

**`lib/src/widgets/server_control_card.dart`:**
- Color-coded status badge (green=running, orange=starting/stopping, red=error, grey=stopped)
- Editable port field (only when stopped)
- Start/Stop button
- Error message display

**`lib/src/widgets/network_info_card.dart`:**
- Shows server URL as selectable monospace text
- Copy-to-clipboard button
- QR code of the server URL (180px, via `qr_flutter`)
- Shows "unable to detect WiFi" warning if IP detection fails

**`lib/src/widgets/resource_counts_card.dart`:**
- Lists resource types sorted by count (descending)
- Shows total count in header
- Updates every 10s via ServerState

**`lib/src/widgets/request_log_card.dart`:**
- Scrollable list (300px height) of recent requests, newest on top
- Each entry: timestamp, color-coded method badge, path, color-coded status code, duration in ms
- Color coding: GET=blue, POST=green, PUT=orange, PATCH=purple, DELETE=red; 2xx=green, 3xx=blue, 4xx=orange, 5xx=red

### Android Configuration (`AndroidManifest.xml`)
- Permissions: `INTERNET`, `ACCESS_WIFI_STATE`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_CONNECTED_DEVICE`
- App label: `FHIRant`
- Foreground service declaration: `com.pravera.flutter_foreground_task.service.ForegroundService` with `foregroundServiceType="connectedDevice"`

### iOS Configuration (`Info.plist`)
- `CFBundleDisplayName`: `FHIRant`
- `NSLocalNetworkUsageDescription`: explains that FHIRant runs a local FHIR server
- Server auto-stops when app goes to background (handled in `_FhirantAppState.didChangeAppLifecycleState`)

---

## What's Still Left To Do

### 1. Build and Test on Android Device
```bash
cd packages/fhirant
flutter build apk --debug
# Install APK on device
# Start server
# From laptop: curl http://<phone-ip>:8080/metadata
# Background the app — server should remain reachable via foreground service
# Create resources via curl, verify dashboard counts update
# Scan QR code from another device
```

### 2. Build and Test on iOS Device/Simulator
```bash
cd packages/fhirant
flutter build ios --debug
# Run on device/simulator
# Start server, test from laptop
# Background the app — server should stop (iOS limitation, by design)
```

### 3. Potential Issues to Watch For
- **SQLCipher on iOS**: May need `sqlcipher_flutter_libs` to be configured in the Podfile. If the build fails on iOS, check `ios/Podfile` for SQLCipher pod inclusion.
- **Network permissions on Android 12+**: `ACCESS_WIFI_STATE` should suffice, but if WiFi IP comes back null on newer Android, may need `ACCESS_FINE_LOCATION` with runtime permission request.
- **Foreground service on Android 14+**: Android 14 requires user consent for foreground services. `flutter_foreground_task` should handle this, but verify the notification appears and the service stays alive.
- **Large DB on mobile**: If the DB grows large, the 10s resource count refresh could cause UI jank. Consider making it less frequent or running in a compute isolate if this becomes an issue.

### 4. Not Yet Committed
All changes are uncommitted. When ready:
```bash
cd /home/grey/dev/fhir/fhirant
git add packages/fhirant_server/lib/src/fhirant_server.dart \
        packages/fhirant_server/lib/fhirant_server.dart \
        packages/fhirant_server/lib/src/handlers/favico_handler.dart \
        packages/fhirant_logging/lib/fhirant_logging.dart \
        packages/fhirant/ \
        MOBILE_APP_PLAN.md
git commit -m "Add Flutter mobile app — FHIR server in your pocket"
```

---

## Test Results (as of implementation)
- `dart analyze packages/fhirant_server` — 0 new warnings (1 pre-existing info about unnecessary_import)
- `dart test packages/fhirant_server` — **291 tests pass**
- `dart test packages/fhirant_db` — **108 tests pass**
- `flutter analyze packages/fhirant` — **No issues found**
