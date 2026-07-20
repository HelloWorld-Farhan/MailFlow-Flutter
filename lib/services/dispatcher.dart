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
  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    clientId: '787471915530-sg4ul6fm6s1paqabljmksi9c61cf4c77.apps.googleusercontent.com',
    scopes: ['email', 'https://www.googleapis.com/auth/gmail.send'],
  );

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
      if (_activelySending.contains(email.id)) continue;
      if (_isTimeArrived(email.scheduledDate, email.scheduledTime)) {
        if (email.type == 'PDF' && email.dailyLimit > 0) {
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
      GoogleSignInAccount? account = _googleSignIn.currentUser;
      account ??= await _googleSignIn.signInSilently();
      if (account == null) return;
      final auth = await account.authentication;
      final token = auth.accessToken;
      if (token == null) return;
      if (email.type == 'Single') await _sendSingle(email, token);
      else if (email.type == 'Multiple') await _sendMultiple(email, token);
      else if (email.type == 'PDF') await _sendPdfBatch(email, token);
    } catch (e) {
      print('Dispatcher error: ' + e.toString());
    }
  }

  static Future<void> _sendSingle(ScheduledEmail email, String token) async {
    if (await StorageService.getDailySentCount() >= 50) return;
    await StorageService.updateEmail(email.copyWith(status: 'Sending...'));
    final success = await MailService.sendEmail(emailConfig: email, accessToken: token);
    if (success) {
      await StorageService.incrementDailySentCount();
    }
    await StorageService.updateEmail(email.copyWith(status: success ? 'Success' : 'Failed'));
  }

  static Future<void> _sendMultiple(ScheduledEmail email, String token) async {
    final total = email.recipients.length;
    for (int i = 0; i < total; i++) {
      if (await StorageService.getDailySentCount() >= 50) return;
      final st = 'Doing it... (' + i.toString() + '/' + total.toString() + ')';
      await StorageService.updateEmail(email.copyWith(status: st));
      final single = email.copyWith(recipients: [email.recipients[i]]);
      final success = await MailService.sendEmail(emailConfig: single, accessToken: token);
      if (success) await StorageService.incrementDailySentCount();
      if (i < total - 1) await Future.delayed(const Duration(seconds: 5));
    }
    await StorageService.updateEmail(email.copyWith(status: 'Success'));
  }

  static Future<void> _sendPdfBatch(ScheduledEmail email, String token) async {
    final total = email.recipients.length;
    final batchSize = email.dailyLimit > 0 ? email.dailyLimit : 40;
    final startIdx = email.sentCount;
    final endIdx = min(startIdx + batchSize, total);
    final today = _todayString();
    int newCount = startIdx;
    for (int i = startIdx; i < endIdx; i++) {
      if (await StorageService.getDailySentCount() >= 50) break;
      final latestList = await StorageService.getEmails();
      final cur = latestList.firstWhere((e) => e.id == email.id, orElse: () => email);
      if (cur.status == 'Paused') return;
      final st = 'Doing it... (' + i.toString() + '/' + total.toString() + ')';
      await StorageService.updateEmail(cur.copyWith(status: st, sentCount: i));
      final single = email.copyWith(recipients: [email.recipients[i]]);
      final success = await MailService.sendEmail(emailConfig: single, accessToken: token);
      if (success) await StorageService.incrementDailySentCount();
      newCount = i + 1;
      if (i < endIdx - 1) await Future.delayed(const Duration(seconds: 5));
    }
    final latestList = await StorageService.getEmails();
    final cur = latestList.firstWhere((e) => e.id == email.id, orElse: () => email);
    if (cur.status == 'Paused') return;
    
    if (newCount >= total) {
      await StorageService.updateEmail(cur.copyWith(status: 'Success', sentCount: newCount, lastSentDate: today));
    } else {
      final daysDone = (newCount / batchSize).ceil();
      final dayStatus = 'Day ' + daysDone.toString() + ': ' + newCount.toString() + '/' + total.toString() + ' sent';
      await StorageService.updateEmail(cur.copyWith(status: dayStatus, sentCount: newCount, lastSentDate: today));
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
}
