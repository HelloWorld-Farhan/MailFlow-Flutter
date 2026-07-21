import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/scheduled_email.dart';
import '../models/template_item.dart';
import 'dispatcher.dart';

class StorageService {
  static const String _emailsKey = 'scheduled_emails_history';

  static Future<void> saveEmail(ScheduledEmail email) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> savedList = prefs.getStringList(_emailsKey) ?? [];
    savedList.add(email.toJson());
    await prefs.setStringList(_emailsKey, savedList);
    
    // Automatically schedule exact alarm for this new email
    BackgroundDispatcher.scheduleExactAlarmForEmail(email);
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

  // Sender Email Autocomplete Storage
  static const String _sendersKey = 'saved_senders';
  
  static Future<List<String>> getSenderEmails() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_sendersKey) ?? [];
  }

  static Future<void> saveSenderEmail(String email) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> senders = prefs.getStringList(_sendersKey) ?? [];
    if (!senders.contains(email)) {
      senders.add(email);
      await prefs.setStringList(_sendersKey, senders);
    }
  }

  // Permanent Contacts (PDF Extracted) Storage
  static const String _contactsKey = 'saved_contacts';

  static Future<List<String>> getExtractedEmails() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_contactsKey) ?? [];
  }

  static Future<void> saveExtractedEmails(List<String> newEmails) async {
    final prefs = await SharedPreferences.getInstance();
    Set<String> contacts = (prefs.getStringList(_contactsKey) ?? []).toSet();
    contacts.addAll(newEmails);
    await prefs.setStringList(_contactsKey, contacts.toList());
  }

  // Templates Storage
  static const String _templatesKey = 'saved_templates';

  static Future<List<TemplateItem>> getTemplates() async {
    final prefs = await SharedPreferences.getInstance();
    List<String> savedList = prefs.getStringList(_templatesKey) ?? [];
    return savedList.map((jsonStr) => TemplateItem.fromJson(jsonStr)).toList();
  }

  static Future<void> saveTemplate(TemplateItem template) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> savedList = prefs.getStringList(_templatesKey) ?? [];
    savedList.add(template.toJson());
    await prefs.setStringList(_templatesKey, savedList);
  }

  static Future<void> deleteTemplate(String id) async {
    final templates = await getTemplates();
    templates.removeWhere((t) => t.id == id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_templatesKey, templates.map((t) => t.toJson()).toList());
  }

  static Future<void> updateTemplate(TemplateItem updatedTemplate) async {
    final templates = await getTemplates();
    final index = templates.indexWhere((t) => t.id == updatedTemplate.id);
    if (index != -1) {
      templates[index] = updatedTemplate;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_templatesKey, templates.map((t) => t.toJson()).toList());
    }
  }

  // Global Daily Sent Limit Tracking per Sender
  static String _todayString() {
    final now = DateTime.now();
    return '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
  }

  static Future<Map<String, int>> getAllDailyLimits() async {
    final prefs = await SharedPreferences.getInstance();
    final date = prefs.getString('daily_sent_date');
    final today = _todayString();
    
    if (date != today) {
      await prefs.setString('daily_sent_map', '{}');
      await prefs.setString('daily_sent_date', today);
      return {};
    }
    
    final mapStr = prefs.getString('daily_sent_map');
    if (mapStr == null || mapStr.isEmpty) return {};
    
    try {
      final Map<String, dynamic> decoded = jsonDecode(mapStr);
      return decoded.map((key, value) => MapEntry(key, value as int));
    } catch (e) {
      return {};
    }
  }

  static Future<int> getDailySentCount(String senderEmail) async {
    final limits = await getAllDailyLimits();
    return limits[senderEmail] ?? 0;
  }

  static Future<void> incrementDailySentCount(String senderEmail) async {
    final prefs = await SharedPreferences.getInstance();
    final limits = await getAllDailyLimits();
    
    int current = limits[senderEmail] ?? 0;
    limits[senderEmail] = current + 1;
    
    await prefs.setString('daily_sent_map', jsonEncode(limits));
    await prefs.setString('daily_sent_date', _todayString());
  }

  // ── OAuth Access Token Storage (per sender) ────────────────────────────
  // Saved when user signs in via UI, read by background dispatcher.
  // Key: 'access_token_<email>'
  static Future<void> saveAccessToken(String email, String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('access_token_$email', token);
    print('StorageService: Saved access token for $email');
  }

  static Future<String?> getAccessToken(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return prefs.getString('access_token_$email');
  }
}
