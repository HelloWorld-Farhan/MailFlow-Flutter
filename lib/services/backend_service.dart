import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/scheduled_email.dart';
import 'app_config.dart';

/// Client for MailFlow Cloudflare Worker API, Supabase REST, and Supabase Realtime.
class BackendService {
  static final StreamController<void> _changesController =
      StreamController<void>.broadcast();
  static Stream<void> get onDataChanged => _changesController.stream;

  static WebSocket? _socket;
  static Timer? _heartbeatTimer;
  static Timer? _reconnectTimer;
  static bool _realtimeWanted = false;
  static int _refCounter = 1;

  static Map<String, String> get _workerHeaders => {
        'Authorization': 'Bearer ${AppConfig.backendApiSecret}',
        'Content-Type': 'application/json',
        'User-Agent': 'MailFlow-App/1.0',
      };

  static Map<String, String> get _supabaseHeaders => {
        'apikey': AppConfig.supabaseAnonKey,
        'Authorization': 'Bearer ${AppConfig.supabaseAnonKey}',
        'Content-Type': 'application/json',
      };

  /// Parses `DD/MM/YYYY` + `HH:MM AM/PM` into a local DateTime.
  static DateTime? parseScheduleDateTime(String dateStr, String timeStr) {
    final dParts = dateStr.split('/');
    final tParts = timeStr.trim().split(' ');
    if (dParts.length != 3 || tParts.length != 2) return null;
    final hm = tParts[0].split(':');
    if (hm.length != 2) return null;

    final day = int.tryParse(dParts[0]);
    final month = int.tryParse(dParts[1]);
    final year = int.tryParse(dParts[2]);
    var hour = int.tryParse(hm[0]);
    final minute = int.tryParse(hm[1]);
    if (day == null || month == null || year == null || hour == null || minute == null) {
      return null;
    }

    final ampm = tParts[1].toUpperCase();
    if (ampm == 'PM' && hour < 12) hour += 12;
    if (ampm == 'AM' && hour == 12) hour = 0;
    return DateTime(year, month, day, hour, minute);
  }

