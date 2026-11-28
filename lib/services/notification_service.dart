import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/scheduled_email.dart';
import '../theme/app_theme.dart';

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
  static final StreamController<String> _tapController =
      StreamController<String>.broadcast();
  static Stream<String> get onNotificationTap => _tapController.stream;
  static String? _pendingInitialCampaignId;
  static bool _isInitialized = false;

  // Deduplication guard so background dispatcher + UI monitor don't double-ring the same alert.
  static final Map<String, String> _lastNotifiedEventById = {};

  static bool get _isAndroid => !kIsWeb && Platform.isAndroid;
  static bool get _isWindows => !kIsWeb && Platform.isWindows;
  static bool get _isApple => !kIsWeb && (Platform.isIOS || Platform.isMacOS);
  static bool get _isSupported => _isAndroid || _isWindows || _isApple;

  static int _campaignNotifId(String campaignId) => 2000 + (campaignId.hashCode.abs() % 50000);
  static const int _parallelSummaryId = 1998;
  static const String updatePayload = 'app_update';

  static Color get _notifAccentColor {
    final mode = AppTheme.themeModeNotifier.value;
    final isDark = mode == ThemeMode.dark ||
        (mode == ThemeMode.system &&
            PlatformDispatcher.instance.platformBrightness == Brightness.dark);
    return isDark ? AppTheme.blackberryCream : AppTheme.primaryBlue;
  }

  static Future<void> initialize() async {
    if (_isInitialized || !_isSupported) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestSoundPermission: true,
      requestBadgePermission: true,
    );
    const windowsSettings = WindowsInitializationSettings(
      appName: 'MailFlow',
      appUserModelId: 'com.mailflow.app',
      guid: 'a7f3c8b2-4f19-4d2e-9b1c-8e2d7f6a1094',
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
      windows: windowsSettings,
    );

    await _notificationsPlugin.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload?.trim();
        if (payload != null && payload.isNotEmpty) {
          _tapController.add(payload);
        }
      },
    );
    try {
      final launchDetails = await _notificationsPlugin.getNotificationAppLaunchDetails();
      final launchPayload = launchDetails?.notificationResponse?.payload?.trim();
      if ((launchDetails?.didNotificationLaunchApp ?? false) &&
          launchPayload != null &&
          launchPayload.isNotEmpty) {
        _pendingInitialCampaignId = launchPayload;
      }
    } catch (_) {}
    if (_isAndroid) {
      await _notificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    }
    _isInitialized = true;
  }

  /// Returns and clears the campaign ID if the app was cold-launched by tapping a notification.
  static String? consumeInitialCampaignId() {
    final id = _pendingInitialCampaignId;
    _pendingInitialCampaignId = null;
    return id;
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
        await _showParallelSummaryNotification(active);
      } else {
        await cancelNotification(_parallelSummaryId);
      }
    }

    return events;
  }

  /// Fires 60s before a scheduled campaign starts and updates silently each second
  /// using the single per-schedule notification ID.
  static Future<void> showPreStartCountdownNotification(
    ScheduledEmail email,
    int secondsLeft, {
    bool silent = false,
  }) async {
    if (!_isSupported) return;
    await initialize();
    final name = _labelFor(email);
    final total = email.recipients.length;
    final pct = ((60 - secondsLeft) / 60 * 100).round().clamp(0, 100);

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        silent ? 'mailflow_sending_progress' : 'mailflow_sending_start',
        silent ? 'Live Sending Progress' : 'Mail Sending Started',
        channelDescription: 'Countdown and live progress for scheduled emails',
        importance: silent ? Importance.low : Importance.high,
        priority: silent ? Priority.low : Priority.high,
        playSound: !silent,
        onlyAlertOnce: true,
        ongoing: true,
        showProgress: true,
        maxProgress: 60,
        progress: (60 - secondsLeft).clamp(0, 60),
        color: _notifAccentColor,
      ),
      iOS: DarwinNotificationDetails(presentAlert: !silent, presentBanner: !silent, presentSound: !silent),
      macOS: DarwinNotificationDetails(presentAlert: !silent, presentBanner: !silent, presentSound: !silent),
      windows: WindowsNotificationDetails(
        audio: silent ? WindowsNotificationAudio.silent() : WindowsNotificationAudio.preset(sound: WindowsNotificationSound.mail),
        subtitle: email.senderEmail,
        progressBars: [
          WindowsProgressBar(
            id: 'pre_${email.id}',
            title: '$name • Starting in ${secondsLeft}s',
            status: '$total recipient${total == 1 ? '' : 's'}',
            value: (pct / 100).clamp(0.0, 1.0),
          ),
        ],
      ),
    );

    await _notificationsPlugin.show(
      id: _campaignNotifId(email.id),
      title: 'Starting Soon: $name (${secondsLeft}s)',
      body: 'Starts in ${secondsLeft}s • $total recipient${total == 1 ? '' : 's'}',
      notificationDetails: details,
      payload: email.id,
    );
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
      android: AndroidNotificationDetails(
        'mailflow_sending_start',
        'Mail Sending Started',
        channelDescription: 'Plays system sound when automated email sending begins',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        color: _notifAccentColor,
      ),
      iOS: const DarwinNotificationDetails(presentAlert: true, presentBanner: true, presentSound: true),
      macOS: const DarwinNotificationDetails(presentAlert: true, presentBanner: true, presentSound: true),
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
      payload: email.id,
    );
  }

  /// Updates the single per-schedule notification silently while a campaign sends.
  static Future<void> showSendingProgressNotification(
    ScheduledEmail email, {
    int parallelCount = 1,
    int? nextSendInSec,
  }) async {
    if (!_isSupported) return;
    await initialize();

    final name = _labelFor(email);
    final total = email.recipients.length;
    final sent = email.sentCount.clamp(0, total);
    final current = SendNotificationMonitor.currentRecipient(email);
    final recipientPart = current != null ? ' -> $current' : '';
    final gapPart = nextSendInSec != null && nextSendInSec > 0
        ? ' • Next in ${nextSendInSec}s'
        : '';
    final parallelPart = parallelCount > 1 ? ' • $parallelCount parallel' : '';
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
        color: _notifAccentColor,
      ),
      iOS: const DarwinNotificationDetails(presentAlert: false, presentSound: false),
      macOS: const DarwinNotificationDetails(presentAlert: false, presentSound: false),
      windows: WindowsNotificationDetails(
        audio: WindowsNotificationAudio.silent(),
        subtitle: email.senderEmail,
        progressBars: [
          WindowsProgressBar(
            id: 'prog_${email.id}',
            title: '$sent/$total sent$gapPart$parallelPart',
            status: 'Sending$recipientPart',
            value: progressValue.clamp(0.0, 1.0),
          ),
        ],
      ),
    );

    await _notificationsPlugin.show(
      id: _campaignNotifId(email.id),
      title: 'Sending: $name ($sent/$total)',
      body: '$sent/$total sent$gapPart$recipientPart$parallelPart',
      notificationDetails: details,
      payload: email.id,
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
    final now = DateTime.now();
    final lines = active.map((e) {
      final nextSec = e.nextSendAt?.difference(now).inSeconds;
      final nextLabel = (nextSec != null && nextSec > 0) ? ' • Next ${nextSec}s' : '';
      return '${_labelFor(e)}: ${e.sentCount}/${e.recipients.length} sent$nextLabel';
    }).toList();
    final title = active.length == 1
        ? 'Sending: ${_labelFor(active.first)}'
        : '${active.length} Schedules Sending in Parallel';
    final summary = '$totalSent / $totalAll emails sent';

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
        styleInformation: InboxStyleInformation(
          lines,
          contentTitle: title,
          summaryText: summary,
        ),
        color: _notifAccentColor,
      ),
      iOS: const DarwinNotificationDetails(presentAlert: false, presentSound: false),
      macOS: const DarwinNotificationDetails(presentAlert: false, presentSound: false),
      windows: WindowsNotificationDetails(
        audio: WindowsNotificationAudio.silent(),
        subtitle: '${active.length} active schedule${active.length == 1 ? '' : 's'}',
        progressBars: [
          WindowsProgressBar(
            id: 'parallel_summary',
            title: title,
            status: summary,
            value: ratio,
          ),
        ],
      ),
    );

    await _notificationsPlugin.show(
      id: _parallelSummaryId,
      title: title,
      body: lines.join(' | '),
      notificationDetails: details,
      payload: active.first.id,
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

    final name = _labelFor(email);
    final total = email.recipients.length;
    final sent = email.sentCount;
    final stillRunning =
        parallelRemaining > 0 ? ' • $parallelRemaining still running' : '';

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        'mailflow_sending_done',
        'Mail Sending Completed',
        channelDescription: 'Plays system sound when an email campaign finishes',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        color: _notifAccentColor,
      ),
      iOS: const DarwinNotificationDetails(presentAlert: true, presentBanner: true, presentSound: true),
      macOS: const DarwinNotificationDetails(presentAlert: true, presentBanner: true, presentSound: true),
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
      payload: email.id,
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
      android: AndroidNotificationDetails(
        'mailflow_updates',
        'Software Updates',
        channelDescription: 'Notifications for new MailFlow versions and updates',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        color: _notifAccentColor,
      ),
      iOS: const DarwinNotificationDetails(presentAlert: true, presentBanner: true, presentSound: true),
      macOS: const DarwinNotificationDetails(presentAlert: true, presentBanner: true, presentSound: true),
      windows: WindowsNotificationDetails(
        audio: WindowsNotificationAudio.preset(sound: WindowsNotificationSound.defaultSound),
      ),
    );

    await _notificationsPlugin.show(
      id: 1001,
      title: 'MailFlow Update Available (v$newVersion)',
      body: body ?? 'A new update is ready! Tap to download and install.',
      notificationDetails: details,
      payload: updatePayload,
    );
  }

  /// Shows or updates a real-time ongoing progress notification while an update downloads.
  static Future<void> showUpdateDownloadProgress({
    required String version,
    required int progressPct,
    required String subtitle,
    bool indeterminate = false,
  }) async {
    if (!_isSupported) return;
    await initialize();

    final pct = progressPct.clamp(0, 100);
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        'mailflow_update_download',
        'Update Downloads',
        channelDescription: 'Real-time progress while downloading MailFlow updates',
        importance: Importance.low,
        priority: Priority.low,
        playSound: false,
        onlyAlertOnce: true,
        ongoing: true,
        showProgress: true,
        indeterminate: indeterminate,
        maxProgress: 100,
        progress: pct,
      ),
      iOS: const DarwinNotificationDetails(presentAlert: false, presentSound: false),
      macOS: const DarwinNotificationDetails(presentAlert: false, presentSound: false),
      windows: WindowsNotificationDetails(
        audio: WindowsNotificationAudio.silent(),
        progressBars: [
          WindowsProgressBar(
            id: 'update_dl',
            title: 'Downloading MailFlow v$version',
            status: subtitle,
            value: indeterminate ? null : pct / 100.0,
          ),
        ],
      ),
    );

    await _notificationsPlugin.show(
      id: 1002,
      title: 'Downloading MailFlow v$version ($pct%)',
      body: subtitle,
      notificationDetails: details,
      payload: updatePayload,
    );
  }

  /// Replaces the progress notification with a ready-to-install alert.
  static Future<void> showUpdateDownloadComplete(String version) async {
    if (!_isSupported) return;
    await initialize();
    await cancelNotification(1002);

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'mailflow_updates',
        'Software Updates',
        channelDescription: 'Notifications for new MailFlow versions and updates',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
      ),
      iOS: DarwinNotificationDetails(presentAlert: true, presentBanner: true, presentSound: true),
      macOS: DarwinNotificationDetails(presentAlert: true, presentBanner: true, presentSound: true),
    );

    await _notificationsPlugin.show(
      id: 1002,
      title: 'MailFlow v$version Downloaded',
      body: 'Tap to complete installation.',
      notificationDetails: details,
      payload: updatePayload,
    );
  }

  /// Replaces the progress notification with an error alert if download fails.
  static Future<void> showUpdateDownloadFailed(String message) async {
    if (!_isSupported) return;
    await initialize();
    await cancelNotification(1002);

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'mailflow_updates',
        'Software Updates',
        channelDescription: 'Notifications for new MailFlow versions and updates',
        importance: Importance.high,
        priority: Priority.high,
      ),
    );

    await _notificationsPlugin.show(
      id: 1002,
      title: 'Update Download Failed',
      body: message,
      notificationDetails: details,
      payload: updatePayload,
    );
  }
}
