import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/scheduled_email.dart';
import '../utils/date_helpers.dart';
import 'app_config.dart';

enum CloudStatus { connecting, connected, offline }

/// Client for MailFlow Cloudflare Worker API, Supabase REST, and Supabase Realtime.
class BackendService {
  static final http.Client _client = http.Client();
  static final ValueNotifier<CloudStatus> cloudStatus =
      ValueNotifier<CloudStatus>(CloudStatus.connecting);
  static String? lastCloudError;
  static final StreamController<void> _changesController =
      StreamController<void>.broadcast();
  static Stream<void> get onDataChanged => _changesController.stream;

  static WebSocket? _socket;
  static Timer? _heartbeatTimer;
  static Timer? _reconnectTimer;
  static Timer? _realtimeDebounce;
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
    final tParts = timeStr.trim().split(' ');
    if (DateHelpers.parseDmy(dateStr) == null || tParts.length != 2) return null;
    try {
      return DateHelpers.parseScheduleDateTime(dateStr, timeStr);
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>> _sendWorkerRequest(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Duration timeout = const Duration(seconds: 15),
    Set<int> okStatuses = const {200},
    String errorLabel = 'Request failed',
  }) async {
    final uri = Uri.parse('${AppConfig.backendApiUrl}$path');
    final encoded = body != null ? jsonEncode(body) : null;
    final Future<http.Response> req;
    if (method == 'GET') {
      req = _client.get(uri, headers: _workerHeaders);
    } else if (method == 'DELETE') {
      req = _client.delete(uri, headers: _workerHeaders);
    } else {
      req = _client.post(uri, headers: _workerHeaders, body: encoded);
    }
    final res = await req.timeout(timeout);
    if (!okStatuses.contains(res.statusCode)) {
      throw Exception('$errorLabel (${res.statusCode}): ${res.body}');
    }
    if (res.body.isEmpty) return {};
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Verifies the deployed Worker `/health` endpoint and updates [cloudStatus].
  static Future<Map<String, dynamic>> checkHealth() async {
    try {
      final data = await _sendWorkerRequest(
        'GET',
        '/health',
        timeout: const Duration(seconds: 12),
        errorLabel: 'Health check failed',
      );
      lastCloudError = null;
      cloudStatus.value = CloudStatus.connected;
      return data;
    } catch (e) {
      lastCloudError = e.toString().replaceFirst('Exception: ', '');
      cloudStatus.value = CloudStatus.offline;
      rethrow;
    }
  }

  /// Checks Worker health and ensures Realtime socket is connected.
  static Future<bool> verifyCloudConnection() async {
    cloudStatus.value = CloudStatus.connecting;
    try {
      await checkHealth();
      if (_socket == null) {
        await _connectSocket();
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Sends Google `serverAuthCode` to Worker `/oauth/exchange` to store an encrypted refresh token.
  static Future<String> exchangeServerAuthCode(String serverAuthCode) async {
    final data = await _sendWorkerRequest(
      'POST',
      '/oauth/exchange',
      body: {'serverAuthCode': serverAuthCode},
      timeout: const Duration(seconds: 20),
      errorLabel: 'OAuth exchange failed',
    );
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

    final data = await _sendWorkerRequest(
      'POST',
      '/campaigns',
      body: payload,
      timeout: const Duration(seconds: 30),
      okStatuses: const {200, 201},
      errorLabel: 'Schedule failed',
    );
    _changesController.add(null);
    return (data['campaignId'] ?? '').toString();
  }

  static Future<void> pauseCampaign(String id) async {
    await _sendWorkerRequest('POST', '/campaigns/$id/pause', errorLabel: 'Pause failed');
    _changesController.add(null);
  }

  static Future<void> resumeCampaign(String id, {bool forceWeekend = false}) async {
    await _sendWorkerRequest(
      'POST',
      '/campaigns/$id/resume',
      body: {
        'forceWeekend': forceWeekend,
        'timezoneOffsetMinutes': DateTime.now().timeZoneOffset.inMinutes,
      },
      errorLabel: 'Resume failed',
    );
    _changesController.add(null);
  }

  static Future<void> deleteCampaign(String id) async {
    await _sendWorkerRequest('DELETE', '/campaigns/$id', errorLabel: 'Delete failed');
    _changesController.add(null);
  }

  /// Triggers immediate Worker dispatch for due jobs and refreshes listeners if any were claimed.
  static Future<Map<String, dynamic>> triggerTick() async {
    final data = await _sendWorkerRequest(
      'POST',
      '/tick',
      timeout: const Duration(seconds: 20),
      errorLabel: 'Tick failed',
    );
    if ((data['claimed'] ?? 0) is int && (data['claimed'] as int) > 0) {
      _changesController.add(null);
    }
    return data;
  }

  /// Fetches campaigns + nested recipient job statuses from Supabase REST.
  static Future<List<ScheduledEmail>> fetchCampaigns() async {
    final uri = Uri.parse(
      '${AppConfig.supabaseUrl}/rest/v1/campaigns'
      '?select=id,schedule_name,sender_email,type,subject,body,daily_limit,delay_minutes,'
      'total_count,sent_count,failed_count,status,force_weekend,queued_after,'
      'pdf_name,scheduled_date,scheduled_time,merge_meta,created_at,'
      'email_jobs(recipient_email,status,error_message,send_at,sent_at)'
      '&email_jobs.order=send_at.asc'
      '&order=created_at.desc',
    );
    final res = await _client.get(uri, headers: _supabaseHeaders).timeout(const Duration(seconds: 15));
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
    final res = await _client.get(uri, headers: _supabaseHeaders).timeout(const Duration(seconds: 15));
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
    final sendTimes = <String, DateTime>{};
    DateTime? nextSendAt;
    for (final j in jobs) {
      final jm = j as Map<String, dynamic>;
      final email = (jm['recipient_email'] ?? '').toString();
      if (email.isEmpty) continue;
      recipients.add(email);
      final js = (jm['status'] ?? 'pending').toString();
      final scheduledDt = DateTime.tryParse((jm['send_at'] ?? '').toString())?.toLocal();
      final sentDt = DateTime.tryParse((jm['sent_at'] ?? '').toString())?.toLocal();
      if (js == 'sending') {
        statuses[email] = 'inProcess';
        if (scheduledDt != null) sendTimes[email] = scheduledDt;
      } else if (js == 'failed') {
        final err = (jm['error_message'] ?? '').toString();
        statuses[email] = err.isNotEmpty ? 'failed ($err)' : 'failed';
        if (scheduledDt != null) sendTimes[email] = scheduledDt;
      } else if (js == 'sent') {
        statuses[email] = 'sent';
        final exact = sentDt ?? scheduledDt;
        if (exact != null) sendTimes[email] = exact;
      } else {
        statuses[email] = 'pending';
        if (scheduledDt != null) {
          sendTimes[email] = scheduledDt;
          nextSendAt ??= scheduledDt;
        }
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
      recipientSendTimes: sendTimes,
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
      nextSendAt: nextSendAt,
    );
  }

  /// Opens a Supabase Realtime WebSocket subscription for live UI updates.
  static Future<void> startRealtime() async {
    _realtimeWanted = true;
    cloudStatus.value = CloudStatus.connecting;
    unawaited(verifyCloudConnection());
    if (!kIsWeb) {
      await _connectSocket();
    }
  }

  static Future<void> stopRealtime() async {
    _realtimeWanted = false;
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    _realtimeDebounce?.cancel();
    await _socket?.close();
    _socket = null;
  }

  static Future<void> _connectSocket() async {
    if (!_realtimeWanted || kIsWeb) return;
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
          'access_token': AppConfig.supabaseAnonKey,
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
            final event = msg['event'];
            if (event == 'phx_reply' && msg['payload']?['status'] == 'ok') {
              lastCloudError = null;
              cloudStatus.value = CloudStatus.connected;
            } else if (event == 'postgres_changes') {
              cloudStatus.value = CloudStatus.connected;
              _realtimeDebounce?.cancel();
              _realtimeDebounce = Timer(const Duration(milliseconds: 120), () {
                _changesController.add(null);
              });
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
    if (cloudStatus.value != CloudStatus.offline) {
      cloudStatus.value = CloudStatus.connecting;
    }
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      _connectSocket();
    });
  }
}
