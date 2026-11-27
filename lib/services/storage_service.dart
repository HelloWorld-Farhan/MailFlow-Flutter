import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/template_item.dart';

/// Local persistence for sender autocomplete history, extracted contacts, templates, and theme preference.
class StorageService {
  static const String _sendersKey = 'saved_senders';
  static const String _contactsKey = 'saved_contacts';
  static const String _templatesKey = 'saved_templates';
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
    final prefs = await SharedPreferences.getInstance();
    final senders = prefs.getStringList(_sendersKey) ?? [];
    if (!senders.contains(email)) {
      senders.add(email);
      await prefs.setStringList(_sendersKey, senders);
    }
  }

  static Future<List<String>> getExtractedEmails() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_contactsKey) ?? [];
  }

  static Future<void> saveExtractedEmails(List<String> newEmails) async {
    final prefs = await SharedPreferences.getInstance();
    final contacts = (prefs.getStringList(_contactsKey) ?? []).toSet();
    contacts.addAll(newEmails);
    await prefs.setStringList(_contactsKey, contacts.toList());
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
}
