import 'dart:async';
import 'dart:math';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:workmanager/workmanager.dart';
import 'storage_service.dart';
import 'mail_service.dart';
import '../models/scheduled_email.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    await BackgroundDispatcher.checkAndSendEmails();
    return Future.value(true);
  });
}

class BackgroundDispatcher {
  static Timer? _timer;
  static final Set<String> _activelySending = {};

  // Cache of per-sender GoogleSignIn instances
  static final Map<String, GoogleSignIn> _signInCache = {};

  static GoogleSignIn _getSignIn(String senderEmail) {
    if (!_signInCache.containsKey(senderEmail)) {
      _signInCache[senderEmail] = GoogleSignIn(
        clientId: '787471915530-sg4ul6fm6s1paqabljmksi9c61cf4c77.apps.googleusercontent.com',
        scopes: ['email', 'https://www.googleapis.com/auth/gmail.send'],
      );
    }
    return _signInCache[senderEmail]!;
  }

  static void start() {
    print('Starting Background Dispatcher...');
    Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
    Workmanager().registerPeriodicTask('1', 'emailDispatcher', frequency: const Duration(minutes: 15));
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 30), (timer) async {
      await checkAndSendEmails();
    });
  }

  static void stop() {
    _timer?.cancel();
    Workmanager().cancelAll();
  }

  static Future<void> checkAndSendEmails() async {
    final emails = await StorageService.getEmails();
    for (final email in emails) {
      if (email.status == 'Success') continue;
      if (email.status == 'Failed') continue;
      if (email.status == 'Paused') continue;
      if (email.status.startsWith('Doing')) continue;
      if (email.status.startsWith('Sending')) continue;
      if (email.status.startsWith('Merge Day')) continue;
      if (_activelySending.contains(email.id)) continue;

      // ── Queue-After check ─────────────────────────────────────────────
      if (email.queuedAfter != null && email.queuedAfter!.isNotEmpty) {
        final blocker = emails.firstWhere(
          (e) => e.id == email.queuedAfter,
          orElse: () => email, // if blocker gone, allow sending
        );
        // Only unblock if the blocker is finished
        if (blocker.id != email.id && blocker.status != 'Success' && blocker.status != 'Failed') {
          continue; // still waiting for blocker to finish
        }
        // Blocker done — remove queuedAfter so it can proceed next cycle
        if (blocker.status == 'Success' || blocker.status == 'Failed') {
          await StorageService.updateEmail(email.copyWith(clearQueuedAfter: true));
          continue; // will be picked up next timer cycle
        }
      }

      if (_isTimeArrived(email.scheduledDate, email.scheduledTime)) {
        if ((email.type == 'PDF' || email.isMerged) && email.dailyLimit > 0) {
          final today = _todayString();
          if (email.lastSentDate == today) continue;
        }
        _activelySending.add(email.id);
        _processEmail(email).then((_) => _activelySending.remove(email.id));
      }
    }
  }

  static Future<void> _processEmail(ScheduledEmail email) async {
    try {
      final googleSignIn = _getSignIn(email.senderEmail);

      GoogleSignInAccount? account = googleSignIn.currentUser;
      if (account == null || account.email != email.senderEmail) {
        account = await googleSignIn.signInSilently();
      }

      if (account == null || account.email != email.senderEmail) {
        for (final entry in _signInCache.entries) {
          if (entry.key == email.senderEmail) {
            final cur = entry.value.currentUser;
            if (cur != null && cur.email == email.senderEmail) {
              account = cur;
              break;
            }
          }
        }
      }

      if (account == null) {
        print('Dispatcher: No authenticated account for ${email.senderEmail}');
        return;
      }

      final auth = await account.authentication;
      final token = auth.accessToken;
      if (token == null) return;

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
    if (await StorageService.getDailySentCount(email.senderEmail) >= 50) return;
    final recipient = email.recipients.isNotEmpty ? email.recipients[0] : '';
    final statuses = Map<String, String>.from(email.recipientStatuses);
    if (recipient.isNotEmpty) statuses[recipient] = 'inProcess';
    await StorageService.updateEmail(email.copyWith(status: 'Sending...', recipientStatuses: statuses));
    final success = await MailService.sendEmail(emailConfig: email, accessToken: token);
    if (success) {
      await StorageService.incrementDailySentCount(email.senderEmail);
      if (recipient.isNotEmpty) statuses[recipient] = 'sent';
    } else {
      if (recipient.isNotEmpty) statuses[recipient] = 'failed';
    }
    await StorageService.updateEmail(email.copyWith(
      status: success ? 'Success' : 'Failed',
      recipientStatuses: statuses,
    ));
  }

  static Future<void> _sendMultiple(ScheduledEmail email, String token) async {
    final total = email.recipients.length;
    final statuses = Map<String, String>.from(email.recipientStatuses);
    for (final r in email.recipients) {
      if (!statuses.containsKey(r)) statuses[r] = 'pending';
    }
    for (int i = 0; i < total; i++) {
      if (await StorageService.getDailySentCount(email.senderEmail) >= 50) break;
      final recipient = email.recipients[i];
      statuses[recipient] = 'inProcess';
      final st = 'Doing it... (' + i.toString() + '/' + total.toString() + ')';
      await StorageService.updateEmail(email.copyWith(status: st, recipientStatuses: Map.from(statuses)));
      final single = email.copyWith(recipients: [recipient]);
      final success = await MailService.sendEmail(emailConfig: single, accessToken: token);
      if (success) {
        await StorageService.incrementDailySentCount(email.senderEmail);
        statuses[recipient] = 'sent';
      } else {
        statuses[recipient] = 'failed';
      }
      if (i < total - 1) await Future.delayed(const Duration(seconds: 5));
    }
    await StorageService.updateEmail(email.copyWith(status: 'Success', recipientStatuses: Map.from(statuses)));
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
      if (await StorageService.getDailySentCount(email.senderEmail) >= 50) break;
      final latestList = await StorageService.getEmails();
      final cur = latestList.firstWhere((e) => e.id == email.id, orElse: () => email);
      if (cur.status == 'Paused') return;
      final recipient = email.recipients[i];
      statuses[recipient] = 'inProcess';
      final st = 'Doing it... (' + i.toString() + '/' + total.toString() + ')';
      await StorageService.updateEmail(cur.copyWith(status: st, sentCount: i, recipientStatuses: Map.from(statuses)));
      final single = email.copyWith(recipients: [recipient]);
      final success = await MailService.sendEmail(emailConfig: single, accessToken: token);
      if (success) {
        await StorageService.incrementDailySentCount(email.senderEmail);
        statuses[recipient] = 'sent';
      } else {
        statuses[recipient] = 'failed';
      }
      newCount = i + 1;
      if (i < endIdx - 1) await Future.delayed(const Duration(seconds: 5));
    }
    final latestList = await StorageService.getEmails();
    final cur = latestList.firstWhere((e) => e.id == email.id, orElse: () => email);
    if (cur.status == 'Paused') return;

    if (newCount >= total) {
      await StorageService.updateEmail(cur.copyWith(status: 'Success', sentCount: newCount, lastSentDate: today, recipientStatuses: Map.from(statuses)));
    } else {
      final daysDone = (newCount / batchSize).ceil();
      final dayStatus = 'Day ' + daysDone.toString() + ': ' + newCount.toString() + '/' + total.toString() + ' sent';
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
      if (await StorageService.getDailySentCount(email.senderEmail) >= 50) break;
      final latestList = await StorageService.getEmails();
      final cur = latestList.firstWhere((e) => e.id == email.id, orElse: () => email);
      if (cur.status == 'Paused') return;
      final recipient = email.recipients[i];
      statuses[recipient] = 'inProcess';
      final st = 'Merge Day ${(i / dailyLimit).ceil() + 1}: $i/$total sent';
      await StorageService.updateEmail(cur.copyWith(
        status: st,
        sentCount: i,
        recipientStatuses: Map.from(statuses),
      ));
      final single = email.copyWith(recipients: [recipient]);
      final success = await MailService.sendEmail(emailConfig: single, accessToken: token);
      if (success) {
        await StorageService.incrementDailySentCount(email.senderEmail);
        statuses[recipient] = 'sent';
      } else {
        statuses[recipient] = 'failed';
      }
      newCount = i + 1;
      if (i < endIdx - 1) await Future.delayed(const Duration(seconds: 5));
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