  /// Verifies the deployed Worker `/health` endpoint.
  static Future<Map<String, dynamic>> checkHealth() async {
    if (!AppConfig.isBackendEnabled) {
      throw Exception('Backend URL or secrets are not configured.');
    }
    final res = await http
        .get(Uri.parse('${AppConfig.backendApiUrl}/health'), headers: _workerHeaders)
        .timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) {
      throw Exception('Health check failed (${res.statusCode}): ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Sends Google `serverAuthCode` to Worker `/oauth/exchange` to store an encrypted refresh token.
  static Future<String> exchangeServerAuthCode(String serverAuthCode) async {
    final res = await http
        .post(
          Uri.parse('${AppConfig.backendApiUrl}/oauth/exchange'),
          headers: _workerHeaders,
          body: jsonEncode({'serverAuthCode': serverAuthCode}),
        )
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw Exception('OAuth exchange failed (${res.statusCode}): ${res.body}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (data['senderEmail'] ?? '').toString();
  }

  /// Schedules a campaign on the backend Worker (computes multi-day `send_at` slots).
  static Future<String> createCampaign(ScheduledEmail email) async {
    final startLocal = parseScheduleDateTime(email.scheduledDate, email.scheduledTime);
    if (startLocal == null) {
      throw Exception('Invalid schedule date/time format.');
    }

    final payload = {
      'scheduleName': email.scheduleName,
      'senderEmail': email.senderEmail,
      'type': email.isMerged ? 'Merged' : email.type,
      'subject': email.subject,
      'body': email.body,
      'recipients': email.recipients,
      'startAtIso': startLocal.toUtc().toIso8601String(),
      'dailyLimit': email.dailyLimit > 0 ? email.dailyLimit : (email.type == 'PDF' ? 40 : 50),
      'delayMinutes': email.delayMinutes,
      'forceWeekend': email.forceWeekend,
      'queuedAfter': email.queuedAfter,
      'timezoneOffsetMinutes': startLocal.timeZoneOffset.inMinutes,
      'pdfName': email.pdfName,
      'scheduledDate': email.scheduledDate,
      'scheduledTime': email.scheduledTime,
      if (email.isMerged)
        'mergeMeta': {
          'mergedSourceIds': email.mergedSourceIds,
          'mergeContributions': email.mergeContributions,
          'mergeSourceNames': email.mergeSourceNames,
        },
    };

    final res = await http
        .post(
          Uri.parse('${AppConfig.backendApiUrl}/campaigns'),
          headers: _workerHeaders,
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 201 && res.statusCode != 200) {
      throw Exception('Schedule failed (${res.statusCode}): ${res.body}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    _changesController.add(null);
    return (data['campaignId'] ?? '').toString();
  }

  static Future<void> pauseCampaign(String id) async {
    final res = await http
        .post(Uri.parse('${AppConfig.backendApiUrl}/campaigns/$id/pause'), headers: _workerHeaders)
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw Exception('Pause failed (${res.statusCode}): ${res.body}');
    }
    _changesController.add(null);
  }

  static Future<void> resumeCampaign(String id, {bool forceWeekend = false}) async {
    final res = await http
        .post(
          Uri.parse('${AppConfig.backendApiUrl}/campaigns/$id/resume'),
          headers: _workerHeaders,
          body: jsonEncode({'forceWeekend': forceWeekend}),
        )
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw Exception('Resume failed (${res.statusCode}): ${res.body}');
    }
    _changesController.add(null);
  }

  static Future<void> deleteCampaign(String id) async {
    final res = await http
        .delete(Uri.parse('${AppConfig.backendApiUrl}/campaigns/$id'), headers: _workerHeaders)
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw Exception('Delete failed (${res.statusCode}): ${res.body}');
    }
    _changesController.add(null);
  }

  /// Fetches campaigns + nested recipient job statuses from Supabase REST.
  static Future<List<ScheduledEmail>> fetchCampaigns() async {
    final uri = Uri.parse(
      '${AppConfig.supabaseUrl}/rest/v1/campaigns'
      '?select=id,schedule_name,sender_email,type,subject,body,daily_limit,delay_minutes,'
      'total_count,sent_count,failed_count,status,force_weekend,queued_after,'
      'pdf_name,scheduled_date,scheduled_time,merge_meta,created_at,'
      'email_jobs(recipient_email,status,error_message)'
      '&order=created_at.desc',
    );
    final res = await http.get(uri, headers: _supabaseHeaders).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw Exception('Failed to load campaigns (${res.statusCode}): ${res.body}');
    }
    final rows = jsonDecode(res.body) as List<dynamic>;
    return rows.map((row) => _mapCampaignRow(row as Map<String, dynamic>)).toList();
  }

  /// Fetches today's (UTC) per-sender sent counts from Supabase `daily_usage`.
  static Future<Map<String, int>> fetchDailyLimits() async {
    final nowUtc = DateTime.now().toUtc();
    final ymd =
        '${nowUtc.year}-${nowUtc.month.toString().padLeft(2, '0')}-${nowUtc.day.toString().padLeft(2, '0')}';
    final uri = Uri.parse(
      '${AppConfig.supabaseUrl}/rest/v1/daily_usage?select=sender_email,sent_count&usage_date=eq.$ymd',
    );
    final res = await http.get(uri, headers: _supabaseHeaders).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw Exception('Failed to load daily usage (${res.statusCode}): ${res.body}');
    }
    final rows = jsonDecode(res.body) as List<dynamic>;
    final result = <String, int>{};
    for (final item in rows) {
      final map = item as Map<String, dynamic>;
      final sender = (map['sender_email'] ?? '').toString();
      final count = (map['sent_count'] as num?)?.toInt() ?? 0;
      if (sender.isNotEmpty) result[sender] = count;
    }
    return result;
  }

