import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mailflow/theme/app_theme.dart';
import 'package:mailflow/services/update_service.dart';

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

  testWidgets('AppTheme light theme initializes properly', (WidgetTester tester) async {
    final theme = AppTheme.lightTheme;
    expect(theme.primaryColor, AppTheme.primaryBlue);
    expect(theme.scaffoldBackgroundColor, Colors.white);
  });
}
