# RecoverTogether mobile (Flutter)

The mobile client for the RecoverTogether recovery-support platform. It builds
against the API contract frozen in `../backend/docs/api-contract.md` — that
document is the source of truth for endpoints, payloads, and semantics.

## Run

```sh
flutter pub get
flutter run
```

The backend base URL defaults to `http://10.0.2.2:8080` (Android-emulator alias
for the host's loopback, where the dev backend listens). Override per run:

```sh
flutter run --dart-define=BASE_URL=http://<host-lan-ip>:8080
```

## Layout

- `lib/api/` — Dio clients. `api_client.dart` splits public vs. authenticated
  endpoints and implements the contract's silent refresh (on 401: refresh once,
  replay once; failed refresh drops the session).
- `lib/auth/` — token storage (Keystore-backed) and the session controller.
- `lib/screens/` — login, register, home.

Auth is increment one; dashboard, check-ins, chat and push arrive next.
