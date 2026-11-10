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

/// Partner connection status per the contract enum.
enum PartnerRequestStatus {
  pending('PENDING'),
  accepted('ACCEPTED'),
  rejected('REJECTED');

  const PartnerRequestStatus(this.wire);

  /// The exact string the backend contract uses for this status.
  final String wire;

  static PartnerRequestStatus fromWire(String value) =>
      PartnerRequestStatus.values.firstWhere(
        (s) => s.wire == value,
        orElse: () =>
            throw ArgumentError('Unknown partner request status: $value'),
      );
}

/// The connected partner (contract: `PartnerResponse`). Null results from
/// `GET /partner/current` mean the user has no partner yet.
class Partner {
  Partner({this.id, required this.name, required this.email});

  factory Partner.fromJson(Map<String, dynamic> json) => Partner(
        id: json['id'] as int?,
        name: json['name'] as String? ?? '',
        email: json['email'] as String? ?? '',
      );

  final int? id;
  final String name;
  final String email;
}

/// A partner connection request (contract: `PartnerRequestResponse`). For
/// incoming requests [senderName] is the other user; for sent requests
/// [receiverName] is.
class PartnerRequest {
  PartnerRequest({
    this.id,
    required this.senderName,
    required this.receiverName,
    this.status,
    this.createdAt,
  });

  factory PartnerRequest.fromJson(Map<String, dynamic> json) =>
      PartnerRequest(
        id: json['id'] as int?,
        senderName: json['senderName'] as String? ?? '',
        receiverName: json['receiverName'] as String? ?? '',
        status: json['status'] == null
            ? null
            : PartnerRequestStatus.fromWire(json['status'] as String),
        createdAt: json['createdAt'] as String?,
      );

  final int? id;
  final String senderName;
  final String receiverName;
  final PartnerRequestStatus? status;
  final String? createdAt;
}

/// A request this user sent (contract: `SentRequestResponse` — only the
/// receiver's name, no status; sent requests stay pending until answered).
class SentRequest {
  SentRequest({this.requestId, required this.receiverName});

  factory SentRequest.fromJson(Map<String, dynamic> json) => SentRequest(
        requestId: json['requestId'] as int?,
        receiverName: json['receiverName'] as String? ?? '',
      );

  final int? requestId;
  final String receiverName;
}

/// One chat message (contract: `ChatMessageResponse`). The sender is only
/// identified by name — no sender id exists in the contract, so mine-vs-theirs
/// alignment compares against the signed-in user's name.
class ChatMessage {
  ChatMessage({this.id, this.senderName, required this.content, this.createdAt});

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'] as int?,
        senderName: json['senderName'] as String?,
        content: json['content'] as String? ?? '',
        createdAt: json['createdAt'] as String?,
      );

  final int? id;
  final String? senderName;
  final String content;
  final String? createdAt;

  /// `HH:mm` slice of the server's wall-clock timestamp, or '' when absent.
  String get timeLabel {
    final c = createdAt ?? '';
    return c.length >= 16 ? c.substring(11, 16) : '';
  }
}

/// An in-app notification (contract: `NotificationResponse`). `type` is kept
/// as the raw wire string so unknown future types never crash parsing; the
/// NotificationType enum lives in the contract, not the client.
class AppNotification {
  AppNotification({
    this.id,
    this.type,
    required this.message,
    this.read,
    this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      AppNotification(
        id: json['id'] as int?,
        type: json['type'] as String?,
        message: json['message'] as String? ?? '',
        read: json['read'] as bool?,
        createdAt: json['createdAt'] as String?,
      );

  final int? id;
  final String? type;
  final String message;
  final bool? read;
  final String? createdAt;

  /// `yyyy-MM-dd HH:mm` slice of the server's wall-clock timestamp, or ''
  /// when absent.
  String get timestampLabel {
    final c = createdAt ?? '';
    return c.length >= 16 ? c.substring(0, 16).replaceFirst('T', ' ') : '';
  }
}

/// Notification delivery preferences (contract:
/// `NotificationPreferencesRequest`/`Response`). Serialization is
/// patch-style: null fields are omitted so the server keeps their current
/// value; a blank quiet-hours time clears it. `typePreferences` maps
/// NotificationType wire names to their push toggle.
class NotificationPreferences {
  NotificationPreferences({
    this.pushNotificationsEnabled,
    this.quietHoursEnabled,
    this.quietHoursStart,
    this.quietHoursEnd,
    this.typePreferences,
  });

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) =>
      NotificationPreferences(
        pushNotificationsEnabled: json['pushNotificationsEnabled'] as bool?,
        quietHoursEnabled: json['quietHoursEnabled'] as bool?,
        quietHoursStart: json['quietHoursStart'] as String?,
        quietHoursEnd: json['quietHoursEnd'] as String?,
        typePreferences: (json['typePreferences'] as Map<String, dynamic>?)
            ?.map((k, v) => MapEntry(k, v as bool)),
      );

  final bool? pushNotificationsEnabled;
  final bool? quietHoursEnabled;
  final String? quietHoursStart;
  final String? quietHoursEnd;
  final Map<String, bool>? typePreferences;

  /// Only non-null fields are sent — patch semantics per the contract.
  Map<String, dynamic> toJson() => {
        'pushNotificationsEnabled': ?pushNotificationsEnabled,
        'quietHoursEnabled': ?quietHoursEnabled,
        'quietHoursStart': ?quietHoursStart,
        'quietHoursEnd': ?quietHoursEnd,
        'typePreferences': ?typePreferences,
      };
}
