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
  static final Set<String> _activelySending = {};

  // In-memory daily sent count cache — prevents race conditions when two
  // senders run in parallel and both read/write SharedPreferences simultaneously.
  static final Map<String, int> _dailyCountCache = {};
  static String _cacheDate = '';

  static Future<int> _getDailyCount(String senderEmail) async {
    final today = _todayString();
    if (_cacheDate != today) {
      // New day — clear the cache
      _dailyCountCache.clear();
      _cacheDate = today;
    }
    if (_dailyCountCache.containsKey(senderEmail)) {
      return _dailyCountCache[senderEmail]!;
    }
    final count = await StorageService.getDailySentCount(senderEmail);
    _dailyCountCache[senderEmail] = count;
    return count;
  }

  static Future<void> _incrementDailyCount(String senderEmail) async {
    final today = _todayString();
    if (_cacheDate != today) {
      _dailyCountCache.clear();
      _cacheDate = today;
    }
    _dailyCountCache[senderEmail] = (_dailyCountCache[senderEmail] ?? 0) + 1;
    await StorageService.incrementDailySentCount(senderEmail);
  }

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

  static Future<void> checkAndSendEmails() async {
    final emails = await StorageService.getEmails();

    // ── Stuck Email Watchdog ───────────────────────────────────────────────
    // If an email has been stuck in "Doing" or "Sending" status for more than
    // 10 minutes (app was killed mid-send), auto-reset it so it can retry.
    for (final email in emails) {
      final isStuck = email.status.startsWith('Doing') || email.status.startsWith('Sending');
      if (isStuck && !_activelySending.contains(email.id)) {
        // This email is marked as sending but we are NOT actively processing it
        // — it got stuck after a crash or force-close. Reset it.
        print('Watchdog: Resetting stuck email ${email.id} (status: ${email.status})');
        await StorageService.updateEmail(email.copyWith(status: 'Scheduled'));
      }
    }

    // Reload after watchdog fixes
    final freshEmails = await StorageService.getEmails();
    final List<Future<void>> toSend = [];

    for (final email in freshEmails) {
      if (email.status == 'Success') continue;
      if (email.status == 'Failed') continue;
      if (email.status == 'Paused') continue;
      if (email.status.startsWith('Doing')) continue;
      if (email.status.startsWith('Sending')) continue;
      if (email.status.startsWith('Merge Day')) continue;
      if (_activelySending.contains(email.id)) continue;

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
        _activelySending.add(email.id);
        toSend.add(
          _processEmail(email).then((_) => _activelySending.remove(email.id))
        );
      }
    }

    if (toSend.isNotEmpty) {
      await Future.wait(toSend);
    }
  }

  static Future<void> _processEmail(ScheduledEmail email) async {
    try {
      String? token;

      // Step 1: Try to get token from in-memory cache or by signing in silently
      final googleSignIn = _getSignIn(email.senderEmail);
      GoogleSignInAccount? account = googleSignIn.currentUser;
      
      if (account == null) {
        try {
          print('Dispatcher: currentUser is null, attempting signInSilently for ${email.senderEmail}');
          account = await googleSignIn.signInSilently();
        } catch (e) {
          print('Dispatcher: signInSilently failed: $e');
        }
      }

      if (account != null && account.email == email.senderEmail) {
        try {
          final auth = await account.authentication;
          token = auth.accessToken;
          // Refresh stored token too
          if (token != null) {
            await StorageService.saveAccessToken(email.senderEmail, token);
            print('Dispatcher: Token refreshed via signInSilently');
          }
        } catch (e) {
          print('Dispatcher: account.authentication failed: $e');
        }
      }

      // Step 2: If in-memory/silent failed, use the saved token from SharedPreferences
      if (token == null || token.isEmpty) {
        token = await StorageService.getAccessToken(email.senderEmail);
        print('Dispatcher: Using stored token for ${email.senderEmail}: ${token != null ? "found" : "NOT FOUND"}');
      }

      if (token == null || token.isEmpty) {
        print('Dispatcher: No token available for ${email.senderEmail}. User must re-authenticate in app.');
        await StorageService.updateEmail(email.copyWith(
          status: 'Failed: Please open the app and re-authenticate ${email.senderEmail}',
        ));
        return;
      }

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

  static Future<void> _sendSingle(ScheduledEmail email, String token) async {
    if (await _getDailyCount(email.senderEmail) >= 50) {
      await StorageService.updateEmail(email.copyWith(status: 'Daily limit reached. Resumes tomorrow.'));
      return;
    }
    final recipient = email.recipients.isNotEmpty ? email.recipients[0] : '';
    final statuses = Map<String, String>.from(email.recipientStatuses);
    if (recipient.isNotEmpty) statuses[recipient] = 'inProcess';
    await StorageService.updateEmail(email.copyWith(status: 'Sending...', recipientStatuses: statuses));
    
    String finalStatus = '';
    final result = await MailService.sendEmailWithReason(emailConfig: email, accessToken: token);
    final success = result == 'Success';
    
    if (success) {
      await _incrementDailyCount(email.senderEmail);
      if (recipient.isNotEmpty) statuses[recipient] = 'sent';
      finalStatus = 'Success';
    } else {
      if (recipient.isNotEmpty) statuses[recipient] = 'failed';
      finalStatus = 'Failed: $result';
    }
    await StorageService.updateEmail(email.copyWith(
      status: finalStatus,
      recipientStatuses: statuses,
    ));
  }

  static Future<void> _sendMultiple(ScheduledEmail email, String token) async {
    final total = email.recipients.length;
    final statuses = Map<String, String>.from(email.recipientStatuses);
    int sentThisRun = 0;
    for (final r in email.recipients) {
      if (!statuses.containsKey(r)) statuses[r] = 'pending';
    }
    for (int i = 0; i < total; i++) {
      if (await _getDailyCount(email.senderEmail) >= 50) break;
      final recipient = email.recipients[i];
      statuses[recipient] = 'inProcess';
      final st = 'Doing it... (${i + 1}/$total)';
      await StorageService.updateEmail(email.copyWith(status: st, recipientStatuses: Map.from(statuses)));
      final single = email.copyWith(recipients: [recipient]);
      
      final result = await MailService.sendEmailWithReason(emailConfig: single, accessToken: token);
      final success = result == 'Success';
      
      if (success) {
        await _incrementDailyCount(email.senderEmail);
        statuses[recipient] = 'sent';
        sentThisRun++;
      } else {
        statuses[recipient] = 'failed ($result)';
      }
      // Anti-spam delay between each email (if user configured it)
      if (email.delayMinutes > 0 && i < total - 1) {
        await Future.delayed(Duration(minutes: email.delayMinutes));
      }
    }
    final allSent = statuses.values.every((s) => s == 'sent');
    await StorageService.updateEmail(email.copyWith(
      status: allSent ? 'Success' : 'Day 1: $sentThisRun/$total sent',
      recipientStatuses: Map.from(statuses),
    ));
  }

  static Future<void> _sendPdfBatch(ScheduledEmail email, String token) async {
    final total = email.recipients.length;
    final batchSize = email.dailyLimit > 0 ? email.dailyLimit : 40;
    final startIdx = email.sentCount;
    final endIdx = min(startIdx + batchSize, total);
    final today = _todayString();
    int newCount = startIdx;
    final statuses = Map<String, String>.from(email.recipientStatuses);
    for (final r in email.recipients) {
      if (!statuses.containsKey(r)) statuses[r] = 'pending';
    }
    for (int i = startIdx; i < endIdx; i++) {
      if (await _getDailyCount(email.senderEmail) >= 50) break;
      final latestList = await StorageService.getEmails();
      final cur = latestList.firstWhere((e) => e.id == email.id, orElse: () => email);
      if (cur.status == 'Paused') return;
      final recipient = email.recipients[i];
      statuses[recipient] = 'inProcess';
      newCount = i + 1;
      final st = 'Doing it... ($newCount/$total)';
      await StorageService.updateEmail(cur.copyWith(status: st, sentCount: newCount, recipientStatuses: Map.from(statuses)));
      final single = email.copyWith(recipients: [recipient]);
      
      final result = await MailService.sendEmailWithReason(emailConfig: single, accessToken: token);
      final success = result == 'Success';
      
      if (success) {
        await _incrementDailyCount(email.senderEmail);
        statuses[recipient] = 'sent';
      } else {
        statuses[recipient] = 'failed ($result)';
      }
      // Anti-spam delay between each email
      if (email.delayMinutes > 0 && i < endIdx - 1) {
        await Future.delayed(Duration(minutes: email.delayMinutes));
      }
    }
    final latestList = await StorageService.getEmails();
    final cur = latestList.firstWhere((e) => e.id == email.id, orElse: () => email);
    if (cur.status == 'Paused') return;

    if (newCount >= total) {
      await StorageService.updateEmail(cur.copyWith(status: 'Success', sentCount: newCount, lastSentDate: today, recipientStatuses: Map.from(statuses)));
    } else {
      final daysDone = (newCount / batchSize).ceil();
      final dayStatus = 'Day $daysDone: $newCount/$total sent. Resumes tomorrow.';
      await StorageService.updateEmail(cur.copyWith(status: dayStatus, sentCount: newCount, lastSentDate: today, recipientStatuses: Map.from(statuses)));
    }
  }

  // ── Merged PDF Batch Sending ────────────────────────────────────────────
  // Recipients are interleaved: first N from source-A, then M from source-B
  // based on mergeContributions map. Proportional split per day.
  static Future<void> _sendMergedPdfBatch(ScheduledEmail email, String token) async {
    final total = email.recipients.length;
    final dailyLimit = email.dailyLimit > 0 ? email.dailyLimit : 40;
    final startIdx = email.sentCount;
    final endIdx = min(startIdx + dailyLimit, total);
    final today = _todayString();
    int newCount = startIdx;
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

    for (int i = startIdx; i < endIdx; i++) {
      if (await _getDailyCount(email.senderEmail) >= 50) break;
      final latestList = await StorageService.getEmails();
      final cur = latestList.firstWhere((e) => e.id == email.id, orElse: () => email);
      if (cur.status == 'Paused') return;
      final recipient = email.recipients[i];
      statuses[recipient] = 'inProcess';
      newCount = i + 1;
      final st = 'Merge Day ${(newCount / dailyLimit).ceil()}: $newCount/$total sent';
      await StorageService.updateEmail(cur.copyWith(
        status: st,
        sentCount: newCount,
        recipientStatuses: Map.from(statuses),
      ));
      final single = email.copyWith(recipients: [recipient]);
      final success = await MailService.sendEmail(emailConfig: single, accessToken: token);
      if (success) {
        await _incrementDailyCount(email.senderEmail);
        statuses[recipient] = 'sent';
      } else {
        statuses[recipient] = 'failed';
      }
      // Anti-spam delay between each email
      if (email.delayMinutes > 0 && i < endIdx - 1) {
        await Future.delayed(Duration(minutes: email.delayMinutes));
      }
    }
    final latestList = await StorageService.getEmails();
    final cur = latestList.firstWhere((e) => e.id == email.id, orElse: () => email);
    if (cur.status == 'Paused') return;

    if (newCount >= total) {
      await StorageService.updateEmail(cur.copyWith(
        status: 'Success',
        sentCount: newCount,
        lastSentDate: today,
        recipientStatuses: Map.from(statuses),
      ));
    } else {
      final daysDone = (newCount / dailyLimit).ceil();
      final dayStatus = 'Merge Day $daysDone: $newCount/$total sent [$mergeLabel]';
      await StorageService.updateEmail(cur.copyWith(
        status: dayStatus,
        sentCount: newCount,
        lastSentDate: today,
        recipientStatuses: Map.from(statuses),
      ));
    }
  }

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
