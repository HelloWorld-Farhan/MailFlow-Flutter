import 'package:shared_preferences/shared_preferences.dart';
import '../models/scheduled_email.dart';

class StorageService {
  static const String _emailsKey = 'scheduled_emails_history';

  static Future<void> saveEmail(ScheduledEmail email) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> savedList = prefs.getStringList(_emailsKey) ?? [];
    savedList.add(email.toJson());
    await prefs.setStringList(_emailsKey, savedList);
  }

  static Future<List<ScheduledEmail>> getEmails() async {
    final prefs = await SharedPreferences.getInstance();
    List<String> savedList = prefs.getStringList(_emailsKey) ?? [];
    return savedList.map((jsonStr) => ScheduledEmail.fromJson(jsonStr)).toList().reversed.toList();
  }

  static Future<void> deleteEmail(String id) async {
    final emails = await getEmails();
    emails.removeWhere((email) => email.id == id);
    final prefs = await SharedPreferences.getInstance();
    // Re-reverse back to original order before saving
    await prefs.setStringList(_emailsKey, emails.reversed.map((e) => e.toJson()).toList());
  }

  static Future<void> updateEmail(ScheduledEmail updatedEmail) async {
    final emails = await getEmails();
    final index = emails.indexWhere((e) => e.id == updatedEmail.id);
    if (index != -1) {
      emails[index] = updatedEmail;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_emailsKey, emails.reversed.map((e) => e.toJson()).toList());
    }
  }
}
