import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mailflow/models/scheduled_email.dart';
import 'package:mailflow/services/app_config.dart';
import 'package:mailflow/services/backend_service.dart';
import 'package:mailflow/services/notification_service.dart';
import 'package:mailflow/theme/app_theme.dart';
import 'package:mailflow/widgets/glass_widgets.dart';
import 'package:mailflow/widgets/update_dialog.dart';
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

  test('SendNotificationMonitor tracks start, parallel count, and completion', () {
    final monitor = SendNotificationMonitor();
    ScheduledEmail makeCampaign(String id, String status, {int sent = 0, Map<String, String>? map}) =>
        ScheduledEmail(
          id: id,
          senderEmail: '$id@example.com',
          type: 'Multiple',
          recipients: ['a@example.com', 'b@example.com'],
          subject: 'Hello $id',
          body: '<p>Hi</p>',
          scheduledDate: '27/11/2026',
          scheduledTime: '06:00 PM',
          status: status,
          scheduleName: 'Camp $id',
          sentCount: sent,
          recipientStatuses: map,
        );

    // Initial launch seeds state without replaying old notifications.
    expect(monitor.evaluate([makeCampaign('1', 'Scheduled'), makeCampaign('2', 'Scheduled')]), isEmpty);

    // Campaign 1 starts.
    final start1 = monitor.evaluate([
      makeCampaign('1', 'Running', map: {'a@example.com': 'inProcess'}),
      makeCampaign('2', 'Scheduled'),
    ]);
    expect(start1.length, 1);
    expect(start1.first.kind, CampaignEventKind.started);
    expect(start1.first.activeParallelCount, 1);
    expect(SendNotificationMonitor.currentRecipient(start1.first.email), 'a@example.com');

    // Campaign 2 starts while Campaign 1 is still running -> parallel count is 2.
    final start2 = monitor.evaluate([
      makeCampaign('1', 'Doing it... (1/2)', sent: 1),
      makeCampaign('2', 'Running', map: {'b@example.com': 'inProcess'}),
    ]);
    expect(start2.length, 1);
    expect(start2.first.kind, CampaignEventKind.started);
    expect(start2.first.activeParallelCount, 2);

    // Campaign 1 finishes, Campaign 2 fails.
    final finish = monitor.evaluate([
      makeCampaign('1', 'Success', sent: 2),
      makeCampaign('2', 'Failed: 401'),
    ]);
    expect(finish.map((e) => e.kind), [CampaignEventKind.completed, CampaignEventKind.failed]);
    expect(finish.first.activeParallelCount, 0);
  });

  testWidgets('GlassContainer and BlurredPageRoute render cleanly', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => GlassContainer(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  BlurredPageRoute(builder: (_) => const Scaffold(body: Text('GlassPage'))),
                ),
                child: const Text('Open Glass'),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Open Glass'), findsOneWidget);
    await tester.tap(find.text('Open Glass'));
    await tester.pumpAndSettle();
    expect(find.text('GlassPage'), findsOneWidget);
  });

  testWidgets('UpdateDialog shows compact update popup immediately with preset result',
      (WidgetTester tester) async {
    expect(UpdateService.isNewerVersion('1.0.3', '1.0.2'), isTrue);
    expect(UpdateService.isNewerVersion('1.0.2', '1.0.2'), isFalse);

    final preset = UpdateCheckResult(
      hasUpdate: true,
      currentVersion: '1.0.2',
      latestRelease: ReleaseInfo(
        tagName: 'v1.0.3',
        version: '1.0.3',
        name: 'MailFlow v1.0.3',
        body: 'Faster sending + live blur updates',
        apkDownloadUrl: 'https://example.com/MailFlow-Android.apk',
        windowsDownloadUrl: 'https://example.com/MailFlow-Windows-Setup.exe',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UpdateDialog(initialResult: preset),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('New Version Available: v1.0.3'), findsOneWidget);
    expect(find.text('Download & Install'), findsOneWidget);
  });

  testWidgets('AppTheme light theme initializes properly', (WidgetTester tester) async {
    final theme = AppTheme.lightTheme;
    expect(theme.primaryColor, AppTheme.primaryBlue);
    expect(theme.scaffoldBackgroundColor, Colors.white);
  });
}
