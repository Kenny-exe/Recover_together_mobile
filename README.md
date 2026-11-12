# RecoverTogether mobile (Flutter)

The mobile client for the RecoverTogether recovery-support platform. It builds
strictly against the API contract frozen in `../backend/docs/api-contract.md` —
that document is the source of truth for endpoints, payloads, and semantics.

## Features

| Area | What the app does |
| --- | --- |
| Auth | Register, log in, silent token refresh (one refresh + one replay per 401, session dropped when the refresh fails), logout |
| Dashboard | Streaks, success rate, totals, unread messages, achievements, partner status (measured on the partner's local clock) |
| Daily check-in | One check-in per user-local day with status + optional note; duplicate-day submissions surface the backend's 400 message |
| Partner connection | Exact-email search, send/accept/reject requests, unpair |
| Chat | Partner-only conversation with cursor pagination (`beforeId` exclusive), live messages via SSE, send → server re-sync |
| Notifications | Inbox with newest-first cursor pages, mark read/all-read, swipe-delete, live SSE arrivals deduplicated by id |
| Preferences | Global push switch, quiet hours (validated client-side to match the backend's 400s), per-type toggles — SOS alerts always on |
| Profile & settings | Edit name/email/timezone, change password (signs out everywhere), self-service account deletion with password confirmation |
| Devices | Registered push devices with masked token previews and removal |
| Realtime | `GET /events` SSE stream: exponential backoff 1→30 s, bearer re-read on every reconnect, open only while the app is foregrounded (FCM covers background) |

## Prerequisites

- Flutter 3.38+ / Dart 3.13+ (`flutter --version`)
- Android SDK (the first build bootstraps missing SDK components)
- A running RecoverTogether backend — see `../backend/README.md` for the
  dev setup (PostgreSQL + `JWT_SECRET`, then `./mvnw spring-boot:run`).

## Run

```sh
flutter pub get
flutter run
```

The backend base URL defaults to `http://10.0.2.2:8080` — the Android-emulator
alias for the host's loopback, where the dev backend listens. Override per run:

```sh
# Real device on the same Wi-Fi as the backend host:
flutter run --dart-define=BASE_URL=http://<host-lan-ip>:8080
```

Networking notes:

- Debug builds allow cleartext HTTP (`usesCleartextTraffic` is set in the
  debug manifest only), so the `http://` dev flows work. Release builds keep
  Android's secure default — a release `BASE_URL` must be `https://`.
- The `INTERNET` permission is declared in the main manifest.

## Tests, analysis, build

```sh
flutter analyze          # 0 issues expected
flutter test             # full widget + unit suite
flutter build apk --debug
```

The test suite exercises the API layer against a scripted Dio adapter
(`test/support/mock_adapter.dart`) — contract shapes, error envelopes, silent
refresh, SSE parsing — plus the screens as widgets.

On Windows, a stale Gradle daemon can lock `build/app/intermediates/.../mergeDebugAssets`.
If a rebuild fails with "Unable to delete directory": stop stray `java.exe`
processes (Android Studio JBR daemons), delete `build/`, rebuild.

## Layout

- `lib/api/` — Dio clients per contract area (`checkin`, `partner`, `message`,
  `user`, `notification`, `device`) plus `api_client.dart`, which splits
  public vs. authenticated endpoints and implements the silent refresh.
- `lib/auth/` — Keystore-backed token storage and the session controller.
- `lib/realtime/` — SSE parser + reconnecting `RealtimeService`, and the
  app-lifecycle wiring that opens the stream only while foregrounded.
- `lib/push/` — `DeviceRegistrar` (registers the FCM token on login) and the
  pluggable `PushTokenSource`. Push delivery is log-only until
  `firebase_messaging` and Firebase project configuration are added; the
  backend-side gate is its own (`fcm.credentials-path`).
- `lib/screens/` — login, home (dashboard + check-in), partner, chat,
  notifications, notification preferences, devices, settings.

## Push status

Device registration and the devices screen are live; FCM delivery needs:

1. a Firebase project with `google-services.json` dropped into
   `android/app/`,
2. `firebase_core` + `firebase_messaging` dependencies and a
   `PushTokenSource` implementation that surfaces the FCM token,
3. the backend configured with a service-account JSON (`fcm.credentials-path`).

Until then the registrar stays inert and pushes are server-side log-only.
