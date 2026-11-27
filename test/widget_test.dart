import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mailflow/services/app_config.dart';
import 'package:mailflow/services/backend_service.dart';
import 'package:mailflow/theme/app_theme.dart';
import 'package:mailflow/services/update_service.dart';
import 'package:mailflow/utils/date_helpers.dart';
import 'package:mailflow/utils/pdf_parser.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

void main() {
  test('UpdateService release parser parses Android APK and Windows EXE assets', () {
    final release = ReleaseInfo.fromJson({
      'tag_name': 'v1.0.2',
      'name': 'MailFlow v1.0.2',
      'body': 'Multiplatform update release',
      'published_at': '2026-11-27T00:00:00Z',
      'assets': [
        {
          'name': 'MailFlow-Android.apk',
          'size': 25000000,
          'browser_download_url': 'https://github.com/HelloWorld-Farhan/MailFlow-Flutter/releases/download/v1.0.2/MailFlow-Android.apk',
        },
        {
          'name': 'MailFlow-Windows-Setup.exe',
          'size': 18500000,
          'browser_download_url': 'https://github.com/HelloWorld-Farhan/MailFlow-Flutter/releases/download/v1.0.2/MailFlow-Windows-Setup.exe',
        },
      ]
    });

    expect(release.version, '1.0.2');
    expect(release.apkDownloadUrl, endsWith('.apk'));
    expect(release.apkSize, 25000000);
    expect(release.windowsDownloadUrl, endsWith('.exe'));
    expect(release.windowsSize, 18500000);
    if (Platform.isWindows) {
      expect(release.platformDownloadUrl, release.windowsDownloadUrl);
      expect(release.platformAssetSize, 18500000);
    }
  });

  test('AppConfig stores dynamic URLs without trailing slashes', () async {
    SharedPreferences.setMockInitialValues({});
    await AppConfig.saveOverrides(
      supabaseUrlValue: 'https://demo.supabase.co/',
      supabaseAnonKeyValue: 'anon-key',
      backendApiUrlValue: 'https://worker.test/',
      backendApiSecretValue: 'secret-key',
      googleWebClientIdValue: 'web-client-id',
    );
    expect(AppConfig.isBackendEnabled, isTrue);
    expect(AppConfig.supabaseUrl, 'https://demo.supabase.co');
    expect(AppConfig.backendApiUrl, 'https://worker.test');
  });

  test('BackendService parses DD/MM/YYYY and 12-hour time accurately', () {
    final am = BackendService.parseScheduleDateTime('27/11/2026', '12:05 AM');
    final pm = BackendService.parseScheduleDateTime('27/11/2026', '02:30 PM');
    expect(am, DateTime(2026, 11, 27, 0, 5));
    expect(pm, DateTime(2026, 11, 27, 14, 30));
    expect(BackendService.parseScheduleDateTime('invalid', '10:00 AM'), isNull);
  });

  test('DateHelpers validates dates, weekdays, and future schedules', () {
    expect(DateHelpers.formatDmy(DateTime(2026, 11, 27)), '27/11/2026');
    expect(DateHelpers.weekdayName('27/11/2026'), 'Friday');
    expect(DateHelpers.parseDmy('31/02/2026'), isNull);
    expect(DateHelpers.isFutureDmyTime('27/11/2099', '09:15', true), isTrue);
    expect(DateHelpers.isFutureDmyTime('01/01/2020', '09:15', true), isFalse);
  });

  test('PdfParser extracts unique lowercase emails in background isolate', () async {
    final doc = PdfDocument();
    doc.pages.add().graphics.drawString(
      'Contact Alice@Example.com and bob@test.org or alice@example.com',
      PdfStandardFont(PdfFontFamily.helvetica, 12),
    );
    final bytes = await doc.save();
    doc.dispose();

    final emails = await PdfParser.extractEmailsFromPdfBytes(Uint8List.fromList(bytes));
    expect(emails, unorderedEquals(['alice@example.com', 'bob@test.org']));
  });

  testWidgets('AppTheme light theme initializes properly', (WidgetTester tester) async {
    final theme = AppTheme.lightTheme;
    expect(theme.primaryColor, AppTheme.primaryBlue);
    expect(theme.scaffoldBackgroundColor, Colors.white);
  });
}
