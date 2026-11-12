import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../api/dto.dart';
import '../auth/token_storage.dart';
import '../config.dart';

/// Parses Server-Sent-Events text into (event, data) pairs. Implements the
/// spec subset the backend uses: `event:` and `data:` fields, a blank line
/// terminates the event, and `:`-prefixed lines are comments (the 25 s
/// keepalives) which are ignored. Multi-line `data:` fields join with `\n`.
class SseParser {
  SseParser({required this.onEvent});

  /// Called once per complete event, when its terminating blank line arrives.
  final void Function(String event, String data) onEvent;

  String? _event;
  final List<String> _data = [];

  void addLine(String line) {
    if (line.startsWith(':')) return; // keepalive / comment

    if (line.isEmpty) {
      if (_event == null && _data.isEmpty) return; // stray blank line
      onEvent(_event ?? 'message', _data.join('\n'));
      _event = null;
      _data.clear();
      return;
    }

    if (line.startsWith('event:')) {
      _event = _fieldValue(line, 'event:'.length);
    } else if (line.startsWith('data:')) {
      _data.add(_fieldValue(line, 'data:'.length));
    }
    // Other fields (id:, retry:) are not used by the backend; ignored.
  }

  /// Strips the field name and one optional leading space, per the SSE spec.
  static String _fieldValue(String line, int prefixLength) {
    var value = line.substring(prefixLength);
    if (value.startsWith(' ')) value = value.substring(1);
    return value;
  }
}

/// Maintains the `GET /events` Server-Sent-Events stream while the user is
/// authenticated, per the contract's realtime conventions:
///
/// - Named events: `connected`, `message` (ChatMessageResponse),
///   `notification` (NotificationResponse).
/// - Connections are capped at 30 minutes server-side, so the stream ends
///   periodically: reconnect with exponential backoff and re-sync state from
///   the REST endpoints (SSE is best-effort, not a replay log).
/// - The bearer token is re-read from storage on every (re)connect, because
///   silent refresh rotates access tokens while the service is idle.
///
/// Delivery is fire-and-forget: consumers register [onMessage] /
/// [onNotification] callbacks. Only the message RECEIVER receives `message`
/// events (the backend publishes to the receiver only), so a consumer can
/// treat any `message` event as "from my partner".
class RealtimeService {
  /// [_dioOverride] exists for tests — production builds construct the Dio
  /// internally from [baseUrl].
  RealtimeService({required this._storage, String? baseUrl, Dio? dioOverride})
      : _dio = dioOverride ??
            Dio(
              BaseOptions(
                baseUrl: baseUrl ?? kBaseUrl,
                connectTimeout: const Duration(seconds: 10),
                // A live SSE stream has no meaningful receive deadline:
                // heartbeats arrive every 25 s and the server closes after
                // 30 min anyway.
                receiveTimeout: null,
              ),
            ) {
    _dio.options.headers['Accept'] = 'text/event-stream';
  }

  final TokenStorage _storage;
  final Dio _dio;

  late final SseParser _parser = SseParser(onEvent: _handleEvent);

  /// Fires for every `message` SSE event (the partner sent a chat message).
  void Function(ChatMessage message)? onMessage;

  /// Fires for every `notification` SSE event. Deduplicate by `id` — the same
  /// notification can also arrive via FCM push.
  void Function(AppNotification notification)? onNotification;

  bool _wantConnected = false;
  bool _opening = false;
  int _backoffSeconds = 1;
  Timer? _reconnectTimer;
  CancelToken? _cancelToken;
  StreamSubscription<String>? _subscription;

  /// Opens the stream (no-op when already connecting/connected). Safe to call
  /// repeatedly — e.g. from an auth-state listener.
  Future<void> connect() async {
    if (_wantConnected || _opening) return;
    _wantConnected = true;
    await _open();
  }

  /// Closes the stream and stops reconnecting. Safe to call repeatedly.
  void disconnect() {
    _wantConnected = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _cancelToken?.cancel();
    _cancelToken = null;
    _subscription?.cancel();
    _subscription = null;
    _opening = false;
    _backoffSeconds = 1;
  }

  Future<void> _open() async {
    if (!_wantConnected || _opening) return;
    _opening = true;

    // Always read the freshest token: silent refresh may have rotated the
    // pair since the last attempt.
    final token = await _storage.readAccessToken();
    if (!_wantConnected || token == null || token.isEmpty) {
      _opening = false;
      return;
    }

    try {
      _cancelToken = CancelToken();
      final res = await _dio.get<ResponseBody>(
        '/events',
        // SSE never ends, so the response MUST be streamed: with the default
        // json/text response type Dio waits for the whole body (an EOF that
        // never arrives) and the connect future would hang forever.
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
          responseType: ResponseType.stream,
        ),
        cancelToken: _cancelToken,
      );
      _opening = false;
      _backoffSeconds = 1;
      _subscription = utf8.decoder
          .bind(res.data!.stream)
          .transform(const LineSplitter())
          .listen(
            _parser.addLine,
            onDone: _handleStreamClosed,
            onError: (_) => _handleStreamClosed(),
            cancelOnError: true,
          );
    } on DioException catch (e) {
      _opening = false;
      if (e.type == DioExceptionType.cancel) return; // deliberate disconnect()
      _scheduleReconnect();
    } catch (_) {
      _opening = false;
      _scheduleReconnect();
    }
  }

  void _handleStreamClosed() {
    _subscription = null;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (!_wantConnected) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: _backoffSeconds), () {
      // Exponential backoff, capped at 30 s.
      _backoffSeconds = (_backoffSeconds * 2).clamp(1, 30);
      _open();
    });
  }

  void _handleEvent(String event, String data) {
    if (data.isEmpty) return;
    switch (event) {
      case 'message':
        try {
          onMessage?.call(
            ChatMessage.fromJson(jsonDecode(data) as Map<String, dynamic>),
          );
        } catch (_) {
          // Malformed payload — SSE is best-effort; never crash on it.
        }
      case 'notification':
        try {
          onNotification?.call(
            AppNotification.fromJson(jsonDecode(data) as Map<String, dynamic>),
          );
        } catch (_) {}
      case 'connected':
      default:
        // `connected` confirms the stream; unknown events are ignored so the
        // backend can add event types without breaking this client.
        break;
    }
  }
}
