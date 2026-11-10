import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'package:app/auth/token_storage.dart';

/// Immutable snapshot of a request at adapter time — the live RequestOptions
/// keeps being mutated by interceptors after dispatch, so assertions must
/// record what was actually sent.
class RequestRecord {
  RequestRecord(RequestOptions options)
      : method = options.method,
        path = options.path,
        headers = Map<String, dynamic>.of(options.headers),
        data = options.data;

  final String method;
  final String path;
  final Map<String, dynamic> headers;
  final Object? data;
}

/// Records every request and answers from a scripted handler — enough to
/// exercise the API layer without a live backend.
class MockAdapter implements HttpClientAdapter {
  MockAdapter(this.handler);

  final List<RequestRecord> requests = [];
  Future<ResponseBody> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(RequestRecord(options));
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

/// JSON response body with the given status code.
ResponseBody jsonBody(Object? json, int status) => ResponseBody.fromString(
      jsonEncode(json),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

/// In-memory [TokenStorage] for tests.
class InMemoryTokenStorage implements TokenStorage {
  String? accessToken;
  String? refreshToken;

  @override
  Future<void> save({String? accessToken, String? refreshToken}) async {
    if (accessToken != null) this.accessToken = accessToken;
    if (refreshToken != null) this.refreshToken = refreshToken;
  }

  @override
  Future<String?> readAccessToken() async => accessToken;

  @override
  Future<String?> readRefreshToken() async => refreshToken;

  @override
  Future<void> clear() async {
    accessToken = null;
    refreshToken = null;
  }
}
