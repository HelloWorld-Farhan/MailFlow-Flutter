import 'dart:async';
import 'dart:math';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'storage_service.dart';
import 'mail_service.dart';
import '../models/scheduled_email.dart';

import 'package:flutter/widgets.dart';

@pragma('vm:entry-point')
void exactAlarmCallback() async {
  WidgetsFlutterBinding.ensureInitialized();
  await BackgroundDispatcher.checkAndSendEmails();
}

class BackgroundDispatcher {
  static Timer? _timer;
  static bool _isChecking = false;

  // Cache of per-sender GoogleSignIn instances
  static final Map<String, GoogleSignIn> _signInCache = {};

  static GoogleSignIn _getSignIn(String senderEmail) {
    if (!_signInCache.containsKey(senderEmail)) {
      _signInCache[senderEmail] = GoogleSignIn(
        clientId: '787471915530-sg4ul6fm6s1paqabljmksi9c61cf4c77.apps.googleusercontent.com',
        scopes: ['email', 'https://www.googleapis.com/auth/gmail.send'],
        forceAccountName: senderEmail,
      );
    }
    return _signInCache[senderEmail]!;
  }

  static Future<void> start() async {
    print('Starting Background Dispatcher...');
    await AndroidAlarmManager.initialize();
    
    // Register a periodic fallback every 5 minutes to catch any missed alarms
    await AndroidAlarmManager.periodic(
      const Duration(minutes: 5),
      1,
      exactAlarmCallback,
      wakeup: true,
      rescheduleOnReboot: true,
    );

    _timer?.cancel();
    // Poll every 5 seconds so the app reacts within 5 seconds of the scheduled time
    _timer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      await checkAndSendEmails();
    });
    // Also run immediately on start
    await checkAndSendEmails();
  }

  static void scheduleExactAlarm(DateTime time, int id) {
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
      final parts = email.scheduledDate.split('/');
      if (parts.length == 3) {
        final day = int.parse(parts[0]);
        final month = int.parse(parts[1]);
        final year = int.parse(parts[2]);
        
        final tParts = email.scheduledTime.split(' ');
        final hm = tParts[0].split(':');
        int hour = int.parse(hm[0]);
        final min = int.parse(hm[1]);
        if (tParts[1] == 'PM' && hour < 12) hour += 12;
        if (tParts[1] == 'AM' && hour == 12) hour = 0;

        final dt = DateTime(year, month, day, hour, min);
        final alarmId = email.id.hashCode.abs();

        // Schedule a warm-up alarm 2 minutes BEFORE the actual send time
        // so the system is alive and ready exactly at send time.
        final warmUpTime = dt.subtract(const Duration(minutes: 2));
        if (warmUpTime.isAfter(DateTime.now())) {
          // Warm-up alarm uses a different ID (alarmId + offset)
          scheduleExactAlarm(warmUpTime, (alarmId + 9999999) % 0x7FFFFFFF);
          print('Scheduled warm-up alarm for $warmUpTime');
        }

        // Main alarm at the exact send time
        scheduleExactAlarm(dt, alarmId);
        print('Scheduled exact alarm for $dt (ID: $alarmId)');
      }
    } catch (e) {
      print('Failed to schedule exact alarm: $e');
    }
  }

  static void stop() {
    _timer?.cancel();
    AndroidAlarmManager.cancel(1);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  MAIN ENTRY POINT — called every 5 seconds by timer & by alarm callbacks
  // ═══════════════════════════════════════════════════════════════════════════
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

    // ── Stuck Email Watchdog ───────────────────────────────────────────────
    // If an email has been stuck in "Doing" or "Sending" status for more than
    // 10 minutes (app was killed mid-send), auto-reset it so it can retry.
    final nowEpoch = DateTime.now().millisecondsSinceEpoch;
    for (final email in emails) {
      final isStuck = email.status.startsWith('Doing') || email.status.startsWith('Sending');
      
      if (isStuck) {
        final timeSinceLastUpdate = nowEpoch - email.lastUpdateEpoch;
        final isOrphaned = timeSinceLastUpdate > 10 * 60 * 1000; // 10 minutes

        if (isOrphaned) {
          print('Watchdog: Resetting stuck email ${email.id} (status: ${email.status}, inactive for ${timeSinceLastUpdate / 1000}s)');
          await StorageService.updateEmail(email.copyWith(status: 'Scheduled'));
        }
      }
    }

    // Reload after watchdog fixes
    final freshEmails = await StorageService.getEmails();

    // ── Process emails SEQUENTIALLY (one schedule at a time) ──────────────
    for (final email in freshEmails) {
      if (email.status == 'Success') continue;
      if (email.status == 'Failed') continue;
      if (email.status == 'Paused') continue;
      if (email.status.startsWith('Doing')) continue;
      if (email.status.startsWith('Sending')) continue;
      if (email.status.startsWith('Merge Day')) continue;

      // ── Queue-After check ─────────────────────────────────────────────
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

      if (_isTimeArrived(email.scheduledDate, email.scheduledTime)) {
        if ((email.type == 'PDF' || email.isMerged) && email.dailyLimit > 0) {
          final today = _todayString();
          if (email.lastSentDate == today) continue;
        }

        // ── Get a valid token for this sender ──────────────────────────
        final token = await _getFreshToken(email.senderEmail);
        if (token == null || token.isEmpty) {
          print('Dispatcher: No token available for ${email.senderEmail}. User must re-authenticate.');
          await StorageService.updateEmail(email.copyWith(
            status: 'Failed: Please open the app and re-authenticate ${email.senderEmail}',
          ));
          continue;
        }

        // ── Process this one email schedule fully ──────────────────────
        await _processEmailWithToken(email, token);
        // After processing one schedule, break out and let the next timer
        // tick pick up the next schedule. This prevents Android from killing
        // a long-running loop that tries to process everything at once.
        // NOTE: For Single emails this is fast so we continue the loop.
        if (email.type != 'Single') {
          break;
        }
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  TOKEN MANAGEMENT — sequential, no races
  // ═══════════════════════════════════════════════════════════════════════════
  static Future<String?> _getFreshToken(String senderEmail) async {
    String? token;
    try {
      final googleSignIn = _getSignIn(senderEmail);
      GoogleSignInAccount? account = googleSignIn.currentUser;
      if (account == null) {
        print('Dispatcher: currentUser is null, attempting signInSilently for $senderEmail');
        account = await googleSignIn.signInSilently();
      }
      if (account != null && account.email == senderEmail) {
        final auth = await account.authentication;
        token = auth.accessToken;
        if (token != null) {
          await StorageService.saveAccessToken(senderEmail, token);
          print('Dispatcher: Token refreshed via signInSilently');
        }
      }
    } catch (e) {
      print('Dispatcher: signInSilently failed: $e');
    }

    if (token == null || token.isEmpty) {
      token = await StorageService.getAccessToken(senderEmail);
      print('Dispatcher: Using stored token for $senderEmail: ${token != null ? "found" : "NOT FOUND"}');
    }
    return token;
  }

  /// Force-refresh the token (used after a 401 error)
  static Future<String?> _forceRefreshToken(String senderEmail) async {
    print('Dispatcher: Force-refreshing token for $senderEmail');
    try {
      final googleSignIn = _getSignIn(senderEmail);
      // Disconnect and re-sign-in to get a brand new token
      await googleSignIn.signOut();
      final account = await googleSignIn.signInSilently();
      if (account != null && account.email == senderEmail) {
        final auth = await account.authentication;
        final token = auth.accessToken;
        if (token != null) {
          await StorageService.saveAccessToken(senderEmail, token);
          print('Dispatcher: Token force-refreshed successfully');
          return token;
        }
      }
    } catch (e) {
      print('Dispatcher: Force-refresh failed: $e');
    }
    return null;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  EMAIL PROCESSING — dispatch to the right handler
  // ═══════════════════════════════════════════════════════════════════════════
  static Future<void> _processEmailWithToken(ScheduledEmail email, String token) async {
    try {
      if (email.isMerged) {
        await _sendMergedPdfBatch(email, token);
      } else if (email.type == 'Single') {
        await _sendSingle(email, token);
      } else if (email.type == 'Multiple') {
        await _sendMultiple(email, token);
      } else if (email.type == 'PDF') {
        await _sendPdfBatch(email, token);
      }
    } catch (e) {
      print('Dispatcher error: ' + e.toString());
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  SEND WITH RETRY — sends one email, retries once on 401
  // ═══════════════════════════════════════════════════════════════════════════
  /// Sends a single email to one recipient. On 401, force-refreshes the token
  /// and retries once. Returns the result string and the (possibly new) token.
  static Future<Map<String, String>> _sendOneWithRetry(
    ScheduledEmail single,
    String token,
  ) async {
    String result = await MailService.sendEmailWithReason(emailConfig: single, accessToken: token);

    // If 401, force refresh and retry once
    if (result.contains('401')) {
      print('Dispatcher: Got 401, attempting token refresh for ${single.senderEmail}');
      final newToken = await _forceRefreshToken(single.senderEmail);
      if (newToken != null && newToken.isNotEmpty) {
        token = newToken;
        result = await MailService.sendEmailWithReason(emailConfig: single, accessToken: token);
      }
    }

    return {'result': result, 'token': token};
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  SINGLE EMAIL
  // ═══════════════════════════════════════════════════════════════════════════
  static Future<void> _sendSingle(ScheduledEmail email, String token) async {
    final recipient = email.recipients.isNotEmpty ? email.recipients[0] : '';
    final statuses = Map<String, String>.from(email.recipientStatuses);
    if (recipient.isNotEmpty) statuses[recipient] = 'inProcess';
    await StorageService.updateEmail(email.copyWith(status: 'Sending...', recipientStatuses: statuses));
    
    final single = email.copyWith(recipients: [recipient]);
    final retryResult = await _sendOneWithRetry(single, token);
    final result = retryResult['result']!;
    final success = result == 'Success';
    
    if (success) {
      if (recipient.isNotEmpty) statuses[recipient] = 'sent';
      await StorageService.updateEmail(email.copyWith(
        status: 'Success',
        recipientStatuses: statuses,
      ));
      print('Dispatcher: Single email sent to $recipient');
    } else {
      if (recipient.isNotEmpty) statuses[recipient] = 'failed';
      await StorageService.updateEmail(email.copyWith(
        status: 'Failed: $result',
        recipientStatuses: statuses,
      ));
      print('Dispatcher: Single email FAILED to $recipient: $result');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  MULTIPLE EMAILS (bulk list) — sequential, send-then-count
  // ═══════════════════════════════════════════════════════════════════════════
  static Future<void> _sendMultiple(ScheduledEmail email, String token) async {
    final total = email.recipients.length;
    final startIdx = email.sentCount;
    final today = _todayString();
    final statuses = Map<String, String>.from(email.recipientStatuses);

    // Initialize pending statuses for any new recipients
    for (final r in email.recipients) {
      if (!statuses.containsKey(r)) statuses[r] = 'pending';
    }

    print('Dispatcher: Starting Multiple send for ${email.id} from index $startIdx/$total');

    for (int i = startIdx; i < total; i++) {
      // Re-read from storage to check for pause
      final latestList = await StorageService.getEmails();
      final cur = latestList.firstWhere((e) => e.id == email.id, orElse: () => email);
      if (cur.status == 'Paused') {
        print('Dispatcher: Email ${email.id} paused at $i/$total');
        return;
      }

      final recipient = email.recipients[i];
      statuses[recipient] = 'inProcess';

      // Update status BEFORE send (shows progress) but do NOT increment sentCount yet
      await StorageService.updateEmail(cur.copyWith(
        status: 'Doing it... (${i + 1}/$total)',
        sentCount: i, // still at i, not i+1 — we haven't sent yet
        recipientStatuses: Map.from(statuses),
      ));

      // Actually send the email
      final single = email.copyWith(recipients: [recipient]);
      final retryResult = await _sendOneWithRetry(single, token);
      final result = retryResult['result']!;
      token = retryResult['token']!; // update token in case it was refreshed
      final success = result == 'Success';

      if (success) {
        statuses[recipient] = 'sent';
        print('Dispatcher: [$i/${total}] Sent to $recipient');
      } else {
        statuses[recipient] = 'failed ($result)';
        print('Dispatcher: [$i/${total}] FAILED to $recipient: $result');
      }

      // NOW increment sentCount — only after the send attempt completed
      await StorageService.updateEmail(cur.copyWith(
        status: 'Doing it... (${i + 1}/$total)',
        sentCount: i + 1,
        recipientStatuses: Map.from(statuses),
      ));

      // Anti-spam delay between each email
      if (email.delayMinutes > 0 && i < total - 1) {
        print('Dispatcher: Waiting ${email.delayMinutes} min before next email...');
        await Future.delayed(Duration(minutes: email.delayMinutes));
      }
    }

    // All done — mark success
    final latestList = await StorageService.getEmails();
    final cur = latestList.firstWhere((e) => e.id == email.id, orElse: () => email);
    if (cur.status == 'Paused') return;

    await StorageService.updateEmail(cur.copyWith(
      status: 'Success',
      sentCount: total,
      lastSentDate: today,
      recipientStatuses: Map.from(statuses),
    ));
    print('Dispatcher: Multiple email ${email.id} completed — $total/$total sent');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  PDF BATCH — sequential, send-then-count
  // ═══════════════════════════════════════════════════════════════════════════
  static Future<void> _sendPdfBatch(ScheduledEmail email, String token) async {
    final total = email.recipients.length;
    final batchSize = email.dailyLimit > 0 ? email.dailyLimit : total; // no limit if dailyLimit=0
    final startIdx = email.sentCount;
    final endIdx = min(startIdx + batchSize, total);
    final today = _todayString();
    final statuses = Map<String, String>.from(email.recipientStatuses);

    for (final r in email.recipients) {
      if (!statuses.containsKey(r)) statuses[r] = 'pending';
    }

    print('Dispatcher: Starting PDF batch for ${email.id} from $startIdx to $endIdx (total: $total)');

    for (int i = startIdx; i < endIdx; i++) {
      final latestList = await StorageService.getEmails();
      final cur = latestList.firstWhere((e) => e.id == email.id, orElse: () => email);
      if (cur.status == 'Paused') {
        print('Dispatcher: PDF batch ${email.id} paused at $i/$total');
        return;
      }

      final recipient = email.recipients[i];
      statuses[recipient] = 'inProcess';

      await StorageService.updateEmail(cur.copyWith(
        status: 'Doing it... (${i + 1}/$total)',
        sentCount: i,
        recipientStatuses: Map.from(statuses),
      ));

      final single = email.copyWith(recipients: [recipient]);
      final retryResult = await _sendOneWithRetry(single, token);
      final result = retryResult['result']!;
      token = retryResult['token']!;
      final success = result == 'Success';

      if (success) {
        statuses[recipient] = 'sent';
        print('Dispatcher: PDF [$i/$total] Sent to $recipient');
      } else {
        statuses[recipient] = 'failed ($result)';
        print('Dispatcher: PDF [$i/$total] FAILED to $recipient: $result');
      }

      // Increment sentCount AFTER send
      await StorageService.updateEmail(cur.copyWith(
        status: 'Doing it... (${i + 1}/$total)',
        sentCount: i + 1,
        recipientStatuses: Map.from(statuses),
      ));

      if (email.delayMinutes > 0 && i < endIdx - 1) {
        print('Dispatcher: Waiting ${email.delayMinutes} min before next PDF email...');
        await Future.delayed(Duration(minutes: email.delayMinutes));
      }
    }

    final latestList = await StorageService.getEmails();
    final cur = latestList.firstWhere((e) => e.id == email.id, orElse: () => email);
    if (cur.status == 'Paused') return;

    final newCount = endIdx;
    if (newCount >= total) {
      await StorageService.updateEmail(cur.copyWith(
        status: 'Success',
        sentCount: newCount,
        lastSentDate: today,
        recipientStatuses: Map.from(statuses),
      ));
      print('Dispatcher: PDF batch ${email.id} completed — $total/$total sent');
    } else {
      final daysDone = (newCount / batchSize).ceil();
      final dayStatus = 'Day $daysDone: $newCount/$total sent. Resumes tomorrow.';
      await StorageService.updateEmail(cur.copyWith(
        status: dayStatus,
        sentCount: newCount,
        lastSentDate: today,
        recipientStatuses: Map.from(statuses),
      ));
      print('Dispatcher: PDF batch ${email.id} day done — $newCount/$total sent');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  MERGED PDF BATCH — sequential, send-then-count
  // ═══════════════════════════════════════════════════════════════════════════
  static Future<void> _sendMergedPdfBatch(ScheduledEmail email, String token) async {
    final total = email.recipients.length;
    final dailyLimit = email.dailyLimit > 0 ? email.dailyLimit : total;
    final startIdx = email.sentCount;
    final endIdx = min(startIdx + dailyLimit, total);
    final today = _todayString();
    final statuses = Map<String, String>.from(email.recipientStatuses);

    for (final r in email.recipients) {
      if (!statuses.containsKey(r)) statuses[r] = 'pending';
    }

    // Build today's contribution breakdown for status display
    final contributions = email.mergeContributions;
    final names = email.mergeSourceNames;
    String mergeLabel = '';
    if (contributions.isNotEmpty) {
      mergeLabel = contributions.entries
          .map((e) => '${names[e.key] ?? e.key}: ${e.value}/day')
          .join(' | ');
    }

    print('Dispatcher: Starting Merged PDF for ${email.id} from $startIdx to $endIdx (total: $total)');

    for (int i = startIdx; i < endIdx; i++) {
      final latestList = await StorageService.getEmails();
      final cur = latestList.firstWhere((e) => e.id == email.id, orElse: () => email);
      if (cur.status == 'Paused') {
        print('Dispatcher: Merged PDF ${email.id} paused at $i/$total');
        return;
      }

      final recipient = email.recipients[i];
      statuses[recipient] = 'inProcess';

      await StorageService.updateEmail(cur.copyWith(
        status: 'Merge Day ${((i + 1) / dailyLimit).ceil()}: ${i + 1}/$total sending...',
        sentCount: i,
        recipientStatuses: Map.from(statuses),
      ));

      final single = email.copyWith(recipients: [recipient]);
      final retryResult = await _sendOneWithRetry(single, token);
      final result = retryResult['result']!;
      token = retryResult['token']!;
      final success = result == 'Success';

      if (success) {
        statuses[recipient] = 'sent';
        print('Dispatcher: Merged [$i/$total] Sent to $recipient');
      } else {
        statuses[recipient] = 'failed ($result)';
        print('Dispatcher: Merged [$i/$total] FAILED to $recipient: $result');
      }

      // Increment sentCount AFTER send
      await StorageService.updateEmail(cur.copyWith(
        status: 'Merge Day ${((i + 1) / dailyLimit).ceil()}: ${i + 1}/$total sent',
        sentCount: i + 1,
        recipientStatuses: Map.from(statuses),
      ));

      if (email.delayMinutes > 0 && i < endIdx - 1) {
        await Future.delayed(Duration(minutes: email.delayMinutes));
      }
    }

    final latestList = await StorageService.getEmails();
    final cur = latestList.firstWhere((e) => e.id == email.id, orElse: () => email);
    if (cur.status == 'Paused') return;

    final newCount = endIdx;
    if (newCount >= total) {
      await StorageService.updateEmail(cur.copyWith(
        status: 'Success',
        sentCount: newCount,
        lastSentDate: today,
        recipientStatuses: Map.from(statuses),
      ));
      print('Dispatcher: Merged PDF ${email.id} completed — $total/$total sent');
    } else {
      final daysDone = (newCount / dailyLimit).ceil();
      final dayStatus = 'Merge Day $daysDone: $newCount/$total sent [$mergeLabel]';
      await StorageService.updateEmail(cur.copyWith(
        status: dayStatus,
        sentCount: newCount,
        lastSentDate: today,
        recipientStatuses: Map.from(statuses),
      ));
      print('Dispatcher: Merged PDF ${email.id} day done — $newCount/$total sent');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  HELPERS
  // ═══════════════════════════════════════════════════════════════════════════
  static String _todayString() {
    final now = DateTime.now();
    return now.day.toString().padLeft(2, '0') + '/' + now.month.toString().padLeft(2, '0') + '/' + now.year.toString();
  }

  static bool _isTimeArrived(String dateString, String timeString) {
    if (dateString.length != 10 || timeString.isEmpty) return false;
    try {
      int day = int.parse(dateString.substring(0, 2));
      int month = int.parse(dateString.substring(3, 5));
      int year = int.parse(dateString.substring(6, 10));
      final isAm = timeString.contains('AM');
      final rawTime = timeString.replaceAll(RegExp(r' AM| PM'), '');
      int hour = int.parse(rawTime.substring(0, 2));
      int minute = int.parse(rawTime.substring(3, 5));
      if (!isAm && hour != 12) hour += 12;
      if (isAm && hour == 12) hour = 0;
      final scheduled = DateTime(year, month, day, hour, minute);
      return scheduled.isBefore(DateTime.now()) || scheduled.isAtSameMomentAs(DateTime.now());
    } catch (e) {
      return false;
    }
  }

  // Called from UI after auth to cache the signed-in account
  static void registerSignedInAccount(GoogleSignInAccount account) {
    final googleSignIn = _getSignIn(account.email);
    _signInCache[account.email] = googleSignIn;
  }
}
