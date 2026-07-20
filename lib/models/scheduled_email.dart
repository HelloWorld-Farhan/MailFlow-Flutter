import 'dart:convert';

class ScheduledEmail {
  final String id;
  final String senderEmail;
  final String type;
  final List<String> recipients;
  final String subject;
  final String body;
  final String scheduledDate;
  final String scheduledTime;
  final String status;
  final String? scheduleName;
  final int sentCount;
  final int dailyLimit;
  final String? lastSentDate;
  // Per-recipient statuses: 'sent', 'failed', 'inProcess', 'pending'
  final Map<String, String> recipientStatuses;

  // ── Merge / Queue fields ──────────────────────────────────────────────
  /// True if this schedule was created by merging two PDF schedules
  final bool isMerged;
  /// IDs of the source PDF schedules that were merged into this one
  final List<String> mergedSourceIds;
  /// sourceId → daily email allocation count (proportional split)
  final Map<String, int> mergeContributions;
  /// sourceId → display name of source schedule
  final Map<String, String> mergeSourceNames;
  /// ID of the PDF schedule this one waits for (Queue After mode)
  final String? queuedAfter;

  ScheduledEmail({
    required this.id,
    required this.senderEmail,
    required this.type,
    required this.recipients,
    required this.subject,
    required this.body,
    required this.scheduledDate,
    required this.scheduledTime,
    this.status = 'Scheduled',
    this.scheduleName,
    this.sentCount = 0,
    this.dailyLimit = 0,
    this.lastSentDate,
    Map<String, String>? recipientStatuses,
    this.isMerged = false,
    List<String>? mergedSourceIds,
    Map<String, int>? mergeContributions,
    Map<String, String>? mergeSourceNames,
    this.queuedAfter,
  })  : recipientStatuses = recipientStatuses ?? {},
        mergedSourceIds = mergedSourceIds ?? [],
        mergeContributions = mergeContributions ?? {},
        mergeSourceNames = mergeSourceNames ?? {};

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
    String? scheduleName,
    int? sentCount,
    int? dailyLimit,
    String? lastSentDate,
    Map<String, String>? recipientStatuses,
    bool? isMerged,
    List<String>? mergedSourceIds,
    Map<String, int>? mergeContributions,
    Map<String, String>? mergeSourceNames,
    String? queuedAfter,
    bool clearQueuedAfter = false,
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
      scheduleName: scheduleName ?? this.scheduleName,
      sentCount: sentCount ?? this.sentCount,
      dailyLimit: dailyLimit ?? this.dailyLimit,
      lastSentDate: lastSentDate ?? this.lastSentDate,
      recipientStatuses: recipientStatuses ?? this.recipientStatuses,
      isMerged: isMerged ?? this.isMerged,
      mergedSourceIds: mergedSourceIds ?? this.mergedSourceIds,
      mergeContributions: mergeContributions ?? this.mergeContributions,
      mergeSourceNames: mergeSourceNames ?? this.mergeSourceNames,
      queuedAfter: clearQueuedAfter ? null : (queuedAfter ?? this.queuedAfter),
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
      'scheduleName': scheduleName,
      'sentCount': sentCount,
      'dailyLimit': dailyLimit,
      'lastSentDate': lastSentDate,
      'recipientStatuses': recipientStatuses,
      'isMerged': isMerged,
      'mergedSourceIds': mergedSourceIds,
      'mergeContributions': mergeContributions,
      'mergeSourceNames': mergeSourceNames,
      'queuedAfter': queuedAfter,
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
      status: map['status'] ?? 'Scheduled',
      scheduleName: map['scheduleName'],
      sentCount: map['sentCount'] ?? 0,
      dailyLimit: map['dailyLimit'] ?? 0,
      lastSentDate: map['lastSentDate'],
      recipientStatuses: map['recipientStatuses'] != null
          ? Map<String, String>.from(map['recipientStatuses'])
          : {},
      isMerged: map['isMerged'] ?? false,
      mergedSourceIds: map['mergedSourceIds'] != null
          ? List<String>.from(map['mergedSourceIds'])
          : [],
      mergeContributions: map['mergeContributions'] != null
          ? Map<String, int>.from(
              (map['mergeContributions'] as Map).map(
                (k, v) => MapEntry(k.toString(), (v as num).toInt()),
              ),
            )
          : {},
      mergeSourceNames: map['mergeSourceNames'] != null
          ? Map<String, String>.from(map['mergeSourceNames'])
          : {},
      queuedAfter: map['queuedAfter'],
    );
  }

  String toJson() => json.encode(toMap());

  factory ScheduledEmail.fromJson(String source) =>
      ScheduledEmail.fromMap(json.decode(source));
}
