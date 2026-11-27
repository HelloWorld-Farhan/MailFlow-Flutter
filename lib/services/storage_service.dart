import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/scheduled_email.dart';
import '../models/template_item.dart';
import '../utils/date_helpers.dart';
import 'dispatcher.dart';

class StorageService {
  static const String _emailsKey = 'scheduled_emails_history';
  static final StreamController<void> _changesController =
      StreamController<void>.broadcast();
  static Stream<void> get onDataChanged => _changesController.stream;

  // Serializes read-modify-write operations on SharedPreferences so parallel senders never race.
  static Future<void> _writeQueue = Future.value();

  static Future<T> _synchronized<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _writeQueue = _writeQueue.then((_) async {
      try {
        completer.complete(await action());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  static Future<void> saveEmail(ScheduledEmail email) async {
    await _synchronized(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final savedList = prefs.getStringList(_emailsKey) ?? [];
      savedList.add(email.toJson());
      await prefs.setStringList(_emailsKey, savedList);
    });
    _changesController.add(null);
    BackgroundDispatcher.scheduleExactAlarmForEmail(email);
  }

  static Future<List<ScheduledEmail>> getEmails() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final savedList = prefs.getStringList(_emailsKey) ?? [];
    return savedList.map((jsonStr) => ScheduledEmail.fromJson(jsonStr)).toList().reversed.toList();
  }

  static Future<void> deleteEmail(String id) async {
    await _synchronized(() async {
      final emails = await getEmails();
      emails.removeWhere((email) => email.id == id);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_emailsKey, emails.reversed.map((e) => e.toJson()).toList());
    });
    _changesController.add(null);
  }

  static Future<void> updateEmail(ScheduledEmail updatedEmail) async {
    await _synchronized(() async {
      final emails = await getEmails();
      final index = emails.indexWhere((e) => e.id == updatedEmail.id);
      if (index != -1) {
        emails[index] = updatedEmail;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList(_emailsKey, emails.reversed.map((e) => e.toJson()).toList());
      }
    });
    _changesController.add(null);
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
  static Future<Map<String, int>> getAllDailyLimits() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final date = prefs.getString('daily_sent_date');
    final today = DateHelpers.todayDmy();
    
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
    await _synchronized(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final limits = await getAllDailyLimits();
      limits[senderEmail] = (limits[senderEmail] ?? 0) + 1;
      await prefs.setString('daily_sent_map', jsonEncode(limits));
      await prefs.setString('daily_sent_date', DateHelpers.todayDmy());
    });
    _changesController.add(null);
  }

  // OAuth Access Token Storage (per sender)
  static Future<void> saveAccessToken(String email, String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('access_token_$email', token);
  }

  static Future<String?> getAccessToken(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return prefs.getString('access_token_$email');
  }
}
