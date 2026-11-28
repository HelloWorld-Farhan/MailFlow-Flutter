import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/scheduled_email.dart';
import '../models/template_item.dart';
import '../utils/date_helpers.dart';

/// Saved contact entry with the schedule types where it was used (`Single`, `Multiple`, `PDF`).
class SavedContact {
  final String email;
  final Set<String> sources;
  final String? savedDate;
  const SavedContact({required this.email, required this.sources, this.savedDate});
}

/// Local persistence for sender autocomplete history, extracted contacts, templates, and theme preference.
class StorageService {
  static const String _sendersKey = 'saved_senders';
  static const String _contactsKey = 'saved_contacts';
  static const String _contactsSourcesKey = 'saved_contacts_sources';
  static const String _contactsDatesKey = 'saved_contacts_dates';
  static const String _dailyLimitsHistoryKey = 'saved_daily_limits_history';
  static const String _templatesKey = 'saved_templates';
  static const String _draftsKey = 'saved_schedule_drafts';
  static const String _themeModeKey = 'theme_mode';

  static Future<ThemeMode> getThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    switch (prefs.getString(_themeModeKey)) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  static Future<void> saveThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModeKey, mode.name);
  }

  static Future<List<String>> getSenderEmails() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_sendersKey) ?? [];
  }

  static Future<void> saveSenderEmail(String email) async {
    final normalized = email.trim().toLowerCase();
    if (normalized.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final senders = (prefs.getStringList(_sendersKey) ?? [])
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toList();
    if (!senders.contains(normalized)) {
      senders.add(normalized);
      await prefs.setStringList(_sendersKey, senders);
    }
  }

  static Future<List<String>> getExtractedEmails() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_contactsKey) ?? [];
  }

  static Future<void> saveExtractedEmails(List<String> newEmails, {String source = 'PDF'}) =>
      saveContacts(newEmails, source: source);

  /// Saves emails normalized to lowercase and tags each with its source (`Single`, `Multiple`, `PDF`) and date.
  static Future<void> saveContacts(List<String> newEmails, {required String source}) async {
    if (newEmails.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final contacts = (prefs.getStringList(_contactsKey) ?? []).map((e) => e.trim().toLowerCase()).where((e) => e.isNotEmpty).toSet();
    final rawMeta = prefs.getString(_contactsSourcesKey);
    final Map<String, Set<String>> meta = {};
    if (rawMeta != null && rawMeta.isNotEmpty) {
      final decoded = jsonDecode(rawMeta) as Map<String, dynamic>;
      for (final entry in decoded.entries) {
        meta[entry.key] = Set<String>.from((entry.value as List).map((e) => e.toString()));
      }
    }
    final rawDates = prefs.getString(_contactsDatesKey);
    final Map<String, String> dates = {};
    if (rawDates != null && rawDates.isNotEmpty) {
      final decoded = jsonDecode(rawDates) as Map<String, dynamic>;
      for (final entry in decoded.entries) {
        dates[entry.key] = entry.value.toString();
      }
    }
    final today = DateHelpers.todayDmy();
    for (final raw in newEmails) {
      final email = raw.trim().toLowerCase();
      if (email.isEmpty) continue;
      contacts.add(email);
      meta.putIfAbsent(email, () => <String>{}).add(source);
      dates[email] = today;
    }
    await prefs.setStringList(_contactsKey, contacts.toList());
    await prefs.setString(
      _contactsSourcesKey,
      jsonEncode(meta.map((k, v) => MapEntry(k, v.toList()))),
    );
    await prefs.setString(_contactsDatesKey, jsonEncode(dates));
  }

  /// Returns all saved contacts with their source tags (`Single`, `Multiple`, `PDF`) and saved date.
  static Future<List<SavedContact>> getContactsWithSources() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_contactsKey) ?? [];
    final rawMeta = prefs.getString(_contactsSourcesKey);
    final Map<String, Set<String>> meta = {};
    if (rawMeta != null && rawMeta.isNotEmpty) {
      final decoded = jsonDecode(rawMeta) as Map<String, dynamic>;
      for (final entry in decoded.entries) {
        meta[entry.key] = Set<String>.from((entry.value as List).map((e) => e.toString()));
      }
    }
    final rawDates = prefs.getString(_contactsDatesKey);
    final Map<String, String> dates = {};
    if (rawDates != null && rawDates.isNotEmpty) {
      final decoded = jsonDecode(rawDates) as Map<String, dynamic>;
      for (final entry in decoded.entries) {
        dates[entry.key] = entry.value.toString();
      }
    }
    final seen = <String>{};
    final result = <SavedContact>[];
    for (final raw in [...list, ...meta.keys]) {
      final email = raw.trim().toLowerCase();
      if (email.isEmpty || !seen.add(email)) continue;
      result.add(SavedContact(email: email, sources: meta[email] ?? <String>{}, savedDate: dates[email]));
    }
    return result;
  }

  /// Deletes a saved contact from local storage.
  static Future<void> deleteContact(String email) async {
    final normalized = email.trim().toLowerCase();
    final prefs = await SharedPreferences.getInstance();
    final list = (prefs.getStringList(_contactsKey) ?? [])
        .where((e) => e.trim().toLowerCase() != normalized)
        .toList();
    await prefs.setStringList(_contactsKey, list);
    final rawMeta = prefs.getString(_contactsSourcesKey);
    if (rawMeta != null && rawMeta.isNotEmpty) {
      final decoded = jsonDecode(rawMeta) as Map<String, dynamic>;
      decoded.remove(normalized);
      await prefs.setString(_contactsSourcesKey, jsonEncode(decoded));
    }
    final rawDates = prefs.getString(_contactsDatesKey);
    if (rawDates != null && rawDates.isNotEmpty) {
      final decoded = jsonDecode(rawDates) as Map<String, dynamic>;
      decoded.remove(normalized);
      await prefs.setString(_contactsDatesKey, jsonEncode(decoded));
    }
  }

  /// Saves a date's (`DD/MM/YYYY`) per-sender sent counts locally, retaining the latest 14 days.
  static Future<void> saveDailyLimitsSnapshot(String dateDmy, Map<String, int> counts) async {
    final prefs = await SharedPreferences.getInstance();
    final history = await getDailyLimitsHistory();
    history[dateDmy] = Map<String, int>.from(counts);
    if (history.length > 14) {
      final keys = history.keys.toList();
      for (final oldKey in keys.take(history.length - 14)) {
        history.remove(oldKey);
      }
    }
    await prefs.setString(_dailyLimitsHistoryKey, jsonEncode(history));
  }

  /// Returns saved daily sender sent counts keyed by `DD/MM/YYYY`.
  static Future<Map<String, Map<String, int>>> getDailyLimitsHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_dailyLimitsHistoryKey);
    if (raw == null || raw.isEmpty) return {};
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final result = <String, Map<String, int>>{};
    for (final entry in decoded.entries) {
      final inner = entry.value as Map<String, dynamic>;
      result[entry.key] = inner.map((k, v) => MapEntry(k, (v as num).toInt()));
    }
    return result;
  }

  static Future<List<TemplateItem>> getTemplates() async {
    final prefs = await SharedPreferences.getInstance();
    final savedList = prefs.getStringList(_templatesKey) ?? [];
    return savedList.map((jsonStr) => TemplateItem.fromJson(jsonStr)).toList();
  }

  static Future<void> saveTemplate(TemplateItem template) async {
    final prefs = await SharedPreferences.getInstance();
    final savedList = prefs.getStringList(_templatesKey) ?? [];
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

  /// Loads locally saved incomplete schedule drafts.
  static Future<List<ScheduledEmail>> getDrafts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_draftsKey) ?? [];
    final drafts = <ScheduledEmail>[];
    for (final s in raw) {
      try {
        drafts.add(ScheduledEmail.fromJson(s));
      } catch (_) {}
    }
    return drafts;
  }

  /// Saves or updates an incomplete schedule draft on the device.
  static Future<void> saveDraft(ScheduledEmail draft) async {
    final drafts = await getDrafts();
    final idx = drafts.indexWhere((d) => d.id == draft.id);
    if (idx != -1) {
      drafts[idx] = draft;
    } else {
      drafts.insert(0, draft);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_draftsKey, drafts.map((d) => d.toJson()).toList());
  }

  /// Deletes a saved draft by ID.
  static Future<void> deleteDraft(String id) async {
    final drafts = await getDrafts();
    drafts.removeWhere((d) => d.id == id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_draftsKey, drafts.map((d) => d.toJson()).toList());
  }
}
