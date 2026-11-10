import 'package:dio/dio.dart';

/// Response of POST /auth/login and POST /auth/refresh (contract:
/// `LoginResponse`). `tokenType` is always "Bearer"; treat both tokens as
/// opaque strings.
class LoginResponse {
  LoginResponse({
    required this.token,
    required this.refreshToken,
    required this.tokenType,
  });

  factory LoginResponse.fromJson(Map<String, dynamic> json) => LoginResponse(
        token: json['token'] as String,
        refreshToken: json['refreshToken'] as String? ?? '',
        tokenType: json['tokenType'] as String? ?? 'Bearer',
      );

  final String token;
  final String refreshToken;
  final String tokenType;
}

/// GET /users/me, register and profile-update responses (contract:
/// `UserResponse`). Never carries secrets.
class UserResponse {
  UserResponse({
    required this.id,
    required this.name,
    required this.email,
    required this.timezone,
    this.createdAt,
  });

  factory UserResponse.fromJson(Map<String, dynamic> json) => UserResponse(
        id: json['id'] as int,
        name: json['name'] as String? ?? '',
        email: json['email'] as String? ?? '',
        timezone: json['timezone'] as String? ?? 'UTC',
        createdAt: json['createdAt'] as String?,
      );

  final int id;
  final String name;
  final String email;
  final String timezone;
  final String? createdAt;
}

/// The contract's error envelope: `{timestamp, status, message}`. Every error
/// body from the backend has this shape; [message] is safe to show to the user.
class ApiException implements Exception {
  ApiException({this.status, required this.message});

  factory ApiException.fromDio(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['message'] is String) {
      return ApiException(
        status: e.response?.statusCode,
        message: data['message'] as String,
      );
    }
    switch (e.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return ApiException(
          message: 'Cannot reach the server. Check your connection.',
        );
      default:
        return ApiException(
          status: e.response?.statusCode,
          message: 'Something went wrong. Please try again.',
        );
    }
  }

  final int? status;
  final String message;

  @override
  String toString() => message;
}

/// Check-in status per the contract enum (`SUCCESS | RELAPSE | STRUGGLING |
/// STRONG_URGE | NEED_SUPPORT`). Carries the exact wire string and a
/// human-facing label.
enum CheckInStatus {
  success('SUCCESS', 'Stayed clean'),
  relapse('RELAPSE', 'Relapsed'),
  struggling('STRUGGLING', 'Struggling'),
  strongUrge('STRONG_URGE', 'Strong urge'),
  needSupport('NEED_SUPPORT', 'Need support');

  const CheckInStatus(this.wire, this.label);

  /// The exact string the backend contract uses for this status.
  final String wire;

  /// Human-facing label used across the app.
  final String label;

  static CheckInStatus fromWire(String value) => CheckInStatus.values
      .firstWhere(
        (s) => s.wire == value,
        orElse: () => throw ArgumentError('Unknown check-in status: $value'),
      );
}

/// One daily check-in (contract: `CheckInResponse`).
class CheckIn {
  CheckIn({
    this.id,
    required this.date,
    this.status,
    this.note,
    this.createdAt,
  });

  factory CheckIn.fromJson(Map<String, dynamic> json) => CheckIn(
        id: json['id'] as int?,
        date: json['date'] as String? ?? '',
        status: json['status'] == null
            ? null
            : CheckInStatus.fromWire(json['status'] as String),
        note: json['note'] as String?,
        createdAt: json['createdAt'] as String?,
      );

  final int? id;

  /// The user-local day this check-in belongs to, `yyyy-MM-dd`.
  final String date;
  final CheckInStatus? status;
  final String? note;
  final String? createdAt;

  /// True when submitted today on the device's clock. The device clock tracks
  /// the user's IANA timezone in practice; the server's local-day rules do the
  /// authoritative assignment, this is only for UI state.
  bool get isToday {
    final now = DateTime.now();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return date == '${now.year}-$month-$day';
  }
}

/// GET /dashboard (contract: `DashboardResponse`). Partner fields are null
/// when no partner is connected; other fields default to zero when omitted.
class Dashboard {
  Dashboard({
    required this.currentStreak,
    required this.bestStreak,
    required this.totalCheckIns,
    required this.successCount,
    required this.relapseCount,
    required this.successRate,
    required this.unreadMessages,
    required this.achievementCount,
    this.partnerName,
    this.partnerCurrentStreak,
    this.partnerBestStreak,
    this.partnerLastSeen,
    this.partnerCheckedInToday,
    this.daysSinceLastCheckIn,
  });

  factory Dashboard.fromJson(Map<String, dynamic> json) => Dashboard(
        currentStreak: json['currentStreak'] as int? ?? 0,
        bestStreak: json['bestStreak'] as int? ?? 0,
        totalCheckIns: json['totalCheckIns'] as int? ?? 0,
        successCount: json['successCount'] as int? ?? 0,
        relapseCount: json['relapseCount'] as int? ?? 0,
        successRate: (json['successRate'] as num?)?.toDouble() ?? 0,
        unreadMessages: json['unreadMessages'] as int? ?? 0,
        achievementCount: json['achievementCount'] as int? ?? 0,
        partnerName: json['partnerName'] as String?,
        partnerCurrentStreak: json['partnerCurrentStreak'] as int?,
        partnerBestStreak: json['partnerBestStreak'] as int?,
        partnerLastSeen: json['partnerLastSeen'] as String?,
        partnerCheckedInToday: json['partnerCheckedInToday'] as bool?,
        daysSinceLastCheckIn: json['daysSinceLastCheckIn'] as int?,
      );

  final int currentStreak;
  final int bestStreak;
  final int totalCheckIns;
  final int successCount;
  final int relapseCount;

  /// Percentage 0..100 (the backend already multiplies by 100).
  final double successRate;
  final int unreadMessages;
  final int achievementCount;
  final String? partnerName;
  final int? partnerCurrentStreak;
  final int? partnerBestStreak;
  final String? partnerLastSeen;
  final bool? partnerCheckedInToday;
  final int? daysSinceLastCheckIn;

  bool get hasPartner => partnerName != null;
}
