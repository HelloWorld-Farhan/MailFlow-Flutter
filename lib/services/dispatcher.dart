import 'dart:async';
import 'package:google_sign_in/google_sign_in.dart';
import 'storage_service.dart';
import 'mail_service.dart';

class BackgroundDispatcher {
  static Timer? _timer;
  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    clientId: '787471915530-sg4ul6fm6s1paqabljmksi9c61cf4c77.apps.googleusercontent.com',
    scopes: ['email', 'https://www.googleapis.com/auth/gmail.send']
  );

  static void start() {
    print('Starting Background Dispatcher...');
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 30), (timer) async {
      print('Dispatcher running...');
      await _checkAndSendEmails();
    });
  }

  static void stop() {
    _timer?.cancel();
  }

  static Future<void> _checkAndSendEmails() async {
    final emails = await StorageService.getEmails();
    
    for (final email in emails) {
      if (email.status == 'Success') continue; // Already sent
      
      if (_isTimeArrived(email.scheduledDate, email.scheduledTime)) {
        print('Time arrived for email: \${email.id}. Attempting to send...');
        
        try {
          // Attempt to get token silently
          GoogleSignInAccount? account = _googleSignIn.currentUser;
          account ??= await _googleSignIn.signInSilently();

          if (account != null) {
            final auth = await account.authentication;
            final token = auth.accessToken;

            if (token != null) {
              final success = await MailService.sendEmail(
                emailConfig: email,
                accessToken: token,
              );

              if (success) {
                // Update local storage status to Success
                final updatedEmail = email.copyWith(status: 'Success');
                await StorageService.updateEmail(updatedEmail);
                print('Email \${email.id} sent and status updated.');
              }
            } else {
              print('Failed to get Access Token for sending.');
            }
          } else {
            print('User not signed in. Cannot send email \${email.id}');
          }
        } catch (e) {
          print('Dispatcher error: \$e');
        }
      }
    }
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
      
      DateTime scheduledTime = DateTime(year, month, day, hour, minute);
      DateTime now = DateTime.now();
      
      return scheduledTime.isBefore(now) || scheduledTime.isAtSameMomentAs(now);
    } catch (e) {
      return false;
    }
  }
}
