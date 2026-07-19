import 'dart:convert';

class ScheduledEmail {
  final String id;
  final String senderEmail;
  final String type; // Single, Multiple, PDF
  final List<String> recipients;
  final String subject;
  final String body;
  final String scheduledDate; // DD/MM/YYYY
  final String scheduledTime; // HH:MM AM/PM
  final String status; // In Process, Success

  ScheduledEmail({
    required this.id,
    required this.senderEmail,
    required this.type,
    required this.recipients,
    required this.subject,
    required this.body,
    required this.scheduledDate,
    required this.scheduledTime,
    this.status = 'In Process',
  });

  ScheduledEmail copyWith({
    String? id,
    String? senderEmail,
    String? type,
    List<String>? recipients,
    String? subject,
    String? body,
    String? scheduledDate,
    String? scheduledTime,
    String? status,
  }) {
    return ScheduledEmail(
      id: id ?? this.id,
      senderEmail: senderEmail ?? this.senderEmail,
      type: type ?? this.type,
      recipients: recipients ?? this.recipients,
      subject: subject ?? this.subject,
      body: body ?? this.body,
      scheduledDate: scheduledDate ?? this.scheduledDate,
      scheduledTime: scheduledTime ?? this.scheduledTime,
      status: status ?? this.status,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'senderEmail': senderEmail,
      'type': type,
      'recipients': recipients,
      'subject': subject,
      'body': body,
      'scheduledDate': scheduledDate,
      'scheduledTime': scheduledTime,
      'status': status,
    };
  }

  factory ScheduledEmail.fromMap(Map<String, dynamic> map) {
    return ScheduledEmail(
      id: map['id'],
      senderEmail: map['senderEmail'] ?? '',
      type: map['type'],
      recipients: List<String>.from(map['recipients']),
      subject: map['subject'] ?? '',
      body: map['body'] ?? '',
      scheduledDate: map['scheduledDate'],
      scheduledTime: map['scheduledTime'],
      status: map['status'] ?? 'In Process',
    );
  }

  String toJson() => json.encode(toMap());

  factory ScheduledEmail.fromJson(String source) => ScheduledEmail.fromMap(json.decode(source));
}
