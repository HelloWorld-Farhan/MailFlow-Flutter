import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/scheduled_email.dart';

enum CampaignEventKind { started, completed, failed }

class CampaignNotificationEvent {
  final CampaignEventKind kind;
  final ScheduledEmail email;
  final int activeParallelCount;
  final DateTime timestamp;

  CampaignNotificationEvent({
    required this.kind,
    required this.email,
    required this.activeParallelCount,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  String get displayName {
    if (email.scheduleName != null && email.scheduleName!.trim().isNotEmpty) {
      return email.scheduleName!.trim();
    }
    if (email.subject.trim().isNotEmpty) return email.subject.trim();
    return email.senderEmail;
  }
}

/// Evaluates campaign status transitions so Start, Parallel Progress, and Done
/// notifications fire accurately without replaying historical campaigns on launch.
class SendNotificationMonitor {
  bool _seeded = false;
  final Map<String, String> _lastStatusById = {};
  final Map<String, int> _lastSentById = {};
  String _lastProgressSignature = '';

  static bool isActiveStatus(String status) =>
      status == 'Running' ||
      status.startsWith('Doing') ||
      status.startsWith('Sending') ||
      status.startsWith('Day ') ||
      status.startsWith('Merge Day');

  static bool isDoneStatus(String status) => status == 'Success';

  static bool isFailedStatus(String status) => status.startsWith('Failed');

  static String? currentRecipient(ScheduledEmail email) {
    for (final entry in email.recipientStatuses.entries) {
      if (entry.value == 'inProcess') return entry.key;
    }
    return null;
  }

  /// Computes transition events between snapshots and returns the newly emitted events.
  List<CampaignNotificationEvent> evaluate(List<ScheduledEmail> emails) {
    final active = emails.where((e) => isActiveStatus(e.status)).toList();
    final parallelCount = active.length;
    final events = <CampaignNotificationEvent>[];

    if (!_seeded) {
      for (final email in emails) {
        _lastStatusById[email.id] = email.status;
        _lastSentById[email.id] = email.sentCount;
      }
      _seeded = true;
      return events;
    }

    final currentIds = <String>{};
    for (final email in emails) {
      currentIds.add(email.id);
      final prevStatus = _lastStatusById[email.id];
      final wasActive = prevStatus != null && isActiveStatus(prevStatus);
      final nowActive = isActiveStatus(email.status);
      final wasDone = prevStatus != null && isDoneStatus(prevStatus);
      final nowDone = isDoneStatus(email.status);
      final wasFailed = prevStatus != null && isFailedStatus(prevStatus);
      final nowFailed = isFailedStatus(email.status);

      if (nowActive && !wasActive) {
        events.add(CampaignNotificationEvent(
          kind: CampaignEventKind.started,
          email: email,
          activeParallelCount: parallelCount,
        ));
      } else if (nowDone && !wasDone) {
        events.add(CampaignNotificationEvent(
          kind: CampaignEventKind.completed,
          email: email,
          activeParallelCount: parallelCount,
        ));
      } else if (nowFailed && !wasFailed) {
        events.add(CampaignNotificationEvent(
          kind: CampaignEventKind.failed,
          email: email,
          activeParallelCount: parallelCount,
        ));
      }

      _lastStatusById[email.id] = email.status;
      _lastSentById[email.id] = email.sentCount;
    }

    _lastStatusById.removeWhere((id, _) => !currentIds.contains(id));
    _lastSentById.removeWhere((id, _) => !currentIds.contains(id));
    return events;
  }

  bool shouldUpdateProgress(List<ScheduledEmail> active) {
    final sig = active.map((e) => '${e.id}:${e.sentCount}:${e.status}').join('|');
    if (sig == _lastProgressSignature) return false;
    _lastProgressSignature = sig;
    return true;
  }

  void reset() {
    _seeded = false;
    _lastStatusById.clear();
    _lastSentById.clear();
    _lastProgressSignature = '';
  }
}

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static final SendNotificationMonitor monitor = SendNotificationMonitor();
  static bool _isInitialized = false;

  // Deduplication guard so background dispatcher + UI monitor don't double-ring the same alert.
  static final Map<String, String> _lastNotifiedEventById = {};

  static bool get _isAndroid => !kIsWeb && Platform.isAndroid;
  static bool get _isWindows => !kIsWeb && Platform.isWindows;
  static bool get _isSupported => _isAndroid || _isWindows;

  static int _campaignNotifId(String campaignId) => 2000 + (campaignId.hashCode.abs() % 50000);
  static int _progressNotifId(String campaignId) => 55000 + (campaignId.hashCode.abs() % 50000);
  static const int _parallelSummaryId = 1998;

  static Future<void> initialize() async {
    if (_isInitialized || !_isSupported) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const windowsSettings = WindowsInitializationSettings(
      appName: 'MailFlow',
      appUserModelId: 'com.mailflow.app',
      guid: 'a7f3c8b2-4f19-4d2e-9b1c-8e2d7f6a1094',
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      windows: windowsSettings,
    );

    await _notificationsPlugin.initialize(settings: initSettings);
    if (_isAndroid) {
      await _notificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    }
    _isInitialized = true;
  }

  static String _labelFor(ScheduledEmail email) {
    if (email.scheduleName != null && email.scheduleName!.trim().isNotEmpty) {
      return email.scheduleName!.trim();
    }
    if (email.subject.trim().isNotEmpty) return email.subject.trim();
    return email.senderEmail;
  }

  /// Processes a full list of campaigns, firing Start / Done system sounds and
  /// silent live progress notifications (with parallel count when > 1 are active).
  static Future<List<CampaignNotificationEvent>> handleSnapshot(
    List<ScheduledEmail> emails,
  ) async {
    final events = monitor.evaluate(emails);
    final active = emails.where((e) => SendNotificationMonitor.isActiveStatus(e.status)).toList();

    for (final ev in events) {
      if (ev.kind == CampaignEventKind.started) {
        await showSendingStartedNotification(ev.email, parallelCount: active.length);
      } else if (ev.kind == CampaignEventKind.completed) {
        await showSendingDoneNotification(ev.email, parallelRemaining: active.length);
      } else if (ev.kind == CampaignEventKind.failed) {
        await showSendingDoneNotification(
          ev.email,
          failed: true,
          parallelRemaining: active.length,
        );
      }
    }

    if (monitor.shouldUpdateProgress(active)) {
      if (active.isNotEmpty) {
        for (final campaign in active) {
          await showSendingProgressNotification(campaign, parallelCount: active.length);
        }
        if (active.length > 1) {
          await _showParallelSummaryNotification(active);
        } else {
          await cancelNotification(_parallelSummaryId);
        }
      } else {
        await cancelNotification(_parallelSummaryId);
      }
    }

    return events;
  }

  /// Fires immediately when a campaign starts sending, with system notification sound.
  static Future<void> showSendingStartedNotification(
    ScheduledEmail email, {
    int parallelCount = 1,
  }) async {
    if (!_isSupported) return;
    if (_lastNotifiedEventById[email.id] == 'started') return;
    _lastNotifiedEventById[email.id] = 'started';

    await initialize();
    final name = _labelFor(email);
    final total = email.recipients.length;
    final parallelNote = parallelCount > 1 ? ' • $parallelCount running in parallel' : '';

    final details = NotificationDetails(
      android: const AndroidNotificationDetails(
        'mailflow_sending_start',
        'Mail Sending Started',
        channelDescription: 'Plays system sound when automated email sending begins',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
      ),
      windows: WindowsNotificationDetails(
        audio: WindowsNotificationAudio.preset(sound: WindowsNotificationSound.mail),
        subtitle: email.senderEmail,
      ),
    );

    await _notificationsPlugin.show(
      id: _campaignNotifId(email.id),
      title: 'Sending Started: $name',
      body: 'Dispatching $total recipient${total == 1 ? '' : 's'}$parallelNote',
      notificationDetails: details,
    );
  }

  /// Updates an ongoing silent progress notification while a campaign sends.
  static Future<void> showSendingProgressNotification(
    ScheduledEmail email, {
    int parallelCount = 1,
  }) async {
    if (!_isSupported) return;
    await initialize();

    final name = _labelFor(email);
    final total = email.recipients.length;
    final sent = email.sentCount.clamp(0, total);
    final current = SendNotificationMonitor.currentRecipient(email);
    final recipientPart = current != null ? ' -> $current' : '';
    final parallelPart = parallelCount > 1 ? ' ($parallelCount parallel)' : '';
    final progressValue = total > 0 ? sent / total : 0.0;

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        'mailflow_sending_progress',
        'Live Sending Progress',
        channelDescription: 'Silent live progress for active email dispatches',
        importance: Importance.low,
        priority: Priority.low,
        playSound: false,
        onlyAlertOnce: true,
        ongoing: true,
        showProgress: total > 0,
        maxProgress: total > 0 ? total : 1,
        progress: sent,
      ),
      windows: WindowsNotificationDetails(
        audio: WindowsNotificationAudio.silent(),
        subtitle: email.senderEmail,
        progressBars: [
          WindowsProgressBar(
            id: 'prog_${email.id}',
            title: '$sent/$total sent$parallelPart',
            status: 'Sending$recipientPart',
            value: progressValue.clamp(0.0, 1.0),
          ),
        ],
      ),
    );