  static ScheduledEmail _mapCampaignRow(Map<String, dynamic> row) {
    final rawType = (row['type'] ?? 'Single').toString();
    final isMerged = rawType == 'Merged';
    final total = (row['total_count'] as num?)?.toInt() ?? 0;
    final sent = (row['sent_count'] as num?)?.toInt() ?? 0;
    final dailyLimit = (row['daily_limit'] as num?)?.toInt() ?? 50;
    final rawStatus = (row['status'] ?? 'Scheduled').toString();

    final jobs = (row['email_jobs'] as List<dynamic>?) ?? const [];
    final recipients = <String>[];
    final statuses = <String, String>{};
    for (final j in jobs) {
      final jm = j as Map<String, dynamic>;
      final email = (jm['recipient_email'] ?? '').toString();
      if (email.isEmpty) continue;
      recipients.add(email);
      final js = (jm['status'] ?? 'pending').toString();
      if (js == 'sending') {
        statuses[email] = 'inProcess';
      } else if (js == 'failed') {
        final err = (jm['error_message'] ?? '').toString();
        statuses[email] = err.isNotEmpty ? 'failed ($err)' : 'failed';
      } else if (js == 'sent') {
        statuses[email] = 'sent';
      } else {
        statuses[email] = 'pending';
      }
    }

    String uiStatus = rawStatus;
    if (rawStatus == 'Completed') {
      uiStatus = 'Success';
    } else if (rawStatus == 'Running') {
      if (isMerged) {
        final day = dailyLimit > 0 ? (sent / dailyLimit).ceil().clamp(1, 999) : 1;
        uiStatus = 'Merge Day $day: $sent/$total sent';
      } else if (rawType == 'PDF') {
        final day = dailyLimit > 0 ? (sent / dailyLimit).ceil().clamp(1, 999) : 1;
        uiStatus = 'Day $day: $sent/$total sent';
      } else {
        uiStatus = 'Doing it... ($sent/$total)';
      }
    }

    final mergeMeta = row['merge_meta'] as Map<String, dynamic>?;
    final createdAtIso = (row['created_at'] ?? '').toString();
    String? createdAtStr;
    final parsedCreated = DateTime.tryParse(createdAtIso)?.toLocal();
    if (parsedCreated != null) {
      createdAtStr =
          '${parsedCreated.day.toString().padLeft(2, '0')}/${parsedCreated.month.toString().padLeft(2, '0')}/${parsedCreated.year}';
    }

    return ScheduledEmail(
      id: (row['id'] ?? '').toString(),
      senderEmail: (row['sender_email'] ?? '').toString(),
      type: isMerged ? 'PDF' : rawType,
      recipients: recipients,
      subject: (row['subject'] ?? '').toString(),
      body: (row['body'] ?? '').toString(),
      scheduledDate: (row['scheduled_date'] ?? createdAtStr ?? '').toString(),
      scheduledTime: (row['scheduled_time'] ?? '12:00 PM').toString(),
      status: uiStatus,
      scheduleName: row['schedule_name']?.toString(),
      sentCount: sent,
      dailyLimit: dailyLimit,
      createdAt: createdAtStr,
      pdfName: row['pdf_name']?.toString(),
      recipientStatuses: statuses,
      isMerged: isMerged,
      mergedSourceIds: mergeMeta?['mergedSourceIds'] != null
          ? List<String>.from(mergeMeta!['mergedSourceIds'] as List)
          : [],
      mergeContributions: mergeMeta?['mergeContributions'] != null
          ? (mergeMeta!['mergeContributions'] as Map).map(
              (k, v) => MapEntry(k.toString(), (v as num).toInt()),
            )
          : {},
      mergeSourceNames: mergeMeta?['mergeSourceNames'] != null
          ? Map<String, String>.from(mergeMeta!['mergeSourceNames'] as Map)
          : {},
      queuedAfter: row['queued_after']?.toString(),
      forceWeekend: row['force_weekend'] == true,
      delayMinutes: (row['delay_minutes'] as num?)?.toInt() ?? 0,
    );
  }

  /// Opens a Supabase Realtime WebSocket subscription for live UI updates.
  static Future<void> startRealtime() async {
    if (kIsWeb || !AppConfig.isBackendEnabled) return;
    _realtimeWanted = true;
    await _connectSocket();
  }

  static Future<void> stopRealtime() async {
    _realtimeWanted = false;
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    await _socket?.close();
    _socket = null;
  }

  static Future<void> _connectSocket() async {
    if (!_realtimeWanted || !AppConfig.isBackendEnabled) return;
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();

    try {
      await _socket?.close();
      final wsBase = AppConfig.supabaseUrl
          .replaceFirst('https://', 'wss://')
          .replaceFirst('http://', 'ws://');
      final wsUrl =
          '$wsBase/realtime/v1/websocket?apikey=${Uri.encodeComponent(AppConfig.supabaseAnonKey)}&vsn=1.0.0';

      final socket = await WebSocket.connect(wsUrl);
      _socket = socket;

      socket.add(jsonEncode({
        'topic': 'realtime:mailflow',
        'event': 'phx_join',
        'payload': {
          'config': {
            'postgres_changes': [
              {'event': '*', 'schema': 'public', 'table': 'campaigns'},
              {'event': '*', 'schema': 'public', 'table': 'email_jobs'},
              {'event': '*', 'schema': 'public', 'table': 'daily_usage'},
            ],
          },
        },
        'ref': '${_refCounter++}',
      }));

      _heartbeatTimer = Timer.periodic(const Duration(seconds: 25), (_) {
        try {
          _socket?.add(jsonEncode({
            'topic': 'phoenix',
            'event': 'heartbeat',
            'payload': {},
            'ref': '${_refCounter++}',
          }));
        } catch (_) {}
      });

      socket.listen(
        (raw) {
          try {
            final msg = jsonDecode(raw.toString()) as Map<String, dynamic>;
            if (msg['event'] == 'postgres_changes') {
              _changesController.add(null);
            }
          } catch (_) {}
        },
        onDone: _scheduleReconnect,
        onError: (_) => _scheduleReconnect(),
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  static void _scheduleReconnect() {
    _heartbeatTimer?.cancel();
    if (!_realtimeWanted) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      _connectSocket();
    });
  }
}
