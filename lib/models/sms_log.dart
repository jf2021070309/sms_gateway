// lib/models/sms_log.dart
import 'dart:convert';

enum SmsStatus { success, failed, pending }

class SmsLog {
  final String id;
  final String phone;
  final String message;
  final DateTime timestamp;
  final SmsStatus status;
  final String? errorMessage;

  SmsLog({
    required this.id,
    required this.phone,
    required this.message,
    required this.timestamp,
    required this.status,
    this.errorMessage,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'phone': phone,
      'message': message,
      'timestamp': timestamp.toIso8601String(),
      'status': status.name,
      'errorMessage': errorMessage,
    };
  }

  factory SmsLog.fromMap(Map<String, dynamic> map) {
    return SmsLog(
      id: map['id'] ?? '',
      phone: map['phone'] ?? '',
      message: map['message'] ?? '',
      timestamp: DateTime.parse(map['timestamp']),
      status: SmsStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => SmsStatus.failed,
      ),
      errorMessage: map['errorMessage'],
    );
  }

  String toJson() => json.encode(toMap());

  factory SmsLog.fromJson(String source) =>
      SmsLog.fromMap(json.decode(source));
}
