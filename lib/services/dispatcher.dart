import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../models/scheduled_email.dart';
import '../utils/date_helpers.dart';
import 'app_config.dart';
import 'mail_service.dart';
import 'notification_service.dart';
import 'storage_service.dart';

@pragma('vm:entry-point')
void exactAlarmCallback() async {
  WidgetsFlutterBinding.ensureInitialized();
  await BackgroundDispatcher.checkAndSendEmails();
}

class BackgroundDispatcher {
  static Timer? _timer;
  static bool _isChecking = false;
  static const Duration _tokenCacheTtl = Duration(minutes: 45);
  static final Map<String, GoogleSignIn> _signInCache = {};
  static final Map<String, ({String token, DateTime fetchedAt})> _tokenCache = {};
  static final Set<String> _inFlightIds = {};

  static GoogleSignIn _getSignIn(String senderEmail) {
    return _signInCache.putIfAbsent(senderEmail, () {
      final clientId = AppConfig.googleWebClientId;
      return GoogleSignIn(
        clientId: clientId.isNotEmpty ? clientId : null,
        scopes: ['email', 'https://www.googleapis.com/auth/gmail.send'],
        forceAccountName: senderEmail,
      );
    });
  }

  static bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  static Future<void> start() async {
    if (_isAndroid) {
      await AndroidAlarmManager.initialize();
      await AndroidAlarmManager.periodic(
        const Duration(minutes: 5),
        1,
        exactAlarmCallback,
        wakeup: true,
        rescheduleOnReboot: true,
      );
    }

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) async {
      await checkAndSendEmails();
    });
    await checkAndSendEmails();
  }

  static void scheduleExactAlarm(DateTime time, int id) {
    if (!_isAndroid) return;
    AndroidAlarmManager.oneShotAt(
      time,
      id,
      exactAlarmCallback,
      exact: true,
      wakeup: true,
      rescheduleOnReboot: true,
    );
  }

  static void scheduleExactAlarmForEmail(ScheduledEmail email) {
    try {
      final dt = DateHelpers.parseScheduleDateTime(email.scheduledDate, email.scheduledTime);
      final alarmId = email.id.hashCode.abs();
      final warmUpTime = dt.subtract(const Duration(minutes: 2));
      if (warmUpTime.isAfter(DateTime.now())) {
        scheduleExactAlarm(warmUpTime, (alarmId + 9999999) % 0x7FFFFFFF);
      }
      scheduleExactAlarm(dt, alarmId);
    } catch (_) {}
  }

  static void stop() {
    _timer?.cancel();
    if (_isAndroid) {
      AndroidAlarmManager.cancel(1);
    }
  }

  static Future<void> checkAndSendEmails() async {
    if (_isChecking) return;
    _isChecking = true;
    try {
      await _doCheck();
    } finally {
      _isChecking = false;
    }
  }

  static Future<void> _doCheck() async {
    final emails = await StorageService.getEmails();

    // Reset orphaned runs left in "Doing"/"Sending" for >10 minutes after an app kill.
    final nowEpoch = DateTime.now().millisecondsSinceEpoch;
    bool resetAny = false;
    for (final email in emails) {
      final isStuck = email.status.startsWith('Doing') || email.status.startsWith('Sending');
      if (isStuck &&
          !_inFlightIds.contains(email.id) &&
          nowEpoch - email.lastUpdateEpoch > 10 * 60 * 1000) {
        await StorageService.updateEmail(email.copyWith(status: 'Scheduled'));
        resetAny = true;
      }
    }

    final freshEmails = resetAny ? await StorageService.getEmails() : emails;
    final today = DateHelpers.todayDmy();
    final now = DateTime.now();
    final isWeekend = now.weekday == DateTime.saturday || now.weekday == DateTime.sunday;

    // Pick at most one due campaign per distinct sender so different senders run in parallel.
    final bySender = <String, ScheduledEmail>{};

    for (final email in freshEmails) {
      if (_inFlightIds.contains(email.id)) continue;
      if (email.status == 'Success' ||
          email.status == 'Failed' ||
          email.status == 'Paused' ||
          email.status.startsWith('Doing') ||
          email.status.startsWith('Sending') ||
          email.status.startsWith('Merge Day')) {
        continue;
      }

      if (isWeekend && !email.forceWeekend && email.status != 'Paused (Weekend)') {
        await StorageService.updateEmail(email.copyWith(status: 'Paused (Weekend)'));
        continue;
      }
      if (!isWeekend && email.status == 'Paused (Weekend)') {
        final batchSize = email.dailyLimit > 0 ? email.dailyLimit : 40;
        String newStatus = 'Scheduled';
        if (email.sentCount > 0) {
          final daysDone = (email.sentCount / batchSize).ceil();
          newStatus = 'Day $daysDone: ${email.sentCount}/${email.recipients.length} sent';
        }
        await StorageService.updateEmail(email.copyWith(status: newStatus, forceWeekend: false));
        continue;
      }
      if (email.status == 'Paused (Weekend)') continue;

      if (email.queuedAfter != null && email.queuedAfter!.isNotEmpty) {
        final blocker = freshEmails.firstWhere(
          (e) => e.id == email.queuedAfter,
          orElse: () => email,
        );
        if (blocker.id != email.id && blocker.status != 'Success' && blocker.status != 'Failed') {
          continue;
        }
        if (blocker.status == 'Success' || blocker.status == 'Failed') {
          await StorageService.updateEmail(email.copyWith(clearQueuedAfter: true));
          continue;
        }
      }

      if (_isTimeArrived(email.scheduledDate, email.scheduledTime) &&
          _isTimeOfDayArrived(email.scheduledTime) &&
          email.lastSentDate != today) {
        bySender.putIfAbsent(email.senderEmail, () => email);
      }
    }

    if (bySender.isEmpty) return;

    final parallelTotal = bySender.length + _inFlightIds.length;
    await Future.wait(bySender.values.map((email) => _launchCampaign(email, parallelTotal)));
  }

  static Future<void> _launchCampaign(ScheduledEmail email, int parallelCount) async {
    _inFlightIds.add(email.id);
    try {
      final token = await _getFreshToken(email.senderEmail);
      if (token == null || token.isEmpty) {
        final failed = email.copyWith(
          status: 'Failed: Please open the app and re-authenticate ${email.senderEmail}',
        );
        await StorageService.updateEmail(failed);
        await NotificationService.showSendingDoneNotification(
          failed,
          failed: true,
          parallelRemaining: max(0, _inFlightIds.length - 1),
        );
        return;
      }

      NotificationService.clearCampaignAlertState(email.id);
      await NotificationService.showSendingStartedNotification(
        email,
        parallelCount: parallelCount,
      );
      await _processEmailWithToken(email, token);
    } finally {
      _inFlightIds.remove(email.id);
    }
  }

  static Future<String?> _getFreshToken(String senderEmail) async {
    final cached = _tokenCache[senderEmail];
    if (cached != null && DateTime.now().difference(cached.fetchedAt) < _tokenCacheTtl) {
      return cached.token;
    }

    String? token;
    try {
      final googleSignIn = _getSignIn(senderEmail);
      final account = googleSignIn.currentUser ?? await googleSignIn.signInSilently();
      if (account != null && account.email == senderEmail) {
        final auth = await account.authentication;
        token = auth.accessToken;
        if (token != null && token.isNotEmpty) {
          _tokenCache[senderEmail] = (token: token, fetchedAt: DateTime.now());
          await StorageService.saveAccessToken(senderEmail, token);
          return token;
        }
      }
    } catch (_) {}

    token = await StorageService.getAccessToken(senderEmail);
    if (token != null && token.isNotEmpty) {
      _tokenCache[senderEmail] = (token: token, fetchedAt: DateTime.now());
    }
    return token;
  }

  static Future<String?> _forceRefreshToken(String senderEmail) async {
    _tokenCache.remove(senderEmail);
    try {
      final account = await _getSignIn(senderEmail).signInSilently();
      if (account != null && account.email == senderEmail) {
        final auth = await account.authentication;
        final token = auth.accessToken;
        if (token != null && token.isNotEmpty) {
          _tokenCache[senderEmail] = (token: token, fetchedAt: DateTime.now());
          await StorageService.saveAccessToken(senderEmail, token);
          return token;
        }
      }
    } catch (_) {}
    return null;
  }

  static Future<void> _processEmailWithToken(ScheduledEmail email, String token) async {
    try {
      if (email.type == 'Single' && !email.isMerged) {
        await _sendSingle(email, token);
      } else {
        await _sendBatch(email, token);
      }
    } catch (_) {}
  }

  static Future<Map<String, String>> _sendOneWithRetry(
    ScheduledEmail single,
    String token,
  ) async {
    String result = await MailService.sendEmailWithReason(emailConfig: single, accessToken: token);
    if (result.contains('401')) {
      final newToken = await _forceRefreshToken(single.senderEmail);
      if (newToken != null && newToken.isNotEmpty) {
        token = newToken;
        result = await MailService.sendEmailWithReason(emailConfig: single, accessToken: token);
      }
    }
    return {'result': result, 'token': token};
  }

  static Future<void> _sendSingle(ScheduledEmail email, String token) async {
    final recipient = email.recipients.isNotEmpty ? email.recipients[0] : '';
    final statuses = Map<String, String>.from(email.recipientStatuses);
    if (recipient.isNotEmpty) statuses[recipient] = 'inProcess';
    final started = email.copyWith(status: 'Sending...', recipientStatuses: statuses);
    await StorageService.updateEmail(started);
    await NotificationService.showSendingProgressNotification(
      started,
      parallelCount: max(1, _inFlightIds.length),
    );

    final single = email.copyWith(recipients: [recipient]);
    final retryResult = await _sendOneWithRetry(single, token);
    final result = retryResult['result']!;
    final success = result == 'Success';

    if (recipient.isNotEmpty) statuses[recipient] = success ? 'sent' : 'failed';
    final finished = email.copyWith(
      status: success ? 'Success' : 'Failed: $result',
      sentCount: success ? 1 : 0,
      recipientStatuses: statuses,
    );
    await StorageService.updateEmail(finished);
    await NotificationService.showSendingDoneNotification(
      finished,
      failed: !success,
      parallelRemaining: max(0, _inFlightIds.length - 1),
    );
  }

  static Future<void> _sendBatch(ScheduledEmail email, String token) async {
    final total = email.recipients.length;
    final batchSize = email.dailyLimit > 0 ? email.dailyLimit : total;
    final startIdx = email.sentCount;
    final endIdx = (email.isMerged || email.type == 'PDF') ? min(startIdx + batchSize, total) : total;
    final today = DateHelpers.todayDmy();
    final statuses = Map<String, String>.from(email.recipientStatuses);

    for (final r in email.recipients) {
      statuses.putIfAbsent(r, () => 'pending');
    }

    String statusLabel(int index, String verb) {
      if (email.isMerged) {
        final day = ((index + 1) / batchSize).ceil();
        return 'Merge Day $day: ${index + 1}/$total $verb';
      }
      return 'Doing it... (${index + 1}/$total)';
    }

    for (int i = startIdx; i < endIdx; i++) {
      final latestList = await StorageService.getEmails();
      final cur = latestList.firstWhere((e) => e.id == email.id, orElse: () => email);
      if (cur.status == 'Paused') return;

      final recipient = email.recipients[i];
      if (await StorageService.getDailySentCount(email.senderEmail) >= 50) {
        statuses[recipient] = 'pending';
        break;
      }

      statuses[recipient] = 'inProcess';
      final sendingState = cur.copyWith(
        status: statusLabel(i, 'sending...'),
        sentCount: i,
        recipientStatuses: Map.from(statuses),
      );
      await StorageService.updateEmail(sendingState);
      await NotificationService.showSendingProgressNotification(
        sendingState,
        parallelCount: max(1, _inFlightIds.length),
      );

      final single = email.copyWith(recipients: [recipient]);
      String result;
      bool success = false;
      try {
        final retryResult = await _sendOneWithRetry(single, token);
        result = retryResult['result']!;
        token = retryResult['token']!;
        success = result == 'Success';
      } catch (e) {
        result = 'Error: $e';
      }

      if (success) {
        statuses[recipient] = 'sent';
        await StorageService.incrementDailySentCount(email.senderEmail);
      } else {
        statuses[recipient] = 'failed ($result)';
      }

      final afterState = cur.copyWith(
        status: statusLabel(i, 'sent'),
        sentCount: i + 1,
        recipientStatuses: Map.from(statuses),
      );
      await StorageService.updateEmail(afterState);
      await NotificationService.showSendingProgressNotification(
        afterState,
        parallelCount: max(1, _inFlightIds.length),
      );

      if (email.delayMinutes > 0 && i < endIdx - 1) {
        await Future.delayed(Duration(minutes: email.delayMinutes));
      }
    }

    final latestList = await StorageService.getEmails();
    final cur = latestList.firstWhere((e) => e.id == email.id, orElse: () => email);
    if (cur.status == 'Paused') return;

    final finalCount = cur.sentCount;
    if (finalCount >= total) {
      final completed = cur.copyWith(
        status: 'Success',
        lastSentDate: today,
        recipientStatuses: Map.from(statuses),
      );
      await StorageService.updateEmail(completed);
      await NotificationService.showSendingDoneNotification(
        completed,
        parallelRemaining: max(0, _inFlightIds.length - 1),
      );
      return;
    }

    final daysDone = batchSize > 0 ? (finalCount / batchSize).ceil() : 1;
    final String dayStatus;
    if (email.isMerged) {
      final mergeLabel = email.mergeContributions.entries
          .map((e) => '${email.mergeSourceNames[e.key] ?? e.key}: ${e.value}/day')
          .join(' | ');
      dayStatus = 'Merge Day $daysDone: $finalCount/$total sent [$mergeLabel]';
    } else if (email.type == 'PDF') {
      dayStatus = 'Day $daysDone: $finalCount/$total sent. Resumes tomorrow.';
    } else {
      dayStatus = 'Limit Reached: Day $daysDone ($finalCount/$total sent). Resumes tomorrow.';
    }

    final partial = cur.copyWith(
      status: dayStatus,
      lastSentDate: today,
      recipientStatuses: Map.from(statuses),
    );
    await StorageService.updateEmail(partial);
    await NotificationService.showSendingDoneNotification(
      partial,
      parallelRemaining: max(0, _inFlightIds.length - 1),
    );
  }

  static bool _isTimeArrived(String dateString, String timeString) {
    if (DateHelpers.parseDmy(dateString) == null || timeString.isEmpty) return false;
    try {
      final scheduled = DateHelpers.parseScheduleDateTime(dateString, timeString);
      return !scheduled.isAfter(DateTime.now());
    } catch (_) {
      return false;
    }
  }

  static bool _isTimeOfDayArrived(String timeString) {
    if (timeString.isEmpty) return false;
    try {
      final scheduled = DateHelpers.parseScheduleDateTime(DateHelpers.todayDmy(), timeString);
      final now = DateTime.now();
      return (now.hour * 60 + now.minute) >= (scheduled.hour * 60 + scheduled.minute);
    } catch (_) {
      return false;
    }
  }

  static void registerSignedInAccount(GoogleSignInAccount account) {
    _signInCache[account.email] = _getSignIn(account.email);
  }
}
