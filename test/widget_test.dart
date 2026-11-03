import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mailflow/theme/app_theme.dart';
import 'package:mailflow/services/update_service.dart';

void main() {
  test('UpdateService release parser test', () {
    final release = ReleaseInfo.fromJson({
      'tag_name': 'v1.0.1',
      'name': 'MailFlow v1.0.1',
      'body': 'Initial update release',
      'published_at': '2026-11-03T00:00:00Z',
      'assets': [
        {
          'name': 'app-release.apk',
          'size': 25000000,
          'browser_download_url': 'https://github.com/HelloWorld-Farhan/MailFlow-Flutter/releases/download/v1.0.1/app-release.apk',
        }
      ]
    });

    expect(release.version, '1.0.1');
    expect(release.apkDownloadUrl, contains('.apk'));
    expect(release.apkSize, 25000000);
  });

  testWidgets('AppTheme light theme initializes properly', (WidgetTester tester) async {
    final theme = AppTheme.lightTheme;
    expect(theme.primaryColor, AppTheme.primaryBlue);
    expect(theme.scaffoldBackgroundColor, Colors.white);
  });
}
