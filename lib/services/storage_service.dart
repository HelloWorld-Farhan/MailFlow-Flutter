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
}
