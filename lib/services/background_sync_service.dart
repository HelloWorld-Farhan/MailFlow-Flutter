import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import '../models/scheduled_email.dart';
import '../theme/app_theme.dart';
import 'app_config.dart';
import 'backend_service.dart';
import 'notification_service.dart';
import 'update_service.dart';

const String _bgPollTaskName = 'mailflow_bg_poll';
const String _bgWakeTaskName = 'mailflow_campaign_wake';
const String _lastNotifiedUpdateKey = 'last_notified_update_version';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      await AppTheme.loadThemeMode();
      await AppConfig.load();
      await NotificationService.initialize();

      try {
        final maxCycles = task == _bgWakeTaskName ? 5 : 1;
        for (int cycle = 0; cycle < maxCycles; cycle++) {
          if (cycle > 0) {
            await Future<void>.delayed(const Duration(seconds: 15));
          }
          if (task == _bgWakeTaskName) {
            try {
              await BackendService.triggerTick();
            } catch (_) {}
          }
          final campaigns = await BackendService.fetchCampaigns();
          final now = DateTime.now();
          bool hasImminentOrActive = false;
          for (final item in campaigns) {
            if (SendNotificationMonitor.isActiveStatus(item.status)) {
              hasImminentOrActive = true;
            } else if (item.status == 'Scheduled') {
              final startDt = BackendService.parseScheduleDateTime(
                item.scheduledDate,
                item.scheduledTime,
              );
              if (startDt != null) {
                final diffSec = startDt.difference(now).inSeconds;
                if (diffSec > 0 && diffSec <= 90) {
                  hasImminentOrActive = true;
                  await NotificationService.showPreStartCountdownNotification(
                    item,
                    diffSec.clamp(1, 60),
                  );
                } else if (diffSec <= 0 && diffSec >= -60) {
                  hasImminentOrActive = true;
                }
              }
            }
          }
          await NotificationService.handleSnapshot(campaigns);
          if (!hasImminentOrActive) break;
        }
      } catch (_) {}

      try {
        final update = await UpdateService.checkForUpdates();
        if (update.hasUpdate && update.latestRelease != null) {
          final latestVer = update.latestRelease!.version;
          final prefs = await SharedPreferences.getInstance();
          if (prefs.getString(_lastNotifiedUpdateKey) != latestVer) {
            await prefs.setString(_lastNotifiedUpdateKey, latestVer);
            await NotificationService.showUpdateNotification(
              newVersion: latestVer,
              body: 'MailFlow v$latestVer is ready! Tap to download and install.',
            );
          }
        }
      } catch (_) {}

      return true;
    } catch (_) {
      return false;
    }
  });
}

/// Schedules Android WorkManager background tasks so campaign & update notifications
/// fire even when the app is closed or in the background.
class BackgroundSyncService {
  static bool _initialized = false;

  static bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  static Future<void> initialize() async {
    if (_initialized || !_isAndroid) return;
    _initialized = true;
    try {
      await Workmanager().initialize(callbackDispatcher);
      await Workmanager().registerPeriodicTask(
        _bgPollTaskName,
        _bgPollTaskName,
        frequency: const Duration(minutes: 15),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
        constraints: Constraints(networkType: NetworkType.connected),
      );
    } catch (_) {}
  }

  /// Registers a one-off background wakeup ~60s before a scheduled campaign starts.
  static Future<void> scheduleCampaignWake(ScheduledEmail email) async {
    if (!_isAndroid || email.status != 'Scheduled') return;
    final startDt = BackendService.parseScheduleDateTime(
      email.scheduledDate,
      email.scheduledTime,
    );
    if (startDt == null) return;
    final rawSec = (startDt.difference(DateTime.now()) - const Duration(seconds: 60)).inSeconds;
    if (rawSec > 7 * 86400) return;
    final delay = Duration(seconds: rawSec < 1 ? 1 : rawSec);
    try {
      await Workmanager().registerOneOffTask(
        'campaign_wake_${email.id}',
        _bgWakeTaskName,
        initialDelay: delay,
        existingWorkPolicy: ExistingWorkPolicy.replace,
        constraints: Constraints(networkType: NetworkType.connected),
      );
    } catch (_) {}
  }
}
