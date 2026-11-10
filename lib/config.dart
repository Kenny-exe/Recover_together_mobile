/// Backend base URL used by the API clients.
///
/// Defaults to the Android-emulator alias for the host machine's loopback
/// (10.0.2.2) — the dev backend listens on localhost:8080. Override per run
/// without code changes:
///
///   flutter run --dart-define=BASE_URL=http://192.168.1.20:8080
///
/// A physical device needs the host's LAN IP on the same Wi-Fi; a production
/// build ships its own value.
const String kBaseUrl = String.fromEnvironment(
  'BASE_URL',
  defaultValue: 'http://10.0.2.2:8080',
);