    await _notificationsPlugin.show(
      id: _progressNotifId(email.id),
      title: 'Sending: $name',
      body: '$sent / $total sent$recipientPart$parallelPart',
      notificationDetails: details,
    );
  }

  static Future<void> _showParallelSummaryNotification(
    List<ScheduledEmail> active,
  ) async {
    if (!_isSupported) return;
    await initialize();

    final totalSent = active.fold<int>(0, (s, e) => s + e.sentCount);
    final totalAll = active.fold<int>(0, (s, e) => s + e.recipients.length);
    final ratio = totalAll > 0 ? (totalSent / totalAll).clamp(0.0, 1.0) : 0.0;

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        'mailflow_sending_progress',
        'Live Sending Progress',
        channelDescription: 'Silent live progress for active email dispatches',
        importance: Importance.low,
        priority: Priority.low,
        playSound: false,
        onlyAlertOnce: true,
        ongoing: true,
        showProgress: totalAll > 0,
        maxProgress: totalAll > 0 ? totalAll : 1,
        progress: totalSent,
      ),
      windows: WindowsNotificationDetails(
        audio: WindowsNotificationAudio.silent(),
        subtitle: '${active.length} active senders running simultaneously',
        progressBars: [
          WindowsProgressBar(
            id: 'parallel_summary',
            title: '${active.length} Parallel Dispatches',
            status: '$totalSent / $totalAll total emails sent',
            value: ratio,
          ),
        ],
      ),
    );

    await _notificationsPlugin.show(
      id: _parallelSummaryId,
      title: '${active.length} Campaigns Sending in Parallel',
      body: '$totalSent / $totalAll emails sent across ${active.length} schedules',
      notificationDetails: details,
    );
  }

  /// Fires when a campaign finishes (Success or Failed), clearing its ongoing
  /// progress bar and playing the system notification sound.
  static Future<void> showSendingDoneNotification(
    ScheduledEmail email, {
    bool failed = false,
    int parallelRemaining = 0,
  }) async {
    if (!_isSupported) return;
    final key = failed ? 'failed:${email.status}' : 'completed';
    if (_lastNotifiedEventById[email.id] == key) return;
    _lastNotifiedEventById[email.id] = key;

    await initialize();
    await cancelNotification(_progressNotifId(email.id));

    final name = _labelFor(email);
    final total = email.recipients.length;
    final sent = email.sentCount;
    final stillRunning =
        parallelRemaining > 0 ? ' • $parallelRemaining still running' : '';

    final details = NotificationDetails(
      android: const AndroidNotificationDetails(
        'mailflow_sending_done',
        'Mail Sending Completed',
        channelDescription: 'Plays system sound when an email campaign finishes',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
      ),
      windows: WindowsNotificationDetails(
        audio: WindowsNotificationAudio.preset(sound: WindowsNotificationSound.defaultSound),
        subtitle: email.senderEmail,
      ),
    );

    await _notificationsPlugin.show(
      id: _campaignNotifId(email.id),
      title: failed ? 'Failed: $name' : 'Done: $name',
      body: failed
          ? '${email.status}$stillRunning'
          : 'All $sent/$total emails sent successfully$stillRunning',
      notificationDetails: details,
    );
  }

  static Future<void> cancelNotification(int id) async {
    if (!_isSupported || !_isInitialized) return;
    await _notificationsPlugin.cancel(id: id);
  }

  /// Clears deduplication state when a user explicitly resets/resends a campaign.
  static void clearCampaignAlertState(String campaignId) {
    _lastNotifiedEventById.remove(campaignId);
  }

  /// Sends a local notification with system default sound & vibration for app updates.
  static Future<void> showUpdateNotification({
    required String newVersion,
    String? body,
  }) async {
    if (!_isSupported) return;
    await initialize();

    final details = NotificationDetails(
      android: const AndroidNotificationDetails(
        'mailflow_updates',
        'Software Updates',
        channelDescription: 'Notifications for new MailFlow versions and updates',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
      ),
      windows: WindowsNotificationDetails(
        audio: WindowsNotificationAudio.preset(sound: WindowsNotificationSound.defaultSound),
      ),
    );

    await _notificationsPlugin.show(
      id: 1001,
      title: 'MailFlow Update Available (v$newVersion)',
      body: body ?? 'A new update is ready! Tap to download and install.',
      notificationDetails: details,
    );
  }
}
