import 'dart:io';
import 'dart:async';
import 'dart:math' show min;
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/scheduled_email.dart';
import '../services/app_config.dart';
import '../services/backend_service.dart';
import '../services/background_sync_service.dart';
import '../services/storage_service.dart';
import '../utils/date_helpers.dart';
import '../utils/date_input_formatter.dart';
import '../utils/time_input_formatter.dart';
import '../utils/pdf_parser.dart';
import '../theme/app_theme.dart';
import 'settings_screen.dart';
import 'email_limit_screen.dart';
import '../models/template_item.dart';
import '../widgets/glass_widgets.dart';
import '../widgets/update_dialog.dart';
import '../services/update_service.dart';
import '../services/notification_service.dart';
import 'package:package_info_plus/package_info_plus.dart';

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
//  DASHBOARD SCREEN
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  List<ScheduledEmail> _history = [];
  List<ScheduledEmail> _drafts = [];
  int _selectedTab = 0; // 0: Ongoing, 1: Completed, 2: Drafts
  bool _isLoading = true;
  int _totalDailySent = 0;

  Timer? _refreshTimer;
  Timer? _countdownTimer;
  Timer? _alertDismissTimer;
  StreamSubscription<void>? _realtimeSub;
  StreamSubscription<String>? _notifTapSub;
  final ValueNotifier<List<ScheduledEmail>> _historyNotifier =
      ValueNotifier<List<ScheduledEmail>>([]);
  final ValueNotifier<DateTime> _nowNotifier = ValueNotifier<DateTime>(DateTime.now());
  final Set<String> _preStartNotifiedIds = {};
  DateTime? _lastTickDispatchAt;
  String? _pendingLaunchCampaignId;
  String? _openDetailsCampaignId;
  bool _updateDialogOpen = false;
  DateTime? _lastUpdateCheckAt;
  Timer? _updateCheckTimer;
  String? _lastNotifiedVersion;
  String? _lastPopupShownVersion;
  UpdateCheckResult? _latestUpdateResult;
  CampaignNotificationEvent? _latestAlert;
  String _currentVersion = '1.0.0';
  bool _hasUpdate = false;
  String? _latestVersion;
  bool _bannerDismissed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pendingLaunchCampaignId = NotificationService.consumeInitialCampaignId();
    _notifTapSub = NotificationService.onNotificationTap.listen(_openCampaignById);
    _checkPermissions();
    _loadDrafts();
    _loadHistory();
    _initVersionAndCheckUpdate();
    _realtimeSub = BackendService.onDataChanged.listen((_) => _loadHistory());
    _refreshTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      _loadHistory();
    });
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) => _onSecondTick());
    _updateCheckTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      _initVersionAndCheckUpdate();
    });
  }

  void _onSecondTick() {
    if (!mounted || _history.isEmpty) return;
    final now = DateTime.now();
    final activeList = _history.where((e) => SendNotificationMonitor.isActiveStatus(e.status)).toList();
    bool hasLiveWork = false;
    bool shouldDispatch = false;

    for (final item in _history) {
      if (SendNotificationMonitor.isActiveStatus(item.status)) {
        hasLiveWork = true;
        final nextAt = item.nextSendAt;
        final nextSec = nextAt != null ? nextAt.difference(now).inSeconds : null;
        if (nextSec != null && nextSec <= 0) {
          shouldDispatch = true;
        } else if (now.second % 10 == 0) {
          shouldDispatch = true;
        }
      } else if (item.status == 'Scheduled') {
        final startDt = BackendService.parseScheduleDateTime(item.scheduledDate, item.scheduledTime);
        if (startDt != null) {
          final diffSec = startDt.difference(now).inSeconds;
          if (diffSec <= 60 && diffSec > 0) {
            hasLiveWork = true;
            final isFirst = _preStartNotifiedIds.add(item.id);
            NotificationService.showPreStartCountdownNotification(
              item,
              diffSec,
              silent: !isFirst,
            );
          } else if (diffSec <= 0 && diffSec >= -120) {
            hasLiveWork = true;
            shouldDispatch = true;
          }
        }
      }
    }

    if (activeList.isNotEmpty) {
      NotificationService.showConsolidatedActiveNotification(activeList);
    }

    if (hasLiveWork) {
      _nowNotifier.value = now;
      if (now.second % 3 == 0) {
        _loadHistory();
      }
      if (shouldDispatch) {
        final last = _lastTickDispatchAt;
        if (last == null || now.difference(last).inSeconds >= 4) {
          _lastTickDispatchAt = now;
          BackendService.triggerTick().catchError((_) => <String, dynamic>{});
        }
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      BackendService.verifyCloudConnection();
      _loadHistory();
      final last = _lastUpdateCheckAt;
      if (last == null || DateTime.now().difference(last) > const Duration(seconds: 30)) {
        _initVersionAndCheckUpdate();
      }
    }
  }

  Future<void> _initVersionAndCheckUpdate() async {
    _lastUpdateCheckAt = DateTime.now();
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _currentVersion = info.version);
    } catch (_) {}

    final result = await UpdateService.checkForUpdates();
    if (!mounted) return;
    _latestUpdateResult = result;
    if (result.hasUpdate && result.latestRelease != null) {
      final ver = result.latestRelease!.version;
      setState(() {
        _hasUpdate = true;
        _latestVersion = ver;
        _bannerDismissed = false;
      });
      if (_lastNotifiedVersion != ver) {
        _lastNotifiedVersion = ver;
        NotificationService.showUpdateNotification(
          newVersion: ver,
          body: 'MailFlow v$ver is now ready. Tap to download & install.',
        );
      }

      if (mounted && _lastPopupShownVersion != ver && !_updateDialogOpen) {
        _lastPopupShownVersion = ver;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showUpdatePopup(result: result);
        });
      }
    }
  }

  Future<void> _showUpdatePopup({
    UpdateCheckResult? result,
    bool markDismissedOnClose = false,
  }) async {
    if (_updateDialogOpen || !mounted) return;
    _updateDialogOpen = true;
    try {
      await UpdateDialog.show(context, initialResult: result ?? _latestUpdateResult);
      final ver = (result ?? _latestUpdateResult)?.latestRelease?.version;
      if (markDismissedOnClose && ver != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('dismissed_update_version', ver);
      }
    } finally {
      _updateDialogOpen = false;
    }
  }

  Future<void> _checkPermissions() async {
    if (kIsWeb || !Platform.isAndroid) return;
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _realtimeSub?.cancel();
    _notifTapSub?.cancel();
    _refreshTimer?.cancel();
    _countdownTimer?.cancel();
    _updateCheckTimer?.cancel();
    _alertDismissTimer?.cancel();
    _historyNotifier.dispose();
    _nowNotifier.dispose();
    super.dispose();
  }

  void _openCampaignById(String campaignId) async {
    if (!mounted) return;
    if (campaignId == NotificationService.updatePayload) {
      await _showUpdatePopup();
      return;
    }
    if (_openDetailsCampaignId == campaignId) return;
    var match = _history.where((e) => e.id == campaignId).firstOrNull;
    if (match == null) {
      await _loadHistory();
      if (!mounted) return;
      match = _history.where((e) => e.id == campaignId).firstOrNull;
    }
    if (match != null) {
      _showEmailDetails(match);
    }
  }

  Future<void> _applyLoadedHistory(List<ScheduledEmail> history, int totalSent) async {
    _historyNotifier.value = history;
    final events = await NotificationService.handleSnapshot(history);
    if (!mounted) return;
    setState(() {
      _history = history;
      _totalDailySent = totalSent;
      _isLoading = false;
      if (events.isNotEmpty) {
        _latestAlert = events.last;
      }
    });
    if (events.isNotEmpty) {
      _alertDismissTimer?.cancel();
      _alertDismissTimer = Timer(const Duration(seconds: 6), () {
        if (mounted) setState(() => _latestAlert = null);
      });
    }
    if (_pendingLaunchCampaignId != null) {
      final targetId = _pendingLaunchCampaignId!;
      _pendingLaunchCampaignId = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => _openCampaignById(targetId));
    }
    for (final item in history) {
      if (item.status == 'Scheduled') {
        unawaited(BackgroundSyncService.scheduleCampaignWake(item));
      }
    }
  }

  Future<void> _loadDrafts() async {
    final drafts = await StorageService.getDrafts();
    if (mounted) setState(() => _drafts = drafts);
  }

  Future<void> _deleteDraft(ScheduledEmail draft) async {
    final label = (draft.scheduleName != null && draft.scheduleName!.trim().isNotEmpty)
        ? draft.scheduleName!.trim()
        : (draft.subject.trim().isNotEmpty ? draft.subject.trim() : 'this draft');
    final confirm = await showBlurredDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Draft?', style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.w600)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.errorRed.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.errorRed.withValues(alpha: 0.25)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.label_outline_rounded, size: 15, color: AppTheme.errorRed),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      style: const TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.errorRed),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            const Text('Are you sure you want to delete this draft?', style: TextStyle(fontFamily: 'Inter')),
          ],
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(fontFamily: 'Inter', color: AppTheme.textMid)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorRed, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(fontFamily: 'Inter', color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    if (mounted) {
      setState(() => _drafts.removeWhere((d) => d.id == draft.id));
    }
    await StorageService.deleteDraft(draft.id);
    await _loadDrafts();
  }

  Future<void> _loadHistory() async {
    try {
      final (history, limitsMap, drafts) = await (
        BackendService.fetchCampaigns(),
        BackendService.fetchDailyLimits(),
        StorageService.getDrafts(),
      ).wait;
      final totalSent = limitsMap.values.fold<int>(0, (sum, val) => sum + val);
      if (mounted) _drafts = drafts;
      await _applyLoadedHistory(history, totalSent);
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _openScheduleModal({ScheduledEmail? existingEmail, bool isDraft = false}) {
    FocusManager.instance.primaryFocus?.unfocus();
    final existingNames = <String>{
      for (final item in [..._history, ..._drafts])
        if (item.id != existingEmail?.id && (item.scheduleName?.trim().isNotEmpty ?? false))
          item.scheduleName!.trim().toLowerCase(),
    };
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.48),
      useSafeArea: true,
      builder: (context) => ResponsiveCenter(
        maxWidth: 640,
        child: _ScheduleModal(
          editEmail: existingEmail,
          isDraft: isDraft,
          existingScheduleNames: existingNames,
          existingDrafts: _drafts,
          onDraftChanged: _loadDrafts,
          onOpenDraft: (d) => _openScheduleModal(existingEmail: d, isDraft: true),
        ),
      ),
    ).then((_) {
      FocusManager.instance.primaryFocus?.unfocus();
      _loadDrafts();
    });
  }

  void _openResendModal(ScheduledEmail email) {
    FocusManager.instance.primaryFocus?.unfocus();
    NotificationService.clearCampaignAlertState(email.id);
    showBlurredDialog(
      context: context,
      builder: (context) => _ResendModal(email: email),
    ).then((_) => FocusManager.instance.primaryFocus?.unfocus());
  }

  Future<void> _deleteEmail(ScheduledEmail email) async {
    final label = (email.scheduleName != null && email.scheduleName!.trim().isNotEmpty)
        ? email.scheduleName!.trim()
        : (email.subject.trim().isNotEmpty ? email.subject.trim() : email.senderEmail);
    final bool? confirm = await showBlurredDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Schedule?', style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.w600)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.errorRed.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.errorRed.withValues(alpha: 0.25)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.label_outline_rounded, size: 15, color: AppTheme.errorRed),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      style: const TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.errorRed),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            const Text('If you delete it, the process will be terminated and this info will be unrecoverable.', style: TextStyle(fontFamily: 'Inter')),
          ],
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(fontFamily: 'Inter', color: AppTheme.textMid)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorRed, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(fontFamily: 'Inter', color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    if (mounted) {
      setState(() {
        _history.removeWhere((e) => e.id == email.id);
        _historyNotifier.value = List.of(_history);
      });
    }
    await BackendService.deleteCampaign(email.id);
    await _loadHistory();
  }

  Future<void> _stopEmail(ScheduledEmail email) async {
    final idx = _history.indexWhere((e) => e.id == email.id);
    if (idx != -1 && mounted) {
      setState(() {
        _history[idx] = _history[idx].copyWith(status: 'Paused');
        _historyNotifier.value = List.of(_history);
      });
    }
    await BackendService.pauseCampaign(email.id);
    await _loadHistory();
  }

  Future<void> _resumeEmail(ScheduledEmail email) async {
    NotificationService.clearCampaignAlertState(email.id);
    final idx = _history.indexWhere((e) => e.id == email.id);
    if (idx != -1 && mounted) {
      setState(() {
        _history[idx] = _history[idx].copyWith(status: 'Scheduled');
        _historyNotifier.value = List.of(_history);
      });
    }
    // testing: weekend sending enabled until user asks to restore weekday-only
    await BackendService.resumeCampaign(email.id, forceWeekend: true);
    await _loadHistory();
  }

  void _showAllContacts() async {
    // Backfill recipients from existing schedules so Single / Multiple / PDF filters stay complete.
    final Map<String, List<String>> byType = {};
    for (final item in _history) {
      if (item.recipients.isEmpty) continue;
      byType.putIfAbsent(item.type, () => []).addAll(item.recipients);
    }
    for (final entry in byType.entries) {
      await StorageService.saveContacts(entry.value, source: entry.key);
    }
    final contacts = await StorageService.getContactsWithSources();
    if (!mounted) return;
    showBlurredDialog(
      context: context,
      builder: (context) => _ContactsDialog(initialContacts: contacts),
    );
  }

  void _showEmailDetails(ScheduledEmail email) {
    _openDetailsCampaignId = email.id;
    showBlurredDialog(
      context: context,
      builder: (context) => _DetailsDialog(
        email: email,
        primaryColor: AppTheme.primaryBlue,
        historyNotifier: _historyNotifier,
        nowNotifier: _nowNotifier,
      ),
    ).then((_) {
      if (_openDetailsCampaignId == email.id) {
        _openDetailsCampaignId = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Compute summary metrics & active list in a single O(N) pass.
    int scheduledCount = 0;
    int sentCount = 0;
    final ongoingList = <ScheduledEmail>[];
    final completedList = <ScheduledEmail>[];
    for (final e in _history) {
      if (e.status == 'Success') {
        sentCount++;
        completedList.add(e);
      } else if (e.status.startsWith('Failed')) {
        completedList.add(e);
      } else {
        scheduledCount++;
        ongoingList.add(e);
      }
    }
    final displayedList = _selectedTab == 0
        ? ongoingList
        : (_selectedTab == 1 ? completedList : _drafts);

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBg(context),
      body: ResponsiveCenter(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
          // ── App Bar ───────────────────────────────────────────────────────
          SliverAppBar(
            floating: true,
            backgroundColor: Colors.transparent,
            flexibleSpace: buildGlassAppBarBackground(),
            elevation: 0,
            surfaceTintColor: Colors.transparent,
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AppLogo(size: 24, padding: 4, borderRadius: 10),
                const SizedBox(width: 8),
                Text(
                  'MailFlow',
                  style: TextStyle(
                    fontFamily: 'Outfit', fontSize: 19, fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary(context),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBlue.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.primaryBlue.withOpacity(0.24)),
                  ),
                  child: Text(
                    'v$_currentVersion',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.isDark(context) ? AppTheme.lightBlue : AppTheme.primaryBlue,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              Stack(
                alignment: Alignment.topRight,
                children: [
                  IconButton(
                    icon: Icon(Icons.system_update_alt_rounded,
                        color: AppTheme.isDark(context) ? AppTheme.lightBlue : AppTheme.primaryBlue, size: 22),
                    tooltip: 'Check for Updates',
                    onPressed: () => _showUpdatePopup(),
                  ),
                  if (_hasUpdate)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: const BoxDecoration(
                          color: AppTheme.errorRed,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
              IconButton(
                icon: Icon(Icons.data_usage_rounded, color: AppTheme.textSecondary(context), size: 22),
                tooltip: 'Email Limits',
                onPressed: () => Navigator.push(context, BlurredPageRoute(builder: (_) => const EmailLimitScreen())),
              ),
              ValueListenableBuilder<ThemeMode>(
                valueListenable: AppTheme.themeModeNotifier,
                builder: (context, mode, _) {
                  final IconData icon;
                  final String tooltip;
                  final ThemeMode nextMode;
                  switch (mode) {
                    case ThemeMode.light:
                      icon = Icons.light_mode_rounded;
                      tooltip = 'Theme: Light (tap for Dark)';
                      nextMode = ThemeMode.dark;
                    case ThemeMode.dark:
                      icon = Icons.dark_mode_rounded;
                      tooltip = 'Theme: Dark (tap for System)';
                      nextMode = ThemeMode.system;
                    case ThemeMode.system:
                      icon = Icons.brightness_auto_rounded;
                      tooltip = 'Theme: System Auto (tap for Light)';
                      nextMode = ThemeMode.light;
                  }
                  return IconButton(
                    tooltip: tooltip,
                    onPressed: () => AppTheme.setThemeMode(nextMode),
                    icon: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 280),
                      switchInCurve: Curves.easeOutBack,
                      switchOutCurve: Curves.easeIn,
                      transitionBuilder: (child, anim) => RotationTransition(
                        turns: Tween(begin: 0.78, end: 1.0).animate(anim),
                        child: ScaleTransition(scale: anim, child: child),
                      ),
                      child: Icon(
                        icon,
                        key: ValueKey(mode),
                        color: mode == ThemeMode.dark
                            ? AppTheme.lightBlue
                            : (mode == ThemeMode.light ? AppTheme.warningAmber : AppTheme.textSecondary(context)),
                        size: 22,
                      ),
                    ),
                  );
                },
              ),
              PopupMenuButton<String>(
                icon: ValueListenableBuilder<CloudStatus>(
                  valueListenable: BackendService.cloudStatus,
                  builder: (context, status, _) {
                    final dotColor = status == CloudStatus.connected
                        ? AppTheme.successGreen
                        : (status == CloudStatus.connecting
                            ? AppTheme.warningAmber
                            : AppTheme.errorRed);
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Icon(Icons.more_vert_rounded, color: AppTheme.textSecondary(context), size: 22),
                        Positioned(
                          right: -1,
                          top: -1,
                          child: Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: dotColor,
                              shape: BoxShape.circle,
                              border: Border.all(color: AppTheme.cardBg(context), width: 1),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
                tooltip: 'More',
                position: PopupMenuPosition.under,
                offset: const Offset(0, 8),
                popUpAnimationStyle: const AnimationStyle(
                  duration: Duration(milliseconds: 250),
                  reverseDuration: Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                ),
                color: AppTheme.cardBg(context),
                surfaceTintColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: AppTheme.border(context)),
                ),
                onSelected: (val) async {
                  if (val == 'cloud') {
                    final ok = await BackendService.verifyCloudConnection();
                    if (ok) await _loadHistory();
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          ok
                              ? 'Cloud connected (24/7 Realtime active)'
                              : 'Cloud offline — check internet connection',
                          style: const TextStyle(fontFamily: 'Inter'),
                        ),
                        backgroundColor: ok ? AppTheme.successGreen : AppTheme.errorRed,
                        behavior: SnackBarBehavior.floating,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                  if (val == 'contacts') _showAllContacts();
                  if (val == 'settings') Navigator.push(context, BlurredPageRoute(builder: (_) => const SettingsScreen()));
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'cloud',
                    child: ValueListenableBuilder<CloudStatus>(
                      valueListenable: BackendService.cloudStatus,
                      builder: (context, status, _) {
                        final isConnected = status == CloudStatus.connected;
                        final isConnecting = status == CloudStatus.connecting;
                        final clr = isConnected
                            ? AppTheme.successGreen
                            : (isConnecting ? AppTheme.warningAmber : AppTheme.errorRed);
                        final text = isConnected
                            ? 'Cloud Connected'
                            : (isConnecting ? 'Connecting...' : 'Cloud Offline (Tap)');
                        return Row(
                          children: [
                            Icon(
                              isConnected
                                  ? Icons.cloud_done_rounded
                                  : (isConnecting ? Icons.cloud_sync_rounded : Icons.cloud_off_rounded),
                              color: clr,
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                text,
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: clr,
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  PopupMenuItem(
                    value: 'contacts',
                    child: Row(
                      children: [
                        Icon(Icons.contacts_outlined,
                            color: AppTheme.isDark(context) ? AppTheme.lightBlue : AppTheme.primaryBlue, size: 18),
                        const SizedBox(width: 10),
                        Text('Saved Contacts',
                            style: TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w500, color: AppTheme.textPrimary(context))),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'settings',
                    child: Row(
                      children: [
                        Icon(Icons.settings_outlined, color: AppTheme.textSecondary(context), size: 18),
                        const SizedBox(width: 10),
                        Text('Settings & Templates',
                            style: TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w500, color: AppTheme.textPrimary(context))),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 4),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Divider(height: 1, color: AppTheme.border(context)),
            ),
          ),

          // ── Update Notification Banner (Zero overlap, dismissible) ────────
          if (_hasUpdate && !_bannerDismissed)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceBg(context),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.primaryBlue.withOpacity(0.30)),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryBlue.withOpacity(0.08),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.campaign_rounded, color: AppTheme.primaryBlue, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _showUpdatePopup(),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Update Available: v${_latestVersion ?? "New"}',
                                style: TextStyle(
                                  fontFamily: 'Outfit',
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.textPrimary(context),
                                ),
                              ),
                              const Text(
                                'Tap to download and install new features',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 11,
                                  color: AppTheme.textMid,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      ElevatedButton(
                        onPressed: () => _showUpdatePopup(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryBlue,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text('Update', style: TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(width: 4),
                      InkWell(
                        onTap: () => setState(() => _bannerDismissed = true),
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(Icons.close_rounded, size: 16, color: AppTheme.textLight),
                        ),
                      ),
                    ],
                  ),
                ).animate().fade(duration: 400.ms).slideY(begin: -0.2, end: 0.0),
              ),
            ),

          // ── In-App Event Alert Banner (Start / Done / Failed) ─────
          if (_latestAlert != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: _RealtimeEventBanner(
                  event: _latestAlert!,
                  onTap: () => _showEmailDetails(_latestAlert!.email),
                  onDismiss: () => setState(() => _latestAlert = null),
                ),
              ),
            ),

          // ── Header hero card (always visible) ──
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
              child: GestureDetector(
                onTap: () => _openScheduleModal(),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppTheme.primaryBlue, AppTheme.accentBlue],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryBlue.withOpacity(0.28),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(Icons.send_rounded, color: Colors.white, size: 26),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Schedule New Email',
                              style: TextStyle(
                                color: Colors.white, fontFamily: 'Outfit',
                                fontSize: 18, fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Tap to set up sender, recipients,\nsubject, body & time',
                              style: TextStyle(
                                color: Colors.white70, fontFamily: 'Inter', fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.18),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 20),
                      ),
                    ],
                  ),
                ).animate().fade(duration: 500.ms).slideY(begin: 0.3, end: 0.0),
              ),
            ),
          ),

          // â”€â”€ Stats row â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(
                children: [
                  _StatChip(
                    icon: Icons.schedule_rounded,
                    label: 'Scheduled',
                    value: '$scheduledCount',
                    color: AppTheme.primaryBlue,
                    onTap: () => setState(() => _selectedTab = 0),
                  ),
                  const SizedBox(width: 12),
                  _StatChip(
                    icon: Icons.check_circle_rounded,
                    label: 'Sent',
                    value: '$sentCount',
                    color: AppTheme.successGreen,
                    onTap: () => setState(() => _selectedTab = 1),
                  ),
                  const SizedBox(width: 12),
                  _StatChip(
                    icon: Icons.speed_rounded,
                    label: 'Total Per Day',
                    value: '$_totalDailySent',
                    color: _totalDailySent >= 150 ? AppTheme.errorRed : (_totalDailySent >= 100 ? AppTheme.warningAmber : AppTheme.textMid),
                    onTap: () => Navigator.push(context, BlurredPageRoute(builder: (_) => const EmailLimitScreen())),
                  ),
                ],
              ).animate(delay: 200.ms).fade(duration: 400.ms),
            ),
          ),

          // Animated Category Tabs (Ongoing / Completed / Drafts)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceBg(context),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.border(context)),
                ),
                child: Row(
                  children: [
                    _buildTabChip(0, 'Ongoing', ongoingList.length),
                    _buildTabChip(1, 'Completed', completedList.length),
                    _buildTabChip(2, 'Drafts', _drafts.length),
                  ],
                ),
              ),
            ),
          ),

          // Email list
          _isLoading && _selectedTab != 2
              ? const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                )
              : displayedList.isEmpty
                  ? SliverFillRemaining(
                      child: _selectedTab == 2
                          ? Center(
                              child: Text(
                                'No saved drafts yet',
                                style: TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppTheme.textSecondary(context)),
                              ),
                            )
                          : _EmptyState(onTap: () => _openScheduleModal()),
                    )
                  : SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final item = displayedList[index];
                            final isDraftTab = _selectedTab == 2;
                            return _EmailCard(
                              item: item,
                              index: index,
                              nowNotifier: isDraftTab ? null : _nowNotifier,
                              onTap: () => isDraftTab
                                  ? _openScheduleModal(existingEmail: item, isDraft: true)
                                  : _showEmailDetails(item),
                              onEdit: () => _openScheduleModal(existingEmail: item, isDraft: isDraftTab),
                              onResend: () => _openResendModal(item),
                              onDelete: () => isDraftTab ? _deleteDraft(item) : _deleteEmail(item),
                              onStop: () => _stopEmail(item),
                              onResume: () => _resumeEmail(item),
                            );
                          },
                          childCount: displayedList.length,
                        ),
                      ),
                    ),
        ],
      ),
    ),
    );
  }

  Widget _buildTabChip(int index, String label, int count) {
    final selected = _selectedTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedTab = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: selected ? AppTheme.primaryBlue : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Text(
              '$label ($count)',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                color: selected ? Colors.white : AppTheme.textSecondary(context),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
//  HELPER WIDGETS
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _RealtimeEventBanner extends StatelessWidget {
  final CampaignNotificationEvent event;
  final VoidCallback onTap;
  final VoidCallback onDismiss;
  const _RealtimeEventBanner({
    required this.event,
    required this.onTap,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDone = event.kind == CampaignEventKind.completed;
    final bool isFailed = event.kind == CampaignEventKind.failed;
    final Color color = isDone
        ? AppTheme.successGreen
        : (isFailed ? AppTheme.errorRed : AppTheme.primaryBlue);
    final IconData icon = isDone
        ? Icons.check_circle_rounded
        : (isFailed ? Icons.error_rounded : Icons.notifications_active_rounded);
    final String title = isDone
        ? 'Done: ${event.displayName}'
        : (isFailed ? 'Failed: ${event.displayName}' : 'Sending Started: ${event.displayName}');
    final String subtitle = isDone
        ? 'All ${event.email.sentCount}/${event.email.recipients.length} emails sent'
        : (isFailed
            ? event.email.status
            : '${event.email.recipients.length} recipient${event.email.recipients.length == 1 ? '' : 's'}'
                '${event.activeParallelCount > 1 ? ' • ${event.activeParallelCount} running in parallel' : ''}');

    return GlassContainer(
      borderRadius: 16,
      blurSigma: 14,
      color: color.withValues(alpha: 0.10),
      borderColor: color.withValues(alpha: 0.35),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Icon(icon, color: color, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Outfit',
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 11,
                          color: AppTheme.textMid,
                        ),
                      ),
                    ],
                  ),
                ),
                InkWell(
                  onTap: onDismiss,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.close_rounded, size: 16, color: AppTheme.textLight),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ).animate().fade(duration: 280.ms).blur(begin: const Offset(8, 8), end: Offset.zero, duration: 280.ms).slideY(begin: -0.15, end: 0);
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final Color color;
  final VoidCallback? onTap;
  const _StatChip({required this.icon, required this.label, required this.value, required this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.07),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(0.15)),
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 6),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(value, style: TextStyle(color: color, fontFamily: 'Outfit', fontSize: 17, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(label, style: const TextStyle(color: AppTheme.textLight, fontFamily: 'Inter', fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onTap;
  const _EmptyState({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppTheme.primaryBlue.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.mail_outline_rounded, size: 36, color: AppTheme.primaryBlue),
            ).animate().fade().scale(),
            const SizedBox(height: 20),
            const Text(
              'No emails scheduled yet',
              style: TextStyle(fontFamily: 'Outfit', fontSize: 18, fontWeight: FontWeight.w600, color: AppTheme.textDark),
            ).animate(delay: 100.ms).fade(),
            const SizedBox(height: 8),
            const Text(
              'Tap the card above to schedule\nyour first automated email',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppTheme.textLight),
            ).animate(delay: 200.ms).fade(),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: onTap,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Schedule Email'),
            ).animate(delay: 300.ms).fade().scale(),
          ],
        ),
      ),
    );

  }
}

class _EmailCard extends StatelessWidget {
  final ScheduledEmail item;
  final int index;
  final ValueNotifier<DateTime>? nowNotifier;
  final VoidCallback onTap, onEdit, onResend, onDelete, onStop, onResume;
  const _EmailCard({
    required this.item,
    required this.index,
    this.nowNotifier,
    required this.onTap,
    required this.onEdit,
    required this.onResend,
    required this.onDelete,
    required this.onStop,
    required this.onResume,
  });

  Color _statusColor() {
    if (item.status == 'Success') return AppTheme.successGreen;
    if (item.status.startsWith('Failed')) return AppTheme.errorRed;
    if (item.status == 'Paused') return Colors.grey;
    if (item.status.startsWith('Doing') || item.status.startsWith('Sending') || item.status.startsWith('Day') || item.status.startsWith('Merge Day') || item.status == 'Running') return AppTheme.primaryBlue;
    return AppTheme.warningAmber;
  }

  String _statusLabel() {
    if (item.status.startsWith('Day ')) return item.status;
    if (item.status.startsWith('Doing it...')) return item.status;
    return item.status;
  }

  bool get _isActive => item.status.startsWith('Doing') || item.status.startsWith('Sending') || item.status.startsWith('Day ') || item.status.startsWith('Merge Day') || item.status == 'Running';
  bool get _isPaused => item.status == 'Paused';
  bool get _isSuccess => item.status == 'Success';
  bool get _isFailed => item.status.startsWith('Failed');
  bool get _isPdfCampaign => item.type == 'PDF' && item.dailyLimit > 0;
  bool get _isPausable => !_isSuccess && !_isFailed;

  @override
  Widget build(BuildContext context) {
    final clr = _statusColor();
    final total = item.recipients.length;
    final sent = item.sentCount;
    final progress = total > 0 ? sent / total : 0.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: AppTheme.cardBg(context),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.border(context)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48, height: 48,
                      decoration: BoxDecoration(
                        color: clr.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        item.type == 'PDF' ? Icons.picture_as_pdf_rounded : Icons.email_rounded,
                        color: clr, size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (item.scheduleName != null && item.scheduleName!.isNotEmpty)
                                ? item.scheduleName!
                                : (item.subject.isNotEmpty ? item.subject : '(No Subject)'),
                            style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.w600, fontSize: 15, color: AppTheme.textPrimary(context)),
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Row(children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: AppTheme.primaryBlue.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                              child: Text(item.type, style: const TextStyle(fontFamily: 'Inter', fontSize: 10, color: AppTheme.primaryBlue, fontWeight: FontWeight.bold)),
                            ),
                            const SizedBox(width: 6),
                            Expanded(child: Text(
                              '${item.recipients.length} recipient${item.recipients.length == 1 ? '' : 's'}',
                              style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.textLight),
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                            )),
                          ]),
                          const SizedBox(height: 2),
                          Text(item.scheduledTime, style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.textMid)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          constraints: const BoxConstraints(maxWidth: 130),
                          decoration: BoxDecoration(
                            color: clr.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _statusLabel(),
                            style: TextStyle(color: clr, fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 10),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(children: [
                           // Resend button — show when done or failed
                          if (_isSuccess || _isFailed || item.status.startsWith('Daily limit') || item.status.startsWith('Limit Reached'))
                            _ActionBtn(icon: Icons.replay_circle_filled_rounded, color: AppTheme.primaryBlue, onTap: onResend),
                          // Edit button — show for everything except completed
                          if (!_isSuccess && !_isFailed)
                            _ActionBtn(icon: Icons.edit_rounded, color: AppTheme.primaryBlue, onTap: onEdit),
                          if (_isPausable && (_isActive || item.status == 'Scheduled'))
                            _ActionBtn(icon: Icons.pause_circle_rounded, color: AppTheme.warningAmber, onTap: onStop),
                          if (_isPausable && _isPaused)
                            _ActionBtn(icon: Icons.play_circle_rounded, color: AppTheme.successGreen, onTap: onResume),
                          const SizedBox(width: 4),
                          _ActionBtn(icon: Icons.delete_rounded, color: AppTheme.errorRed, onTap: onDelete),
                        ]),
                      ],
                    ),
                  ],
                ),
                // Live 60s pre-start countdown, sending delay ticker, or Done badge
                if (nowNotifier != null)
                  _CountdownBanner(item: item, nowNotifier: nowNotifier!),
                // Progress bar for active or multi-day PDF campaigns
                if ((_isPdfCampaign || _isActive) && !_isSuccess && total > 0) ...[
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('$sent / $total sent', style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: clr, fontWeight: FontWeight.w600)),
                      Text('${(progress * 100).toStringAsFixed(1)}%', style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: clr)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: clr.withOpacity(0.12),
                      valueColor: AlwaysStoppedAnimation<Color>(clr),
                      minHeight: 5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ).animate().fade(duration: 320.ms, delay: (index * 50).ms).blur(begin: const Offset(4, 4), end: Offset.zero, duration: 300.ms).slideX(begin: 0.04, end: 0),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _ActionBtn({required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32, height: 32,
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: color, size: 16),
      ),
    );
  }
}

class _ContactsDialog extends StatefulWidget {
  final List<SavedContact> initialContacts;
  const _ContactsDialog({required this.initialContacts});

  @override
  State<_ContactsDialog> createState() => _ContactsDialogState();
}

class _ContactsDialogState extends State<_ContactsDialog> {
  late List<SavedContact> _contacts;
  final TextEditingController _searchCtrl = TextEditingController();
  String _selectedFilter = 'All'; // All | Single | Multiple | PDF
  String _sortMode = 'Recent'; // Recent | A-Z | Z-A

  @override
  void initState() {
    super.initState();
    _contacts = List.of(widget.initialContacts);
    _searchCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Color _sourceColor(String src) {
    switch (src) {
      case 'PDF':
        return AppTheme.successGreen;
      case 'Multiple':
        return const Color(0xFF8B5CF6);
      default:
        return AppTheme.primaryBlue;
    }
  }

  List<SavedContact> get _filteredContacts {
    final query = _searchCtrl.text.trim().toLowerCase();
    final filtered = _contacts.where((c) {
      if (_selectedFilter != 'All' && !c.sources.contains(_selectedFilter)) {
        return false;
      }
      if (query.isNotEmpty && !c.email.contains(query)) {
        return false;
      }
      return true;
    }).toList();
    if (_sortMode == 'A-Z') {
      filtered.sort((a, b) => a.email.compareTo(b.email));
    } else if (_sortMode == 'Z-A') {
      filtered.sort((a, b) => b.email.compareTo(a.email));
    } else {
      // Recent: newest savedDate first, then reverse insertion order
      final rev = filtered.reversed.toList();
      rev.sort((a, b) {
        final da = a.savedDate != null ? DateHelpers.parseDmy(a.savedDate!) : null;
        final db = b.savedDate != null ? DateHelpers.parseDmy(b.savedDate!) : null;
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        return db.compareTo(da);
      });
      return rev;
    }
    return filtered;
  }

  int _countFor(String filter) {
    if (filter == 'All') return _contacts.length;
    return _contacts.where((c) => c.sources.contains(filter)).length;
  }

  Map<String, List<SavedContact>> _groupByDate(List<SavedContact> items) {
    final groups = <String, List<SavedContact>>{};
    for (final c in items) {
      final key = (c.savedDate != null && c.savedDate!.trim().isNotEmpty) ? c.savedDate!.trim() : 'Earlier';
      groups.putIfAbsent(key, () => []).add(c);
    }
    final sortedKeys = groups.keys.toList()
      ..sort((a, b) {
        final da = a == 'Earlier' ? null : DateHelpers.parseDmy(a);
        final db = b == 'Earlier' ? null : DateHelpers.parseDmy(b);
        if (da == null && db == null) return a.compareTo(b);
        if (da == null) return 1;
        if (db == null) return -1;
        return db.compareTo(da);
      });
    return {for (final k in sortedKeys) k: groups[k]!};
  }

  Future<void> _openDateContactsPopup(String dateKey, List<SavedContact> initialGroup) async {
    final accent = AppTheme.isDark(context) ? AppTheme.lightBlue : AppTheme.primaryBlue;
    final day = dateKey == 'Earlier' ? '' : DateHelpers.weekdayName(dateKey);
    final dateTitle = day.isNotEmpty ? '$dateKey ($day)' : dateKey;
    final group = List<SavedContact>.of(initialGroup);

    await showBlurredDialog<void>(
      context: context,
      builder: (popupCtx) => StatefulBuilder(
        builder: (ctx, setPopupState) {
          return Dialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 24),
            backgroundColor: AppTheme.cardBg(ctx),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 640,
                maxHeight: MediaQuery.of(ctx).size.height * 0.72,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: AppTheme.primaryBlue.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.calendar_today_rounded, size: 17, color: accent),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                dateTitle,
                                style: TextStyle(
                                  fontFamily: 'Outfit',
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.textPrimary(ctx),
                                ),
                              ),
                              Text(
                                '${group.length} ${group.length == 1 ? 'contact' : 'contacts'}',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 12,
                                  color: AppTheme.textSecondary(ctx),
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.close_rounded, color: AppTheme.textSecondary(ctx)),
                          onPressed: () => Navigator.pop(popupCtx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Divider(color: AppTheme.border(ctx), height: 1),
                    const SizedBox(height: 6),
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        physics: const BouncingScrollPhysics(),
                        itemCount: group.length,
                        separatorBuilder: (_, __) => Divider(color: AppTheme.border(ctx), height: 1),
                        itemBuilder: (_, i) {
                          final contact = group[i];
                          final sources = contact.sources.toList()..sort();
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                CircleAvatar(
                                  radius: 17,
                                  backgroundColor: AppTheme.primaryBlue.withValues(alpha: 0.12),
                                  child: Text(
                                    contact.email[0].toUpperCase(),
                                    style: TextStyle(color: accent, fontWeight: FontWeight.w700, fontSize: 13),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      SelectableText(
                                        contact.email,
                                        style: TextStyle(
                                          fontFamily: 'Inter',
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w500,
                                          color: AppTheme.textPrimary(ctx),
                                        ),
                                      ),
                                      if (sources.isNotEmpty || contact.savedTime != null) ...[
                                        const SizedBox(height: 5),
                                        Wrap(
                                          spacing: 5,
                                          runSpacing: 4,
                                          crossAxisAlignment: WrapCrossAlignment.center,
                                          children: [
                                            if (contact.savedTime != null)
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: AppTheme.surfaceBg(ctx),
                                                  borderRadius: BorderRadius.circular(6),
                                                  border: Border.all(color: AppTheme.border(ctx)),
                                                ),
                                                child: Text(
                                                  contact.savedTime!,
                                                  style: TextStyle(
                                                    fontFamily: 'Inter',
                                                    fontSize: 10.5,
                                                    fontWeight: FontWeight.w600,
                                                    color: AppTheme.textSecondary(ctx),
                                                  ),
                                                ),
                                              ),
                                            ...sources.map((s) {
                                              final c = _sourceColor(s);
                                              return Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: c.withValues(alpha: 0.12),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  s,
                                                  style: TextStyle(fontFamily: 'Inter', fontSize: 10.5, fontWeight: FontWeight.w700, color: c),
                                                ),
                                              );
                                            }),
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Copy email',
                                  icon: Icon(Icons.copy_rounded, size: 17, color: AppTheme.textSecondary(ctx)),
                                  onPressed: () {
                                    Clipboard.setData(ClipboardData(text: contact.email));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Copied ${contact.email}')),
                                    );
                                  },
                                ),
                                IconButton(
                                  tooltip: 'Remove contact',
                                  icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppTheme.errorRed),
                                  onPressed: () async {
                                    final confirm = await showBlurredDialog<bool>(
                                      context: ctx,
                                      builder: (dCtx) => AlertDialog(
                                        title: const Text('Delete Contact?', style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.w600)),
                                        content: Text('Remove "${contact.email}" from saved contacts?', style: const TextStyle(fontFamily: 'Inter')),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(dCtx, false),
                                            child: const Text('Cancel', style: TextStyle(fontFamily: 'Inter', color: AppTheme.textMid)),
                                          ),
                                          ElevatedButton(
                                            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorRed, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                                            onPressed: () => Navigator.pop(dCtx, true),
                                            child: const Text('Delete', style: TextStyle(fontFamily: 'Inter', color: Colors.white)),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (confirm != true) return;
                                    await StorageService.deleteContact(contact.email);
                                    if (!mounted) return;
                                    setState(() => _contacts.removeWhere((c) => c.email == contact.email));
                                    if (!popupCtx.mounted) return;
                                    setPopupState(() => group.removeWhere((c) => c.email == contact.email));
                                    if (group.isEmpty) {
                                      Navigator.pop(popupCtx);
                                    }
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ).animate().scale(duration: 220.ms, curve: Curves.easeOutBack).fade();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = _filteredContacts;
    final dateGroups = _groupByDate(visible);
    final dateEntries = dateGroups.entries.toList();
    final accent = AppTheme.isDark(context) ? AppTheme.lightBlue : AppTheme.primaryBlue;
    const filters = ['All', 'Single', 'Multiple', 'PDF'];

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      backgroundColor: AppTheme.cardBg(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: MediaQuery.of(context).size.height * 0.78,
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Saved Contacts',
                          style: TextStyle(
                            fontFamily: 'Outfit',
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary(context),
                          ),
                        ),
                        Text(
                          '${visible.length} of ${_contacts.length} saved • ${dateEntries.length} ${dateEntries.length == 1 ? 'day' : 'days'}',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12,
                            color: AppTheme.textSecondary(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Sort',
                    icon: Icon(Icons.sort_rounded, color: AppTheme.textSecondary(context), size: 20),
                    position: PopupMenuPosition.under,
                    onSelected: (val) => setState(() => _sortMode = val),
                    itemBuilder: (_) => ['Recent', 'A-Z', 'Z-A']
                        .map((m) => PopupMenuItem(
                              value: m,
                              child: Row(
                                children: [
                                  Icon(
                                    _sortMode == m ? Icons.check_rounded : Icons.sort_by_alpha_rounded,
                                    size: 16,
                                    color: _sortMode == m ? accent : AppTheme.textSecondary(context),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(m, style: const TextStyle(fontFamily: 'Inter', fontSize: 13)),
                                ],
                              ),
                            ))
                        .toList(),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: AppTheme.textSecondary(context)),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: 'Search saved emails...',
                  prefixIcon: const Icon(Icons.search_rounded, size: 18),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 16),
                          onPressed: () => _searchCtrl.clear(),
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: filters.map((f) {
                    final selected = _selectedFilter == f;
                    final count = _countFor(f);
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(
                          '$f ($count)',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: selected ? Colors.white : AppTheme.textPrimary(context),
                          ),
                        ),
                        selected: selected,
                        selectedColor: AppTheme.primaryBlue,
                        backgroundColor: AppTheme.surfaceBg(context),
                        side: BorderSide(color: selected ? AppTheme.primaryBlue : AppTheme.border(context)),
                        showCheckmark: false,
                        onSelected: (_) => setState(() => _selectedFilter = f),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 10),
              Divider(color: AppTheme.border(context), height: 1),
              const SizedBox(height: 10),
              Expanded(
                child: dateEntries.isEmpty
                    ? Center(
                        child: Text(
                          _contacts.isEmpty
                              ? 'No saved contacts yet.\nEmails from Single, Multiple & PDF schedules appear here.'
                              : 'No contacts match "$_selectedFilter"${_searchCtrl.text.isNotEmpty ? ' for "${_searchCtrl.text}"' : ''}.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppTheme.textSecondary(context)),
                        ),
                      )
                    : ListView.separated(
                        physics: const BouncingScrollPhysics(),
                        itemCount: dateEntries.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) {
                          final entry = dateEntries[i];
                          final dateKey = entry.key;
                          final group = entry.value;
                          final day = dateKey == 'Earlier' ? '' : DateHelpers.weekdayName(dateKey);
                          final dateLabel = day.isNotEmpty ? '$dateKey ($day)' : dateKey;
                          final latestTime = group.map((c) => c.savedTime).whereType<String>().firstOrNull;
                          final groupSources = group.expand((c) => c.sources).toSet().toList()..sort();

                          return Material(
                            color: AppTheme.surfaceBg(context),
                            borderRadius: BorderRadius.circular(14),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () => _openDateContactsPopup(dateKey, group),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: AppTheme.border(context)),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 38,
                                      height: 38,
                                      decoration: BoxDecoration(
                                        color: AppTheme.primaryBlue.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Icon(Icons.calendar_month_rounded, size: 19, color: accent),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  dateLabel,
                                                  style: TextStyle(
                                                    fontFamily: 'Outfit',
                                                    fontSize: 14.5,
                                                    fontWeight: FontWeight.w700,
                                                    color: AppTheme.textPrimary(context),
                                                  ),
                                                ),
                                              ),
                                              if (latestTime != null) ...[
                                                const SizedBox(width: 8),
                                                Text(
                                                  latestTime,
                                                  style: TextStyle(
                                                    fontFamily: 'Inter',
                                                    fontSize: 11.5,
                                                    fontWeight: FontWeight.w500,
                                                    color: AppTheme.textSecondary(context),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                          if (groupSources.isNotEmpty) ...[
                                            const SizedBox(height: 5),
                                            Wrap(
                                              spacing: 5,
                                              runSpacing: 4,
                                              children: groupSources.map((s) {
                                                final c = _sourceColor(s);
                                                return Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                                  decoration: BoxDecoration(
                                                    color: c.withValues(alpha: 0.12),
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: Text(
                                                    s,
                                                    style: TextStyle(fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w700, color: c),
                                                  ),
                                                );
                                              }).toList(),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: AppTheme.primaryBlue.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        '${group.length}',
                                        style: TextStyle(
                                          fontFamily: 'Inter',
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: accent,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: AppTheme.textSecondary(context)),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    ).animate().scale(duration: 250.ms, curve: Curves.easeOutBack).fade();
  }
}

class _CountdownBanner extends StatelessWidget {
  final ScheduledEmail item;
  final ValueNotifier<DateTime> nowNotifier;
  const _CountdownBanner({required this.item, required this.nowNotifier});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DateTime>(
      valueListenable: nowNotifier,
      builder: (context, now, _) {
        if (item.status == 'Success') {
          return Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.successGreen.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.successGreen.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, size: 15, color: AppTheme.successGreen),
                  const SizedBox(width: 6),
                  Text(
                    'Done • ${item.sentCount}/${item.recipients.length} sent',
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.successGreen,
                    ),
                  ),
                ],
              ),
            ).animate().scale(begin: const Offset(0.96, 0.96), duration: 240.ms, curve: Curves.easeOutBack).fade(),
          );
        }

        if (item.status == 'Scheduled') {
          final startDt = BackendService.parseScheduleDateTime(item.scheduledDate, item.scheduledTime);
          if (startDt == null) return const SizedBox.shrink();
          final diffSec = startDt.difference(now).inSeconds;
          if (diffSec > 60) return const SizedBox.shrink();

          final isDueNow = diffSec <= 0;
          final pct = isDueNow ? 1.0 : ((60 - diffSec) / 60).clamp(0.0, 1.0);
          final label = isDueNow ? 'Starting now...' : 'Starting in ${diffSec}s';
          return Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.timer_rounded, size: 14, color: AppTheme.warningAmber),
                    const SizedBox(width: 5),
                    Text(
                      label,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.warningAmber,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: isDueNow ? null : pct,
                    backgroundColor: AppTheme.warningAmber.withValues(alpha: 0.16),
                    valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.warningAmber),
                    minHeight: 4,
                  ),
                ),
              ],
            ).animate().fade(duration: 200.ms),
          );
        }

        if (SendNotificationMonitor.isActiveStatus(item.status) && item.delayMinutes > 0) {
          final nextAt = item.nextSendAt;
          final rawSec = nextAt != null
              ? nextAt.difference(now).inSeconds.clamp(0, item.delayMinutes * 60)
              : (60 - now.second);
          final totalGapSec = item.delayMinutes * 60;
          final pct = totalGapSec > 0 ? ((totalGapSec - rawSec) / totalGapSec).clamp(0.0, 1.0) : 0.0;
          return Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.bolt_rounded, size: 14, color: AppTheme.primaryBlue),
                    const SizedBox(width: 4),
                    Text(
                      rawSec > 0
                          ? 'Next email in ${rawSec}s (${item.delayMinutes}m gap)'
                          : 'Sending next email now...',
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primaryBlue,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: rawSec > 0 ? pct : null,
                    backgroundColor: AppTheme.primaryBlue.withValues(alpha: 0.14),
                    valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryBlue),
                    minHeight: 4,
                  ),
                ),
              ],
            ),
          );
        }

        return const SizedBox.shrink();
      },
    );
  }
}

class _DetailsDialog extends StatefulWidget {
  final ScheduledEmail email;
  final Color primaryColor;
  final ValueNotifier<List<ScheduledEmail>> historyNotifier;
  final ValueNotifier<DateTime>? nowNotifier;
  const _DetailsDialog({
    required this.email,
    required this.primaryColor,
    required this.historyNotifier,
    this.nowNotifier,
  });

  @override
  State<_DetailsDialog> createState() => _DetailsDialogState();
}

class _DetailsDialogState extends State<_DetailsDialog> {
  String? _activePanel; // null = summary, 'body' = Body, 'recipients' = Recipients

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final popupHeight = (screenSize.height * 0.64).clamp(380.0, 560.0);
    return ValueListenableBuilder<List<ScheduledEmail>>(
      valueListenable: widget.historyNotifier,
      builder: (context, history, _) {
        final email = history.where((e) => e.id == widget.email.id).firstOrNull ?? widget.email;
        final isActive = SendNotificationMonitor.isActiveStatus(email.status);
        final total = email.recipients.length;
        final sent = email.sentCount.clamp(0, total);
        final progress = total > 0 ? sent / total : 0.0;
        final Color statusColor = email.status == 'Success'
            ? AppTheme.successGreen
            : (email.status.startsWith('Failed')
                ? AppTheme.errorRed
                : (isActive ? AppTheme.primaryBlue : AppTheme.warningAmber));

        final startDt = BackendService.parseScheduleDateTime(email.scheduledDate, email.scheduledTime);
        final isPreStart = email.status == 'Scheduled' &&
            startDt != null &&
            startDt.difference(DateTime.now()).inSeconds <= 60;
        final isRunningOrStarting = isActive || isPreStart;

        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 28),
          backgroundColor: AppTheme.cardBg(context),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(
              color: isRunningOrStarting
                  ? AppTheme.primaryBlue.withValues(alpha: 0.35)
                  : AppTheme.border(context),
            ),
          ),
          elevation: 8,
          child: SizedBox(
            width: 420,
            height: popupHeight,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, anim) => AnimatedBuilder(
                  animation: anim,
                  child: child,
                  builder: (context, child) {
                    final sigma = (1.0 - anim.value) * 8.0;
                    return ImageFiltered(
                      imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
                      child: FadeTransition(
                        opacity: anim,
                        child: ScaleTransition(
                          scale: Tween<double>(begin: 0.96, end: 1.0).animate(anim),
                          child: child,
                        ),
                      ),
                    );
                  },
                ),
                child: _activePanel == 'body'
                    ? _buildSubPanel(
                        key: const ValueKey('body'),
                        title: 'Email Body',
                        icon: Icons.article_outlined,
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.all(14),
                          child: SelectableText(
                            email.body.isEmpty ? '(Empty body)' : email.body,
                            style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppTheme.textPrimary(context), height: 1.45),
                          ),
                        ),
                      )
                    : _activePanel == 'recipients'
                        ? _buildSubPanel(
                            key: const ValueKey('recipients'),
                            title: 'Recipients (${email.recipients.length})',
                            icon: Icons.group_rounded,
                            child: ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              physics: const BouncingScrollPhysics(),
                              itemCount: email.recipients.length,
                              itemBuilder: (ctx, idx) {
                                final r = email.recipients[idx];
                                final rStatus = email.recipientStatuses[r];
                                final sendDt = email.recipientSendTimes[r] ??
                                    startDt?.add(Duration(minutes: idx * email.delayMinutes));
                                final timeLabel = sendDt == null
                                    ? null
                                    : () {
                                        final h = sendDt.hour % 12 == 0 ? 12 : sendDt.hour % 12;
                                        final m = sendDt.minute.toString().padLeft(2, '0');
                                        final ap = sendDt.hour >= 12 ? 'PM' : 'AM';
                                        return '${h.toString().padLeft(2, '0')}:$m $ap';
                                      }();
                                IconData icon;
                                Color color;
                                if (rStatus == 'sent' || (rStatus == null && email.status == 'Success')) {
                                  icon = Icons.check_circle_rounded; color = AppTheme.successGreen;
                                } else if (rStatus == 'inProcess') {
                                  icon = Icons.sync_rounded; color = AppTheme.primaryBlue;
                                } else if (rStatus != null && rStatus.startsWith('failed')) {
                                  icon = Icons.cancel_rounded; color = AppTheme.errorRed;
                                } else {
                                  icon = Icons.radio_button_unchecked_rounded; color = AppTheme.textLight;
                                }
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 6),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 28, height: 28,
                                        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
                                        child: Icon(icon, size: 16, color: color),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(r, style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppTheme.textPrimary(context))),
                                      ),
                                      if (timeLabel != null) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: color.withValues(alpha: 0.10),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            timeLabel,
                                            style: TextStyle(
                                              fontFamily: 'Inter',
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: rStatus == 'sent' || (rStatus == null && email.status == 'Success')
                                                  ? AppTheme.successGreen
                                                  : AppTheme.textSecondary(ctx),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                );
                              },
                            ),
                          )
                        : Padding(
                            key: const ValueKey('summary'),
                            padding: const EdgeInsets.all(20),
                            child: SingleChildScrollView(
                              physics: const BouncingScrollPhysics(),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (widget.nowNotifier != null)
                                    _CountdownBanner(item: email, nowNotifier: widget.nowNotifier!),
                                  if (isActive && total > 0) ...[
                                    const SizedBox(height: 10),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text('Live Sending Progress', style: TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primaryBlue)),
                                        Text('$sent / $total (${(progress * 100).toStringAsFixed(0)}%)', style: const TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.primaryBlue)),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: LinearProgressIndicator(
                                        value: progress > 0 ? progress : null,
                                        backgroundColor: AppTheme.primaryBlue.withValues(alpha: 0.14),
                                        valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryBlue),
                                        minHeight: 6,
                                      ),
                                    ),
                                  ],
                                  if (isRunningOrStarting) const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              (email.scheduleName != null && email.scheduleName!.isNotEmpty) ? email.scheduleName! : 'Schedule Details',
                                              style: TextStyle(fontFamily: 'Outfit', fontSize: 19, fontWeight: FontWeight.w700, color: AppTheme.textPrimary(context)),
                                            ),
                                            const SizedBox(height: 6),
                                            Wrap(
                                              spacing: 6,
                                              runSpacing: 4,
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                  decoration: BoxDecoration(color: AppTheme.primaryBlue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                                                  child: Text(email.isMerged ? 'Merged PDF' : email.type, style: const TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppTheme.primaryBlue, fontWeight: FontWeight.bold)),
                                                ),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                  decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                                                  child: Text(email.status, style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: statusColor, fontWeight: FontWeight.w700)),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      IconButton(icon: const Icon(Icons.close, color: AppTheme.textMid), onPressed: () => Navigator.pop(context)),
                                    ],
                                  ),
                                  const SizedBox(height: 14),
                                  _infoRow(Icons.account_circle_outlined, 'Sender', email.senderEmail),
                                  if (!isRunningOrStarting) ...[
                                    if (email.createdAt != null) _infoRow(Icons.add_task_rounded, 'Created On', email.createdAt!),
                                    Builder(builder: (context) {
                                      final wd = DateHelpers.weekdayName(email.scheduledDate);
                                      return _infoRow(Icons.calendar_today_rounded, 'Date', '${email.scheduledDate}${wd.isNotEmpty ? ' ($wd)' : ''}');
                                    }),
                                    _infoRow(Icons.access_time_rounded, 'Time', email.scheduledTime),
                                    if (email.type == 'PDF' || email.isMerged)
                                      _infoRow(Icons.speed_rounded, 'Daily Limit', '${email.dailyLimit > 0 ? email.dailyLimit : 40} emails / day'),
                                  ],
                                  if (email.type == 'Multiple' || email.type == 'PDF' || email.isMerged)
                                    _infoRow(Icons.timer_outlined, 'Delay', '${email.delayMinutes} min between emails'),
                                  if (!isRunningOrStarting) ...[
                                    _infoRow(Icons.subject_rounded, 'Subject', email.subject.isEmpty ? '(No Subject)' : email.subject),
                                    const SizedBox(height: 8),
                                    _panelTrigger(
                                      icon: Icons.article_outlined,
                                      label: 'Body',
                                      onTap: () => setState(() => _activePanel = 'body'),
                                    ),
                                    const SizedBox(height: 10),
                                  ],
                                  _panelTrigger(
                                    icon: Icons.group_rounded,
                                    label: 'Recipients (${email.recipients.length})',
                                    highlighted: true,
                                    onTap: () => setState(() => _activePanel = 'recipients'),
                                  ),
                                ],
                              ),
                            ),
                          ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _panelTrigger({
    required IconData icon,
    required String label,
    bool highlighted = false,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: highlighted ? AppTheme.primaryBlue.withValues(alpha: 0.06) : AppTheme.surfaceBg(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: highlighted ? AppTheme.primaryBlue.withValues(alpha: 0.3) : AppTheme.border(context)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppTheme.primaryBlue),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label, style: const TextStyle(fontFamily: 'Outfit', fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.primaryBlue)),
            ),
            const Icon(Icons.open_in_full_rounded, color: AppTheme.primaryBlue, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildSubPanel({
    required Key key,
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Padding(
      key: key,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.primaryBlue),
                onPressed: () => setState(() => _activePanel = null),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 10),
              Icon(icon, size: 18, color: AppTheme.primaryBlue),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title, style: TextStyle(fontFamily: 'Outfit', fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.textPrimary(context))),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: AppTheme.textMid),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppTheme.surfaceBg(context),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.border(context)),
              ),
              child: child,
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppTheme.textSecondary(context)),
          const SizedBox(width: 16),
          SizedBox(width: 72, child: Text(label, style: TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppTheme.textSecondary(context)))),
          const SizedBox(width: 8),
          Expanded(child: Text(value, style: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary(context), height: 1.4))),
        ],
      ),
    );
  }

}


// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
//  SCHEDULE MODAL
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _ScheduleModal extends StatefulWidget {
  final ScheduledEmail? editEmail;
  final bool isDraft;
  final Set<String> existingScheduleNames;
  final List<ScheduledEmail> existingDrafts;
  final VoidCallback? onDraftChanged;
  final void Function(ScheduledEmail draft)? onOpenDraft;
  const _ScheduleModal({
    this.editEmail,
    this.isDraft = false,
    this.existingScheduleNames = const {},
    this.existingDrafts = const [],
    this.onDraftChanged,
    this.onOpenDraft,
  });

  @override
  State<_ScheduleModal> createState() => _ScheduleModalState();
}

class _ScheduleModalState extends State<_ScheduleModal>
    with WidgetsBindingObserver {
  late String _sendType;
  final _senderController = TextEditingController();
  List<String> _suggestedSenders = [];
  bool _isAuthenticated = false;
  bool _isAuthenticating = false; // Shows spinner while Google sign-in is in progress
  late final GoogleSignIn _googleSignIn = GoogleSignIn(
    clientId: (kIsWeb || (!kIsWeb && Platform.isMacOS)) && AppConfig.googleWebClientId.isNotEmpty
        ? AppConfig.googleWebClientId
        : null,
    serverClientId: (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) && AppConfig.googleWebClientId.isNotEmpty
        ? AppConfig.googleWebClientId
        : null,
    forceCodeForRefreshToken: true,
    scopes: const ['email', 'https://www.googleapis.com/auth/gmail.send'],
  );

  final _scheduleNameController = TextEditingController();

  List<TemplateItem> _savedSubjects = [];
  List<TemplateItem> _savedBodies = [];
  bool _useSavedFormat = false;
  TemplateItem? _selectedSubject;
  TemplateItem? _selectedBody;

  List<TextEditingController> _emailControllers = [TextEditingController()];
  String? _pdfPath;
  List<String> _pdfEmails = [];

  final _subjectController = TextEditingController();
  final _bodyController = TextEditingController();
  final _dailyLimitController = TextEditingController(text: '40');
  final _dateController = TextEditingController();
  final _timeController = TextEditingController();
  bool _isAm = true;
  int _delayMinutes = 2; // Default 2 min between emails (anti-spam)
  bool _isCustomDelay = false;
  final _customDelayController = TextEditingController();
  String? _senderMsg; bool _isSenderErr = false;
  String? _recipientMsg; bool _isRecipientErr = false;
  String? _dateMsg; bool _isDateErr = false;
  String? _scheduleNameMsg; bool _isScheduleNameErr = false;
  String? _subjectMsg; bool _isSubjectErr = false;
  String? _bodyMsg; bool _isBodyErr = false;
  String? _dailyLimitMsg; bool _isDailyLimitErr = false;
  bool _showPdfEmails = false;
  // For inline adding & editing of PDF emails
  final TextEditingController _addPdfEmailController = TextEditingController();
  final List<TextEditingController> _pdfEmailControllers = [];
  bool _isPdfEmailEditing = false;
  int _currentSenderUsage = 0;
  bool _dateQuotaFull = false;
  bool _isSubmitting = false;
  bool _savedOrSubmitted = false;
  bool _isScheduleNameDuplicate = false;
  late final String _draftId = (widget.isDraft && widget.editEmail != null)
      ? widget.editEmail!.id
      : 'draft_${DateTime.now().millisecondsSinceEpoch}';
  Timer? _senderLookupDebounce;

  bool get _isDraftNameLocked =>
      widget.isDraft && (widget.editEmail?.scheduleName?.trim().isNotEmpty ?? false);

  void _onScheduleNameChanged() {
    if (_isDraftNameLocked) return;
    final norm = _scheduleNameController.text.trim().toLowerCase();
    final dup = norm.isNotEmpty && widget.existingScheduleNames.contains(norm);
    if (dup != _isScheduleNameDuplicate || _scheduleNameMsg != null) {
      setState(() {
        _isScheduleNameDuplicate = dup;
        if (dup) {
          _scheduleNameMsg = null;
          _isScheduleNameErr = false;
        }
      });
    } else {
      // Rebuild to show/hide live uniqueness badge as user types
      setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSenders();
    _loadTemplates();
    _senderController.addListener(_onSenderChanged);
    _dateController.addListener(_onSenderChanged); // recompute when date changes
    _scheduleNameController.addListener(_onScheduleNameChanged);
    if (widget.editEmail != null) {
      final e = widget.editEmail!;
      _sendType = e.type;
      _senderController.text = e.senderEmail;
      _isAuthenticated = !widget.isDraft;
      _subjectController.text = e.subject;
      _bodyController.text = e.body;
      _dateController.text = e.scheduledDate;
      _isAm = e.scheduledTime.isEmpty || e.scheduledTime.contains('AM');
      _timeController.text = e.scheduledTime.replaceAll(RegExp(r' AM| PM'), '');
      if (_sendType == 'Single' || _sendType == 'Multiple') {
        _emailControllers = e.recipients.isNotEmpty
            ? e.recipients.map((r) => TextEditingController(text: r)).toList()
            : [TextEditingController()];
      } else if (_sendType == 'PDF') {
        _pdfPath = e.pdfName ?? (e.recipients.isNotEmpty ? 'Extracted (${e.recipients.length} emails)' : null);
        _pdfEmails = e.recipients;
        _dailyLimitController.text = e.dailyLimit > 0 ? e.dailyLimit.toString() : '40';
      }
      _delayMinutes = e.delayMinutes;
      if (!const [2, 4, 6, 8].contains(_delayMinutes) && _delayMinutes > 0) {
        _isCustomDelay = true;
        _customDelayController.text = '$_delayMinutes';
      }
      _scheduleNameController.text = e.scheduleName ?? '';
      _isScheduleNameDuplicate = !_isDraftNameLocked &&
          _scheduleNameController.text.trim().isNotEmpty &&
          widget.existingScheduleNames.contains(_scheduleNameController.text.trim().toLowerCase());
    } else {
      _sendType = 'Single';
    }
  }

  Future<void> _loadTemplates() async {
    final templates = await StorageService.getTemplates();
    setState(() {
      _savedSubjects = templates.where((t) => t.type == 'Subject').toList();
      _savedBodies = templates.where((t) => t.type == 'Body').toList();
    });
  }

  Future<void> _loadSenders() async {
    final s = await StorageService.getSenderEmails();
    if (!mounted) return;
    final current = _senderController.text.trim().toLowerCase();
    setState(() {
      _suggestedSenders = s;
      if (current.isNotEmpty && s.any((e) => e.toLowerCase() == current)) {
        _isAuthenticated = true;
      }
    });
  }

  void _onSenderChanged() {
    _senderLookupDebounce?.cancel();
    final email = _senderController.text.trim().toLowerCase();
    final alreadyAuthed = email.isNotEmpty && _suggestedSenders.any((s) => s.toLowerCase() == email);
    if (alreadyAuthed && !_isAuthenticated && mounted) {
      setState(() => _isAuthenticated = true);
    }
    if (!_isValidEmail(email)) {
      if (mounted) {
        setState(() {
          _currentSenderUsage = 0;
          _dateQuotaFull = false;
        });
      }
      return;
    }
    _senderLookupDebounce = Timer(const Duration(milliseconds: 300), () async {
      int sentCount = 0;
      try {
        final limits = await BackendService.fetchDailyLimits();
        sentCount = limits[email] ?? 0;
      } catch (_) {}
      if (mounted) {
        setState(() {
          _currentSenderUsage = sentCount;
          _dateQuotaFull = sentCount >= 50;
        });
      }
    });
  }

  @override
  void didChangeMetrics() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // Detach IME cleanly before backgrounding so Android never leaves a blank keyboard gap on return.
      FocusManager.instance.primaryFocus?.unfocus();
      if (!_savedOrSubmitted) {
        unawaited(_autoSaveDraftIfNeeded());
      }
    } else if (state == AppLifecycleState.resumed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (MediaQuery.viewInsetsOf(context).bottom == 0) {
          FocusManager.instance.primaryFocus?.unfocus();
        }
        setState(() {});
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _senderLookupDebounce?.cancel();
    _senderController.dispose();
    _scheduleNameController.dispose();
    _addPdfEmailController.dispose();
    for (var c in _emailControllers) c.dispose();
    for (var c in _pdfEmailControllers) c.dispose();
    _subjectController.dispose();
    _bodyController.dispose();
    _dailyLimitController.dispose();
    _dateController.dispose();
    _timeController.dispose();
    _customDelayController.dispose();
    super.dispose();
  }

  Future<void> _authenticateWithGoogle(String currentEmail) async {
    if (!_isValidEmail(currentEmail)) {
      _showMsg('sender', 'Please enter a valid Sender Email first.');
      return;
    }
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
      _showMsg(
        'sender',
        'Connect this Gmail sender once on Android, iOS, macOS, or Web — once linked, Windows manages schedules in the Cloud automatically.',
      );
      return;
    }
    setState(() => _isAuthenticating = true);
    try {
      // Force sign-out first so user can choose the correct account
      await _googleSignIn.signOut();
      final account = await _googleSignIn.signIn();
      if (account != null) {
        final authCode = account.serverAuthCode;
        if (authCode == null || authCode.isEmpty) {
          if (mounted) setState(() => _isAuthenticating = false);
          _showMsg('sender', 'Missing Google offline auth code. Please retry Google Sign-In.');
          return;
        }
        await BackendService.exchangeServerAuthCode(authCode);
        if (mounted) {
          setState(() {
            _isAuthenticated = true;
            _isAuthenticating = false;
            _senderController.text = account.email;
          });
        }
        await StorageService.saveSenderEmail(account.email);
        _showMsg('sender', 'Cloud connected as ${account.email}!', isError: false);
      } else {
        if (mounted) setState(() => _isAuthenticating = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isAuthenticating = false);
      _showMsg('sender', 'Authentication failed: $e');
    }
  }

  bool _isValidEmail(String e) =>
      RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$').hasMatch(e.trim());

  Future<void> _pickPdf() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );
    if (result != null) {
      List<String> emails = [];
      if (result.files.single.bytes != null) {
        emails = await PdfParser.extractEmailsFromPdfBytes(result.files.single.bytes!);
      } else if (result.files.single.path != null) {
        final bytes = await File(result.files.single.path!).readAsBytes();
        emails = await PdfParser.extractEmailsFromPdfBytes(bytes);
      }
      // Build controllers for editing
      for (var c in _pdfEmailControllers) c.dispose();
      _pdfEmailControllers.clear();
      for (final e in emails) _pdfEmailControllers.add(TextEditingController(text: e));
      setState(() { _pdfPath = result.files.single.name; _pdfEmails = emails; _showPdfEmails = true; });
      if (emails.isNotEmpty) await StorageService.saveContacts(emails, source: 'PDF');
    }
  }

  /// Syncs edited PDF email controllers back into [_pdfEmails], validating & deduplicating.
  bool _syncPdfEdits() {
    final next = <String>[];
    final seen = <String>{};
    for (final c in _pdfEmailControllers) {
      final e = c.text.trim().toLowerCase();
      if (e.isEmpty) continue;
      if (!_isValidEmail(e)) {
        _showMsg('recipient', 'Invalid email in PDF list: $e');
        return false;
      }
      if (seen.add(e)) next.add(e);
    }
    setState(() {
      _pdfEmails = next;
      _isPdfEmailEditing = false;
    });
    return true;
  }

  /// Adds one or more comma/space/newline-separated emails to [_pdfEmails] and saves them.
  Future<void> _addMorePdfEmails() async {
    final raw = _addPdfEmailController.text.trim();
    if (raw.isEmpty) return;
    if (_isPdfEmailEditing && !_syncPdfEdits()) return;

    final parts = raw.split(RegExp(r'[\s,;]+')).map((e) => e.trim().toLowerCase()).where((e) => e.isNotEmpty);
    final existing = _pdfEmails.map((e) => e.toLowerCase()).toSet();
    final added = <String>[];
    final invalid = <String>[];

    for (final e in parts) {
      if (!_isValidEmail(e)) {
        invalid.add(e);
      } else if (existing.add(e)) {
        added.add(e);
      }
    }

    if (invalid.isNotEmpty) {
      _showMsg('recipient', 'Invalid email: ${invalid.first}');
      return;
    }
    if (added.isEmpty) {
      _addPdfEmailController.clear();
      _showMsg('recipient', 'Email already in list.', isError: false);
      return;
    }

    setState(() {
      _pdfEmails.addAll(added);
      for (final e in added) {
        _pdfEmailControllers.add(TextEditingController(text: e));
      }
      _showPdfEmails = true;
      _addPdfEmailController.clear();
    });
    await StorageService.saveContacts(added, source: 'PDF');
    _showMsg('recipient', 'Added ${added.length} email(s) to PDF list.', isError: false);
  }

  void _showMsg(String field, String msg, {bool isError = true}) {
    if (!mounted) return;
    setState(() {
      if (field == 'sender') { _senderMsg = msg; _isSenderErr = isError; }
      else if (field == 'recipient') { _recipientMsg = msg; _isRecipientErr = isError; }
      else if (field == 'date') { _dateMsg = msg; _isDateErr = isError; }
      else if (field == 'scheduleName') { _scheduleNameMsg = msg; _isScheduleNameErr = isError; }
      else if (field == 'subject') { _subjectMsg = msg; _isSubjectErr = isError; }
      else if (field == 'body') { _bodyMsg = msg; _isBodyErr = isError; }
    });
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          if (field == 'sender' && _senderMsg == msg) _senderMsg = null;
          else if (field == 'recipient' && _recipientMsg == msg) _recipientMsg = null;
          else if (field == 'date' && _dateMsg == msg) _dateMsg = null;
          else if (field == 'scheduleName' && _scheduleNameMsg == msg) _scheduleNameMsg = null;
          else if (field == 'subject' && _subjectMsg == msg) _subjectMsg = null;
          else if (field == 'body' && _bodyMsg == msg) _bodyMsg = null;
        });
      }
    });
  }

  Widget _buildFieldMsg(String? msg, bool isError) {
    if (msg == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isError ? AppTheme.errorRed.withOpacity(0.1) : AppTheme.successGreen.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isError ? AppTheme.errorRed.withOpacity(0.3) : AppTheme.successGreen.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
              color: isError ? AppTheme.errorRed : AppTheme.successGreen, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(msg, style: TextStyle(color: isError ? AppTheme.errorRed : AppTheme.successGreen, fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 13))),
        ],
      ),
    ).animate().fade().slideY(begin: -0.2, end: 0);
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    final sender = _senderController.text.trim();
    if (!_isValidEmail(sender) || !_isAuthenticated) { _showMsg('sender', 'Authenticate a valid sender email first.'); return; }
    if (!DateHelpers.isFutureDmyTime(_dateController.text, _timeController.text, _isAm)) { _showMsg('date', 'Enter a valid future date and time.'); return; }

    // Prevent using an exhausted sender (50/50) for Today; auto-transfer to Tomorrow
    if (_currentSenderUsage >= 50 && _dateController.text.trim() == DateHelpers.todayDmy()) {
      final tmr = DateTime.now().add(const Duration(days: 1));
      _dateController.text =
          '${tmr.day.toString().padLeft(2, '0')}/${tmr.month.toString().padLeft(2, '0')}/${tmr.year}';
      _showMsg('date', 'Daily 50/50 limit reached today — date moved to Tomorrow. Tap Save to confirm.');
      return;
    }

    List<String> recipients = [];
    if (_sendType == 'PDF') {
      if (_isPdfEmailEditing && !_syncPdfEdits()) return;
      if (_pdfEmails.isEmpty) { _showMsg('recipient', 'No emails extracted from PDF.'); return; }
      recipients = _pdfEmails.toSet().toList();
    } else {
      for (var c in _emailControllers) {
        final e = c.text.trim();
        if (e.isNotEmpty) {
          if (!_isValidEmail(e)) { _showMsg('recipient', 'Invalid email: $e'); return; }
          recipients.add(e);
        }
      }
      recipients = recipients.toSet().toList();
      if (recipients.isEmpty) { _showMsg('recipient', 'Add at least one recipient.'); return; }
    }
    
    if (_scheduleNameController.text.trim().isNotEmpty && _isScheduleNameDuplicate) {
      _showMsg('scheduleName', 'Schedule name already exists. Please use a unique name.');
      return;
    }
    if (_sendType == 'Multiple' || _sendType == 'PDF') {
      if (_scheduleNameController.text.trim().isEmpty) { _showMsg('scheduleName', 'Please provide a schedule name.'); return; }
    }
    
    if (_sendType == 'PDF') {
      final inputLimit = int.tryParse(_dailyLimitController.text.trim()) ?? 0;
      if (inputLimit < 1 || inputLimit > 50) {
        setState(() {
          _dailyLimitMsg = inputLimit < 1 ? 'Enter at least 1 email per day.' : 'Max limit is 50.';
          _isDailyLimitErr = true;
        });
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) setState(() { _dailyLimitMsg = null; _isDailyLimitErr = false; });
        });
        return;
      }
    }
    
    if (!_useSavedFormat) {
      if (_subjectController.text.trim().isEmpty) { _showMsg('subject', 'Subject cannot be empty.'); return; }
      if (_bodyController.text.trim().isEmpty) { _showMsg('body', 'Body cannot be empty.'); return; }
      if (!RegExp(r'<[a-zA-Z][^>]*>').hasMatch(_bodyController.text)) { _showMsg('body', 'Body must contain HTML tags (e.g. <p>, <b>, <br>).'); return; }
    } else {
      if (_selectedSubject == null) { _showMsg('subject', 'Please select a saved subject.'); return; }
      if (_selectedBody == null) { _showMsg('body', 'Please select a saved body.'); return; }
    }
    unawaited(StorageService.saveContacts(recipients, source: _sendType));

    final dailyLimit = _sendType == 'PDF' ? (int.tryParse(_dailyLimitController.text.trim()) ?? 40) : 0;
    final newEmail = ScheduledEmail(
      id: (widget.editEmail != null && !widget.isDraft)
          ? widget.editEmail!.id
          : DateTime.now().millisecondsSinceEpoch.toString(),
      senderEmail: sender,
      type: _sendType,
      recipients: recipients,
      subject: _useSavedFormat ? (_selectedSubject?.content ?? '') : _subjectController.text,
      body: _useSavedFormat ? (_selectedBody?.content ?? '') : _bodyController.text,
      scheduledDate: _dateController.text,
      scheduledTime: '${_timeController.text} ${_isAm ? "AM" : "PM"}',
      scheduleName: _scheduleNameController.text.trim(),
      pdfName: _sendType == 'PDF' ? _pdfPath : null,
      dailyLimit: dailyLimit,
      sentCount: widget.editEmail?.sentCount ?? 0,
      lastSentDate: widget.editEmail?.lastSentDate,
      delayMinutes: _delayMinutes,
      // testing: weekend sending enabled until user asks to restore weekday-only
      forceWeekend: true,
      createdAt: widget.editEmail?.createdAt ?? '${DateTime.now().day.toString().padLeft(2, '0')}/${DateTime.now().month.toString().padLeft(2, '0')}/${DateTime.now().year}',
    );

    // â”€â”€ PDF Conflict check for future dates â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    if (_sendType == 'PDF' && widget.editEmail == null) {
      final conflict = await _checkPdfConflict(newEmail);
      if (conflict != null && mounted) {
        // Show resolution dialog â€” it will handle saving
        _showConflictDialog(newEmail, conflict);
        return;
      }
    }

    setState(() => _isSubmitting = true);
    try {
      if (widget.editEmail != null && !widget.isDraft) {
        await BackendService.deleteCampaign(widget.editEmail!.id);
      }
      await BackendService.createCampaign(newEmail);
      _savedOrSubmitted = true;
      if (widget.isDraft && widget.editEmail != null) {
        await StorageService.deleteDraft(widget.editEmail!.id);
        widget.onDraftChanged?.call();
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _showMsg('date', 'Backend error: $e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // Returns the conflicting PDF schedule in O(N) via interval overlap.
  Future<ScheduledEmail?> _checkPdfConflict(ScheduledEmail newPdf) async {
    final allEmails = await BackendService.fetchCampaigns();
    final startDate = DateHelpers.parseDmy(newPdf.scheduledDate);
    if (startDate == null) return null;
    final dailyLimit = newPdf.dailyLimit > 0 ? newPdf.dailyLimit : 40;
    final totalDays = (newPdf.recipients.length / dailyLimit).ceil();
    if (totalDays <= 1) return null;

    final newStart = DateTime(startDate.year, startDate.month, startDate.day + 1);
    final newEnd = DateTime(startDate.year, startDate.month, startDate.day + totalDays - 1);

    for (final e in allEmails) {
      if (e.senderEmail != newPdf.senderEmail) continue;
      if (e.status == 'Success' || e.status == 'Failed' || e.status == 'Paused') continue;
      if (e.type != 'PDF' && e.type != 'Merged') continue;
      if (e.id == newPdf.id) continue;

      final eStart = DateHelpers.parseDmy(e.scheduledDate);
      if (eStart == null) continue;
      final eDailyLimit = e.dailyLimit > 0 ? e.dailyLimit : 40;
      final eTotalDays = (e.recipients.length / eDailyLimit).ceil();
      final normStart = DateTime(eStart.year, eStart.month, eStart.day);
      final normEnd = DateTime(eStart.year, eStart.month, eStart.day + eTotalDays - 1);

      if (!newStart.isAfter(normEnd) && !newEnd.isBefore(normStart)) {
        return e;
      }
    }
    return null;
  }

  void _showConflictDialog(ScheduledEmail newPdf, ScheduledEmail conflictingPdf) {
    final conflictName = conflictingPdf.scheduleName?.isNotEmpty == true
        ? conflictingPdf.scheduleName!
        : conflictingPdf.subject.isNotEmpty ? conflictingPdf.subject : 'Existing PDF';
    final newName = newPdf.scheduleName?.isNotEmpty == true
        ? newPdf.scheduleName!
        : 'New PDF';

    // Proportional daily merge allocation
    final remainingA = conflictingPdf.recipients.length - conflictingPdf.sentCount;
    final remainingB = newPdf.recipients.length;
    final total = remainingA + remainingB;
    final dailyLimit = newPdf.dailyLimit > 0 ? newPdf.dailyLimit : 40;
    final allocA = total > 0 ? (dailyLimit * remainingA / total).floor() : dailyLimit ~/ 2;
    final allocB = dailyLimit - allocA;

    // Queue: new PDF starts after existing PDF finishes
    final eStart = DateHelpers.parseDmy(conflictingPdf.scheduledDate);
    final eDailyLimit = conflictingPdf.dailyLimit > 0 ? conflictingPdf.dailyLimit : 40;
    final eTotalDays = eStart != null ? ((conflictingPdf.recipients.length - conflictingPdf.sentCount) / eDailyLimit).ceil() : 0;
    final queueStartDate = eStart?.add(Duration(days: eTotalDays));
    final queueDateStr = queueStartDate != null
        ? '${queueStartDate.day.toString().padLeft(2,'0')}/${queueStartDate.month.toString().padLeft(2,'0')}/${queueStartDate.year}'
        : 'After completion';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: Colors.white,
        title: Row(
          children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(color: AppTheme.warningAmber.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.warning_amber_rounded, color: AppTheme.warningAmber, size: 22),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text('Schedule Conflict', style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.w700, fontSize: 18, color: AppTheme.textDark)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppTheme.errorRed.withOpacity(0.06), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.errorRed.withOpacity(0.2))),
              child: Text(
                '"$conflictName" already occupies future dates for ${newPdf.senderEmail}. How would you like to handle "$newName"?',
                style: const TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppTheme.textDark),
              ),
            ),
            const SizedBox(height: 16),
            // Option 1: Queue After
            _ConflictOption(
              icon: Icons.schedule_rounded,
              color: AppTheme.primaryBlue,
              title: 'Queue After',
              subtitle: '"$newName" will start on $queueDateStr\nafter "$conflictName" finishes.',
              onTap: () async {
                Navigator.pop(ctx);
                final queued = newPdf.copyWith(queuedAfter: conflictingPdf.id, scheduledDate: queueDateStr);
                await BackendService.createCampaign(queued);
                if (mounted) Navigator.pop(context);
              },
            ),
            const SizedBox(height: 10),
            // Option 2: Merge
            _ConflictOption(
              icon: Icons.merge_rounded,
              color: AppTheme.successGreen,
              title: 'Merge PDFs',
              subtitle: 'Send together: $allocA/day from "$conflictName"\n+ $allocB/day from "$newName" (proportional split)',
              onTap: () async {
                Navigator.pop(ctx);
                await _saveMergedSchedule(newPdf, conflictingPdf, allocA, allocB);
                if (mounted) Navigator.pop(context);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(fontFamily: 'Inter', color: AppTheme.textMid)),
          ),
        ],
      ),
    );
  }

  Future<void> _saveMergedSchedule(
    ScheduledEmail newPdf,
    ScheduledEmail existingPdf,
    int allocExisting,
    int allocNew,
  ) async {
    final existingName = existingPdf.scheduleName?.isNotEmpty == true
        ? existingPdf.scheduleName!
        : existingPdf.subject.isNotEmpty ? existingPdf.subject : 'PDF-A';
    final newName = newPdf.scheduleName?.isNotEmpty == true
        ? newPdf.scheduleName!
        : 'PDF-B';

    final dailyLimit = (newPdf.dailyLimit > 0 ? newPdf.dailyLimit : 40);

    // Interleave recipients: existing remaining first, then new
    final existingRemaining = existingPdf.recipients.skip(existingPdf.sentCount).toList();
    final allRecipients = [...existingRemaining, ...newPdf.recipients];

    final mergedId = 'merged_${DateTime.now().millisecondsSinceEpoch}';
    final merged = ScheduledEmail(
      id: mergedId,
      senderEmail: newPdf.senderEmail,
      type: 'PDF',
      recipients: allRecipients,
      subject: newPdf.subject,
      body: newPdf.body,
      scheduledDate: existingPdf.scheduledDate, // start from existing PDF's date
      scheduledTime: existingPdf.scheduledTime,
      scheduleName: 'Merge: $existingName + $newName',
      pdfName: existingPdf.pdfName ?? existingPdf.scheduleName ?? 'Merged PDF',
      dailyLimit: dailyLimit,
      sentCount: 0,
      lastSentDate: existingPdf.lastSentDate,
      delayMinutes: newPdf.delayMinutes,
      // testing: weekend sending enabled until user asks to restore weekday-only
      forceWeekend: true,
      isMerged: true,
      mergedSourceIds: [existingPdf.id, newPdf.id],
      mergeContributions: {existingPdf.id: allocExisting, newPdf.id: allocNew},
      mergeSourceNames: {existingPdf.id: existingName, newPdf.id: newName},
    );

    await BackendService.deleteCampaign(existingPdf.id);
    await BackendService.createCampaign(merged);
  }

  Future<void> _autoSaveDraftIfNeeded() async {
    if (widget.editEmail != null && !widget.isDraft) return;
    final sender = _senderController.text.trim();
    final name = _scheduleNameController.text.trim();
    final subject = _useSavedFormat
        ? (_selectedSubject?.content ?? '')
        : _subjectController.text;
    final body = _useSavedFormat
        ? (_selectedBody?.content ?? '')
        : _bodyController.text;
    final recipients = _sendType == 'PDF'
        ? _pdfEmails.toSet().toList()
        : _emailControllers
            .map((c) => c.text.trim())
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList();

    final hasAnyContent = name.isNotEmpty ||
        sender.isNotEmpty ||
        recipients.isNotEmpty ||
        subject.trim().isNotEmpty ||
        body.trim().isNotEmpty ||
        _dateController.text.trim().isNotEmpty ||
        _timeController.text.trim().isNotEmpty;
    if (!hasAnyContent) return;

    final draft = ScheduledEmail(
      id: _draftId,
      senderEmail: sender,
      type: _sendType,
      recipients: recipients,
      subject: subject,
      body: body,
      scheduledDate: _dateController.text.trim(),
      scheduledTime: _timeController.text.trim().isNotEmpty
          ? '${_timeController.text.trim()} ${_isAm ? "AM" : "PM"}'
          : '',
      status: 'Draft',
      scheduleName: name,
      pdfName: _sendType == 'PDF' ? _pdfPath : null,
      dailyLimit: int.tryParse(_dailyLimitController.text.trim()) ?? 40,
      delayMinutes: _delayMinutes,
      forceWeekend: true,
    );
    await StorageService.saveDraft(draft);
    widget.onDraftChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && !_savedOrSubmitted) {
          unawaited(_autoSaveDraftIfNeeded());
        }
      },
      child: GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.opaque,
      child: Container(
      decoration: BoxDecoration(
        color: AppTheme.cardBg(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: AppTheme.border(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Scrollable content
          Flexible(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  Row(
                    children: [
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: widget.editEmail != null
                              ? Text(
                                  'Edit Schedule',
                                  style: TextStyle(
                                    fontFamily: 'Outfit',
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.textPrimary(context),
                                  ),
                                )
                              : (() {
                                  final d = DateHelpers.todayDmy();
                                  final wd = DateHelpers.weekdayName(d);
                                  return Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'New Schedule',
                                        style: TextStyle(
                                          fontFamily: 'Outfit',
                                          fontSize: 20,
                                          fontWeight: FontWeight.w700,
                                          color: AppTheme.textPrimary(context),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: AppTheme.primaryBlue.withValues(alpha: 0.10),
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(color: AppTheme.primaryBlue.withValues(alpha: 0.24)),
                                        ),
                                        child: Text(
                                          '$d ($wd)',
                                          style: TextStyle(
                                            fontFamily: 'Inter',
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: AppTheme.isDark(context) ? AppTheme.lightBlue : AppTheme.primaryBlue,
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                })(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          width: 32, height: 32,
                          decoration: BoxDecoration(color: AppTheme.surfaceBg(context), borderRadius: BorderRadius.circular(8)),
                          child: Icon(Icons.close, size: 18, color: AppTheme.textSecondary(context)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // ── Section 1: Name ──────────────────────────────────
                  _SectionHeader(title: '1  Schedule Name', icon: Icons.label_outline),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _scheduleNameController,
                    enabled: !_isDraftNameLocked,
                    decoration: InputDecoration(
                      hintText: 'My Weekly Update Blast',
                      prefixIcon: const Icon(Icons.label_outline, size: 18),
                      suffixIcon: _isDraftNameLocked
                          ? const Icon(Icons.lock_rounded, size: 18, color: AppTheme.textLight)
                          : (_scheduleNameController.text.trim().isNotEmpty
                              ? Icon(
                                  _isScheduleNameDuplicate ? Icons.error_outline_rounded : Icons.check_circle_rounded,
                                  size: 18,
                                  color: _isScheduleNameDuplicate ? AppTheme.errorRed : AppTheme.successGreen,
                                )
                              : null),
                    ),
                  ).animate().fade().slideY(),
                  if (_isDraftNameLocked)
                    Padding(
                      padding: const EdgeInsets.only(top: 6, left: 4),
                      child: Row(
                        children: [
                          const Icon(Icons.lock_rounded, size: 13, color: AppTheme.textLight),
                          const SizedBox(width: 5),
                          Text(
                            'Schedule name cannot be changed while editing a draft',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 12,
                              color: AppTheme.textSecondary(context),
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (_scheduleNameController.text.trim().isNotEmpty && _scheduleNameMsg == null) ...[
                    Builder(builder: (context) {
                      final norm = _scheduleNameController.text.trim().toLowerCase();
                      final matchingDraft = _isScheduleNameDuplicate
                          ? widget.existingDrafts.where((d) =>
                              d.id != widget.editEmail?.id &&
                              (d.scheduleName?.trim().toLowerCase() ?? '') == norm).firstOrNull
                          : null;
                      return Padding(
                        padding: const EdgeInsets.only(top: 6, left: 4),
                        child: Row(
                          children: [
                            Icon(
                              _isScheduleNameDuplicate ? Icons.cancel_rounded : Icons.check_circle_rounded,
                              size: 14,
                              color: _isScheduleNameDuplicate ? AppTheme.errorRed : AppTheme.successGreen,
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                matchingDraft != null
                                    ? 'A draft named "${matchingDraft.scheduleName}" already exists'
                                    : (_isScheduleNameDuplicate
                                        ? 'Name already exists — please choose a unique name'
                                        : 'Unique schedule name available'),
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: _isScheduleNameDuplicate ? AppTheme.errorRed : AppTheme.successGreen,
                                ),
                              ),
                            ),
                            if (matchingDraft != null && widget.onOpenDraft != null)
                              TextButton.icon(
                                onPressed: () {
                                  _savedOrSubmitted = true;
                                  Navigator.pop(context);
                                  WidgetsBinding.instance.addPostFrameCallback((_) {
                                    widget.onOpenDraft?.call(matchingDraft);
                                  });
                                },
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  backgroundColor: AppTheme.primaryBlue.withValues(alpha: 0.12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                icon: const Icon(Icons.open_in_new_rounded, size: 13, color: AppTheme.primaryBlue),
                                label: const Text(
                                  'Open Draft',
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.primaryBlue,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    }),
                  ],
                  _buildFieldMsg(_scheduleNameMsg, _isScheduleNameErr),
                  const SizedBox(height: 24),

                  // â”€â”€ Section 2: Sender â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                  _SectionHeader(title: '2  Sender Account', icon: Icons.account_circle_rounded),
                  const SizedBox(height: 10),
                  Autocomplete<String>(
                    optionsBuilder: (v) => v.text.isEmpty
                        ? const Iterable<String>.empty()
                        : _suggestedSenders.where((s) => s.toLowerCase().contains(v.text.toLowerCase())),
                    onSelected: (s) => setState(() => _senderController.text = s),
                    optionsViewBuilder: (BuildContext ctx2, AutocompleteOnSelected<String> onSelected, Iterable<String> options) {
                      return Align(
                        alignment: Alignment.topLeft,
                        child: Material(
                          color: Colors.transparent,
                          child: Container(
                            width: min(MediaQuery.of(ctx2).size.width - 40, 560),
                            constraints: const BoxConstraints(maxHeight: 220),
                            margin: const EdgeInsets.only(top: 4),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(color: AppTheme.primaryBlue.withOpacity(0.15), blurRadius: 20, offset: const Offset(0, 8)),
                                BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 6, offset: const Offset(0, 2)),
                              ],
                              border: Border.all(color: AppTheme.primaryBlue.withOpacity(0.2)),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: ListView.separated(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                shrinkWrap: true,
                                itemCount: options.length,
                                separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFEEEEF5)),
                                itemBuilder: (BuildContext ctx3, int index) {
                                  final String option = options.elementAt(index);
                                  return InkWell(
                                    onTap: () => onSelected(option),
                                    borderRadius: BorderRadius.circular(12),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 32, height: 32,
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                colors: [AppTheme.primaryBlue, AppTheme.primaryBlue.withOpacity(0.7)],
                                                begin: Alignment.topLeft, end: Alignment.bottomRight,
                                              ),
                                              shape: BoxShape.circle,
                                            ),
                                            child: Center(
                                              child: Text(
                                                option.isNotEmpty ? option[0].toUpperCase() : '?',
                                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              option,
                                              style: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppTheme.textDark, fontWeight: FontWeight.w500),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          const Icon(Icons.north_west_rounded, size: 14, color: AppTheme.textLight),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ).animate().fade(duration: 200.ms).slideY(begin: -0.1, end: 0, duration: 200.ms, curve: Curves.easeOut),
                      );
                    },
                    fieldViewBuilder: (ctx, ctrl, focus, onSubmit) {
                      if (_senderController.text.isNotEmpty && ctrl.text.isEmpty) ctrl.text = _senderController.text;
                      return TextField(
                        controller: ctrl,
                        focusNode: focus,
                        readOnly: _isAuthenticated,
                        onChanged: (v) => _senderController.text = v,
                        decoration: InputDecoration(
                          hintText: 'your@gmail.com',
                          prefixIcon: const Icon(Icons.alternate_email, size: 18),
                          suffixIcon: _isAuthenticated
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.verified_rounded, color: AppTheme.successGreen),
                                    IconButton(
                                      tooltip: 'Switch sender',
                                      icon: const Icon(Icons.edit_outlined, size: 18),
                                      onPressed: () {
                                        setState(() {
                                          _isAuthenticated = false;
                                          _senderController.clear();
                                          ctrl.clear();
                                        });
                                        focus.requestFocus();
                                      },
                                    ),
                                  ],
                                )
                              : null,
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      child: _isAuthenticated
                          ? Container(
                              key: const ValueKey('authed'),
                              width: double.infinity,
                              height: 48,
                              decoration: BoxDecoration(
                                color: AppTheme.successGreen.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: AppTheme.successGreen.withValues(alpha: 0.35),
                                ),
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.verified_rounded, size: 18, color: AppTheme.successGreen),
                                  SizedBox(width: 8),
                                  Text(
                                    'Authenticated • Ready to send',
                                    style: TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.successGreen,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : SizedBox(
                              key: const ValueKey('unauthed'),
                              width: double.infinity,
                              height: 48,
                              child: OutlinedButton(
                                onPressed: _isAuthenticating ? null : () => _authenticateWithGoogle(_senderController.text),
                                child: _isAuthenticating
                                    ? const Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          SizedBox(
                                            width: 18, height: 18,
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                          ),
                                          SizedBox(width: 10),
                                          Text('Authenticating...'),
                                        ],
                                      )
                                    : const Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.security_rounded, size: 18),
                                          SizedBox(width: 8),
                                          Text('Authenticate with Google'),
                                        ],
                                      ),
                              ),
                            ),
                    ),
                  ),
                  _buildFieldMsg(_senderMsg, _isSenderErr),
                  if (_isAuthenticated && _isValidEmail(_senderController.text) && _dateController.text.length == 10) ...[
                    const SizedBox(height: 10),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: _dateQuotaFull
                            ? AppTheme.errorRed.withOpacity(0.08)
                            : (_currentSenderUsage >= 30
                                ? AppTheme.warningAmber.withOpacity(0.08)
                                : AppTheme.successGreen.withOpacity(0.08)),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _dateQuotaFull
                              ? AppTheme.errorRed.withOpacity(0.4)
                              : (_currentSenderUsage >= 30
                                  ? AppTheme.warningAmber.withOpacity(0.4)
                                  : AppTheme.successGreen.withOpacity(0.4)),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                _dateQuotaFull
                                    ? Icons.block_rounded
                                    : (_currentSenderUsage >= 30
                                        ? Icons.warning_amber_rounded
                                        : Icons.check_circle_outline_rounded),
                                size: 15,
                                color: _dateQuotaFull
                                    ? AppTheme.errorRed
                                    : (_currentSenderUsage >= 30
                                        ? AppTheme.warningAmber
                                        : AppTheme.successGreen),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  _dateQuotaFull
                                      ? 'Daily Quota FULL'
                                      : 'Sent Today: $_currentSenderUsage / 50',
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: _dateQuotaFull
                                        ? AppTheme.errorRed
                                        : (_currentSenderUsage >= 30
                                            ? AppTheme.warningAmber
                                            : AppTheme.successGreen),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (_dateQuotaFull) ...[
                            const SizedBox(height: 6),
                            const Text(
                              'This sender has already sent 50 emails today. Please use a different sender email.',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 11,
                                color: AppTheme.errorRed,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ] else if (_currentSenderUsage > 0) ...[
                            const SizedBox(height: 4),
                            Text(
                              '${50 - _currentSenderUsage} emails remaining for today.',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 11,
                                color: _currentSenderUsage >= 30
                                    ? AppTheme.warningAmber
                                    : AppTheme.successGreen,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ).animate().fade(duration: 250.ms),
                  ],
                  const SizedBox(height: 24),

                  // â”€â”€ Section 3: Recipients â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                  _SectionHeader(title: '3  Recipients', icon: Icons.group_rounded),
                  const SizedBox(height: 10),
                  // Type selector (locked during edit so Single/Multiple/PDF cannot be switched)
                  Row(
                    children: ['Single', 'Multiple', 'PDF'].map((type) {
                      final sel = _sendType == type;
                      final isEditLocked = widget.editEmail != null && !widget.isDraft;
                      return Expanded(
                        child: GestureDetector(
                          onTap: isEditLocked ? null : () => setState(() => _sendType = type),
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 200),
                            opacity: (isEditLocked && !sel) ? 0.42 : 1.0,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 250),
                              margin: const EdgeInsets.only(right: 8),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: sel ? AppTheme.primaryBlue : AppTheme.surfaceBg(context),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: sel ? AppTheme.primaryBlue : AppTheme.border(context),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    type,
                                    style: TextStyle(
                                      fontFamily: 'Inter', fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: sel ? Colors.white : AppTheme.textSecondary(context),
                                    ),
                                  ),
                                  if (isEditLocked && sel) ...[
                                    const SizedBox(width: 4),
                                    const Icon(Icons.lock_rounded, size: 12, color: Colors.white),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),

                  // Recipient inputs

                  if (_sendType == 'Single' || _sendType == 'Multiple')
                    ...List.generate(_emailControllers.length, (i) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: TextField(
                        controller: _emailControllers[i],
                        keyboardType: TextInputType.emailAddress,
                        onChanged: (val) {
                          // Auto-append a fresh row as soon as the user types in the last Multiple field.
                          if (_sendType == 'Multiple' &&
                              i == _emailControllers.length - 1 &&
                              val.trim().isNotEmpty) {
                            setState(() => _emailControllers.add(TextEditingController()));
                          }
                        },
                        decoration: InputDecoration(
                          hintText: 'Recipient ${i + 1} email',
                          prefixIcon: const Icon(Icons.email_outlined, size: 18),
                          suffixIcon: _sendType == 'Multiple' && _emailControllers.length > 1
                              ? IconButton(
                                  icon: const Icon(Icons.remove_circle_outline, color: AppTheme.errorRed, size: 18),
                                  onPressed: () {
                                    setState(() {
                                      final removed = _emailControllers.removeAt(i);
                                      removed.dispose();
                                    });
                                  },
                                )
                              : null,
                        ),
                      ).animate().fade().slideY(),
                    )),

                  if (_sendType == 'Multiple')
                    TextButton.icon(
                      onPressed: () => setState(() => _emailControllers.add(TextEditingController())),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Add Recipient'),
                    ),

                  if (_sendType == 'PDF') ...[
                    GestureDetector(
                      onTap: widget.editEmail != null ? null : _pickPdf,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceBg(context),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: _pdfPath != null ? AppTheme.primaryBlue : AppTheme.border(context),
                            width: _pdfPath != null ? 2 : 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              _pdfPath != null ? Icons.picture_as_pdf_rounded : Icons.upload_file_rounded,
                              size: 40,
                              color: _pdfPath != null ? AppTheme.primaryBlue : AppTheme.textSecondary(context),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _pdfPath ?? 'Tap to upload PDF',
                              style: TextStyle(
                                fontFamily: 'Inter', fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: _pdfPath != null ? AppTheme.textPrimary(context) : AppTheme.textSecondary(context),
                              ),
                            ),
                            if (_pdfEmails.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text('${_pdfEmails.length} emails ready', style: const TextStyle(color: AppTheme.successGreen, fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w600)),
                            ],
                          ],
                        ),
                      ).animate().fade().scale(),
                    ),
                    const SizedBox(height: 10),
                    // Add extra email(s) into PDF recipient list
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _addPdfEmailController,
                            keyboardType: TextInputType.emailAddress,
                            onSubmitted: (_) => _addMorePdfEmails(),
                            decoration: const InputDecoration(
                              hintText: 'Add email(s) to PDF list (comma separated)',
                              prefixIcon: Icon(Icons.person_add_alt_1_rounded, size: 18),
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: _addMorePdfEmails,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('Add'),
                        ),
                      ],
                    ),
                    // PDF Emails panel
                    if (_pdfEmails.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      GestureDetector(
                        onTap: () => setState(() => _showPdfEmails = !_showPdfEmails),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: AppTheme.successGreen.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppTheme.successGreen.withOpacity(0.32)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.list_alt_rounded, size: 18, color: AppTheme.successGreen),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  '${_pdfEmails.length} emails in PDF list — tap to ${_showPdfEmails ? 'hide' : 'review, add or edit'}',
                                  style: const TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.successGreen),
                                ),
                              ),
                              Icon(_showPdfEmails ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, color: AppTheme.successGreen),
                            ],
                          ),
                        ),
                      ),
                      if (_showPdfEmails) ...[
                        const SizedBox(height: 8),
                        Container(
                          height: 260,
                          decoration: BoxDecoration(
                            color: AppTheme.cardBg(context),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppTheme.border(context)),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
                          ),
                          child: ListView.separated(
                            padding: const EdgeInsets.all(8),
                            physics: const BouncingScrollPhysics(),
                            itemCount: _isPdfEmailEditing ? _pdfEmailControllers.length : _pdfEmails.length,
                            separatorBuilder: (_, __) => Divider(height: 1, color: AppTheme.border(context)),
                            itemBuilder: (ctx, idx) {
                              if (_isPdfEmailEditing) {
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                                  child: Row(
                                    children: [
                                      Text('${idx + 1}.', style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppTheme.textSecondary(context), fontWeight: FontWeight.w600)),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: TextField(
                                          controller: _pdfEmailControllers[idx],
                                          style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppTheme.textPrimary(context)),
                                          decoration: const InputDecoration(
                                            isDense: true,
                                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.remove_circle_outline, color: AppTheme.errorRed, size: 18),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        onPressed: () {
                                          final removed = _pdfEmailControllers.removeAt(idx);
                                          removed.dispose();
                                          setState(() => _pdfEmails.removeAt(idx));
                                        },
                                      ),
                                    ],
                                  ),
                                );
                              }
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 22, height: 22,
                                      decoration: BoxDecoration(
                                        color: AppTheme.primaryBlue.withOpacity(0.12),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Center(
                                        child: Text('${idx + 1}', style: const TextStyle(fontFamily: 'Inter', fontSize: 10, color: AppTheme.primaryBlue, fontWeight: FontWeight.w700)),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(child: Text(_pdfEmails[idx], style: TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppTheme.textPrimary(context)))),
                                    IconButton(
                                      tooltip: 'Remove',
                                      icon: const Icon(Icons.close_rounded, size: 16, color: AppTheme.errorRed),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      onPressed: () {
                                        if (idx < _pdfEmailControllers.length) {
                                          _pdfEmailControllers.removeAt(idx).dispose();
                                        }
                                        setState(() => _pdfEmails.removeAt(idx));
                                      },
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (_isPdfEmailEditing)
                              TextButton.icon(
                                onPressed: _syncPdfEdits,
                                icon: const Icon(Icons.check_rounded, size: 16),
                                label: const Text('Save Edits'),
                              )
                            else
                              TextButton.icon(
                                onPressed: () {
                                  for (var c in _pdfEmailControllers) c.dispose();
                                  _pdfEmailControllers.clear();
                                  for (final e in _pdfEmails) _pdfEmailControllers.add(TextEditingController(text: e));
                                  setState(() => _isPdfEmailEditing = true);
                                },
                                icon: const Icon(Icons.edit_rounded, size: 16),
                                label: const Text('Edit Emails'),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ],
                  _buildFieldMsg(_recipientMsg, _isRecipientErr),
                  if (_sendType == 'PDF') ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: _dailyLimitController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Emails per day',
                        hintText: '40',
                        prefixIcon: Icon(Icons.speed_rounded, size: 18),
                        helperText: 'Your limit is 50. Campaign will send this many emails each day.',
                      ),
                    ),
                    _buildFieldMsg(_dailyLimitMsg, _isDailyLimitErr),
                  ],
                  // â”€â”€ Delay Between Emails (Anti-Spam) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                  if (_sendType == 'Multiple' || _sendType == 'PDF') ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryBlue.withOpacity(0.04),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppTheme.primaryBlue.withOpacity(0.15)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.timer_outlined, size: 16, color: AppTheme.primaryBlue),
                              const SizedBox(width: 6),
                              const Text(
                                'Delay Between Emails',
                                style: TextStyle(fontFamily: 'Outfit', fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.primaryBlue),
                              ),
                              const Spacer(),
                              Text(
                                '$_delayMinutes min between each email',
                                style: const TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppTheme.successGreen),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Slower sending = less chance of being blocked as spam',
                            style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppTheme.textLight),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              ...[2, 4, 6, 8].map((min) {
                                final selected = !_isCustomDelay && _delayMinutes == min;
                                return Expanded(
                                  child: GestureDetector(
                                    onTap: () => setState(() {
                                      _isCustomDelay = false;
                                      _delayMinutes = min;
                                    }),
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 200),
                                      margin: const EdgeInsets.symmetric(horizontal: 2),
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      decoration: BoxDecoration(
                                        color: selected ? AppTheme.primaryBlue : AppTheme.surfaceBg(context),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: selected ? AppTheme.primaryBlue : AppTheme.border(context)),
                                      ),
                                      child: Center(
                                        child: Text(
                                          '${min}m',
                                          style: TextStyle(
                                            fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w700,
                                            color: selected ? Colors.white : AppTheme.textPrimary(context),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }),
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => setState(() {
                                    _isCustomDelay = true;
                                    if (_customDelayController.text.trim().isEmpty) {
                                      _customDelayController.text = '$_delayMinutes';
                                    }
                                  }),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    margin: const EdgeInsets.symmetric(horizontal: 2),
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    decoration: BoxDecoration(
                                      color: _isCustomDelay ? AppTheme.primaryBlue : AppTheme.surfaceBg(context),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: _isCustomDelay ? AppTheme.primaryBlue : AppTheme.border(context)),
                                    ),
                                    child: Center(
                                      child: Text(
                                        'Custom',
                                        style: TextStyle(
                                          fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w700,
                                          color: _isCustomDelay ? Colors.white : AppTheme.textPrimary(context),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (_isCustomDelay) ...[
                            const SizedBox(height: 10),
                            TextField(
                              controller: _customDelayController,
                              keyboardType: TextInputType.number,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                              onChanged: (val) {
                                final parsed = int.tryParse(val.trim());
                                if (parsed != null && parsed >= 1 && parsed <= 120) {
                                  setState(() => _delayMinutes = parsed);
                                }
                              },
                              decoration: InputDecoration(
                                hintText: 'Enter delay in minutes (1–120)',
                                isDense: true,
                                prefixIcon: const Icon(Icons.edit_calendar_outlined, size: 17),
                                suffixText: 'min',
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),

                  // â”€â”€ Section 4: Email content â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                  _SectionHeader(title: '4  Email Content', icon: Icons.edit_note_rounded),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            FocusManager.instance.primaryFocus?.unfocus();
                            Future.delayed(const Duration(milliseconds: 50), () {
                              if (mounted) setState(() { _useSavedFormat = false; });
                            });
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: !_useSavedFormat ? AppTheme.primaryBlue : AppTheme.bgSurface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: !_useSavedFormat ? AppTheme.primaryBlue : AppTheme.divider),
                            ),
                            child: Center(child: Text('Make New', style: TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w600, color: !_useSavedFormat ? Colors.white : AppTheme.textMid))),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            FocusManager.instance.primaryFocus?.unfocus();
                            Future.delayed(const Duration(milliseconds: 50), () {
                              if (mounted) setState(() { _useSavedFormat = true; });
                            });
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: _useSavedFormat ? AppTheme.primaryBlue : AppTheme.bgSurface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: _useSavedFormat ? AppTheme.primaryBlue : AppTheme.divider),
                            ),
                            child: Center(child: Text('Use Saved', style: TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w600, color: _useSavedFormat ? Colors.white : AppTheme.textMid))),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (!_useSavedFormat) ...[
                    TextField(
                      controller: _subjectController,
                      minLines: 4,
                      maxLines: 8,
                      decoration: const InputDecoration(
                        hintText: 'Subject line',
                        prefixIcon: Icon(Icons.subject_rounded, size: 18),
                      ),
                    ),
                    _buildFieldMsg(_subjectMsg, _isSubjectErr),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _bodyController,
                      minLines: 8,
                      maxLines: 15,
                      decoration: const InputDecoration(
                        hintText: 'Write your HTML email body here... (e.g. <b>Hello</b>)',
                        alignLabelWithHint: true,
                        contentPadding: EdgeInsets.all(16),
                      ),
                    ),
                    _buildFieldMsg(_bodyMsg, _isBodyErr),
                  ] else ...[
                    _AnimatedDropdownPicker(
                      icon: Icons.subject_rounded,
                      hint: 'Select Subject',
                      items: _savedSubjects,
                      selected: _selectedSubject,
                      onSelected: (v) => setState(() => _selectedSubject = v),
                    ),
                    _buildFieldMsg(_subjectMsg, _isSubjectErr),
                    const SizedBox(height: 10),
                    _AnimatedDropdownPicker(
                      icon: Icons.edit_note_rounded,
                      hint: 'Select Body',
                      items: _savedBodies,
                      selected: _selectedBody,
                      onSelected: (v) => setState(() => _selectedBody = v),
                    ),
                    _buildFieldMsg(_bodyMsg, _isBodyErr),
                  ],
                  const SizedBox(height: 24),

                  // â”€â”€ Section 5: Schedule time â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                  _SectionHeader(title: '5  Schedule Date & Time', icon: Icons.schedule_rounded),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _DateFieldWithQuickButtons(controller: _dateController),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _timeController,
                                keyboardType: TextInputType.number,
                                inputFormatters: [TimeInputFormatter()],
                                decoration: const InputDecoration(hintText: '12:00'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () => setState(() => _isAm = !_isAm),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 17),
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryBlue.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: AppTheme.primaryBlue.withOpacity(0.3)),
                                ),
                                child: Text(
                                  _isAm ? 'AM' : 'PM',
                                  style: const TextStyle(color: AppTheme.primaryBlue, fontFamily: 'Inter', fontWeight: FontWeight.w700),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  _buildFieldMsg(_dateMsg, _isDateErr),
                  const SizedBox(height: 28),

                  // Submit
                  if (_currentSenderUsage >= 50 && _dateController.text.trim() == DateHelpers.todayDmy())
                    GestureDetector(
                      onTap: () {
                        final tmr = DateTime.now().add(const Duration(days: 1));
                        setState(() {
                          _dateController.text =
                              '${tmr.day.toString().padLeft(2, '0')}/${tmr.month.toString().padLeft(2, '0')}/${tmr.year}';
                        });
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
                        decoration: BoxDecoration(
                          color: AppTheme.errorRed.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppTheme.errorRed.withValues(alpha: 0.35)),
                        ),
                        child: const Center(
                          child: Text(
                            'Daily 50/50 limit reached today. Tap to move to Tomorrow.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppTheme.errorRed, fontFamily: 'Inter', fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                      ),
                    )
                  else
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        onPressed: _isSubmitting ? null : _submit,
                        child: _isSubmitting
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                              )
                            : Text(
                                widget.editEmail != null ? 'Update Schedule' : 'Save & Schedule',
                                style: const TextStyle(fontFamily: 'Outfit', fontSize: 17, fontWeight: FontWeight.w700),
                              ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
      ), // closes GestureDetector child: Container
      ), // closes GestureDetector
    ); // closes PopScope
  }
}

class _DateFieldWithQuickButtons extends StatelessWidget {
  final TextEditingController controller;
  const _DateFieldWithQuickButtons({required this.controller});

  static String _formatDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.isDark(context) ? AppTheme.lightBlue : AppTheme.primaryBlue;
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, child) {
        final trimmed = value.text.trim();
        final weekdayStr = DateHelpers.weekdayName(trimmed);
        final todayStr = DateHelpers.todayDmy();
        final tomorrowStr = _formatDate(DateTime.now().add(const Duration(days: 1)));
        final todayDay = DateHelpers.weekdayName(todayStr);
        final tomorrowDay = DateHelpers.weekdayName(tomorrowStr);
        final isTodaySelected = trimmed == todayStr;
        final isTomorrowSelected = trimmed == tomorrowStr;

        void selectDate(String dmy) {
          FocusManager.instance.primaryFocus?.unfocus();
          controller.value = TextEditingValue(
            text: dmy,
            selection: TextSelection.collapsed(offset: dmy.length),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              inputFormatters: [DateInputFormatter()],
              decoration: const InputDecoration(
                hintText: 'DD/MM/YYYY',
                prefixIcon: Icon(Icons.calendar_today_rounded, size: 18),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: _quickDateChip(
                    context,
                    label: isTodaySelected
                        ? todayDay
                        : 'Today (${todayDay.length >= 3 ? todayDay.substring(0, 3) : todayDay})',
                    isSelected: isTodaySelected,
                    accent: accent,
                    onTap: () => selectDate(todayStr),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _quickDateChip(
                    context,
                    label: isTomorrowSelected
                        ? tomorrowDay
                        : 'Tomorrow (${tomorrowDay.length >= 3 ? tomorrowDay.substring(0, 3) : tomorrowDay})',
                    isSelected: isTomorrowSelected,
                    accent: accent,
                    onTap: () => selectDate(tomorrowStr),
                  ),
                ),
              ],
            ),
            if (weekdayStr.isNotEmpty && !isTodaySelected && !isTomorrowSelected) ...[
              const SizedBox(height: 4),
              Text(
                weekdayStr,
                style: TextStyle(
                  fontSize: 12,
                  color: accent,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Inter',
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _quickDateChip(
    BuildContext context, {
    required String label,
    required bool isSelected,
    required Color accent,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primaryBlue
              : AppTheme.primaryBlue.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? AppTheme.primaryBlue
                : AppTheme.primaryBlue.withValues(alpha: 0.25),
          ),
        ),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: Text(
                label,
                key: ValueKey(label),
                maxLines: 1,
                style: TextStyle(
                  fontSize: 11,
                  color: isSelected ? Colors.white : accent,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Inter',
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppTheme.primaryBlue),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontFamily: 'Outfit', fontSize: 14, fontWeight: FontWeight.w700,
            color: AppTheme.primaryBlue,
          ),
        ),
      ],
    );
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
//  RESEND MODAL
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _ResendModal extends StatefulWidget {
  final ScheduledEmail email;
  const _ResendModal({required this.email});

  @override
  State<_ResendModal> createState() => _ResendModalState();
}

class _ResendModalState extends State<_ResendModal> {
  final _dateController = TextEditingController();
  final _timeController = TextEditingController();
  bool _isAm = true;
  String? _dateMsg; bool _isDateErr = false;

  @override
  void initState() {
    super.initState();
    if (widget.email.scheduledTime.isNotEmpty) {
      final t = widget.email.scheduledTime;
      final parts = t.split(' ');
      if (parts.length == 2) {
        _timeController.text = parts[0];
        _isAm = parts[1] == 'AM';
      }
    }
  }

  @override
  void dispose() {
    _dateController.dispose();
    _timeController.dispose();
    super.dispose();
  }

  void _showMsg(String msg, {bool isError = true}) {
    if (!mounted) return;
    setState(() {
      _dateMsg = msg; _isDateErr = isError;
    });
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() { _dateMsg = null; });
    });
  }

  Widget _buildFieldMsg() {
    if (_dateMsg == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _isDateErr ? AppTheme.errorRed.withOpacity(0.1) : AppTheme.successGreen.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _isDateErr ? AppTheme.errorRed.withOpacity(0.3) : AppTheme.successGreen.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(_isDateErr ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
              color: _isDateErr ? AppTheme.errorRed : AppTheme.successGreen, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(_dateMsg!, style: TextStyle(color: _isDateErr ? AppTheme.errorRed : AppTheme.successGreen, fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 13))),
        ],
      ),
    ).animate().fade().slideY(begin: -0.2, end: 0);
  }

  Future<void> _submit() async {
    if (!DateHelpers.isFutureDmyTime(_dateController.text, _timeController.text, _isAm)) { _showMsg('Enter a valid future date and time.'); return; }
    
    final originalName = widget.email.scheduleName ?? 'Resend Schedule';
    final resendName = originalName.contains('(Resend)') ? originalName : '$originalName (Resend)';
    final newEmail = widget.email.copyWith(
      id: widget.email.id, // Overwrite existing schedule
      scheduleName: resendName,
      status: 'Scheduled',
      createdAt: '${DateTime.now().day.toString().padLeft(2, '0')}/${DateTime.now().month.toString().padLeft(2, '0')}/${DateTime.now().year}',
      scheduledDate: _dateController.text,
      scheduledTime: '${_timeController.text} ${_isAm ? "AM" : "PM"}',
      sentCount: 0,
      recipientStatuses: {}, // Clears the ticks for the new schedule
      lastSentDate: '',
      recipients: widget.email.recipients.toSet().toList(),
      // testing: weekend sending enabled until user asks to restore weekday-only
      forceWeekend: true,
      clearQueuedAfter: true,
    );
    
    try {
      await BackendService.deleteCampaign(widget.email.id);
      await BackendService.createCampaign(newEmail);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _showMsg('Backend error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
      backgroundColor: AppTheme.cardBg(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: AppTheme.border(context)),
      ),
      elevation: 10,
      child: GestureDetector(
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        behavior: HitTestBehavior.opaque,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Resend Email',
                            style: TextStyle(fontFamily: 'Outfit', fontSize: 20, fontWeight: FontWeight.w700, color: AppTheme.textPrimary(context)),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryBlue.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppTheme.primaryBlue.withValues(alpha: 0.25)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.label_outline_rounded, size: 14, color: AppTheme.primaryBlue),
                                const SizedBox(width: 5),
                                Flexible(
                                  child: Text(
                                    (widget.email.scheduleName != null && widget.email.scheduleName!.trim().isNotEmpty)
                                        ? widget.email.scheduleName!.trim()
                                        : (widget.email.subject.trim().isNotEmpty ? widget.email.subject.trim() : widget.email.senderEmail),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontFamily: 'Outfit', fontSize: 12.5, fontWeight: FontWeight.w700, color: AppTheme.primaryBlue),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 32, height: 32,
                        decoration: BoxDecoration(color: AppTheme.surfaceBg(context), borderRadius: BorderRadius.circular(8)),
                        child: Icon(Icons.close, size: 18, color: AppTheme.textSecondary(context)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text('Schedule Date & Time', style: TextStyle(fontFamily: 'Outfit', fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.primaryBlue)),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _DateFieldWithQuickButtons(controller: _dateController),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _timeController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [TimeInputFormatter()],
                        decoration: const InputDecoration(
                          hintText: 'HH:MM',
                          prefixIcon: Icon(Icons.access_time_rounded, size: 18),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          FocusManager.instance.primaryFocus?.unfocus();
                          setState(() => _isAm = true);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: _isAm ? AppTheme.primaryBlue : AppTheme.surfaceBg(context),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: _isAm ? AppTheme.primaryBlue : AppTheme.border(context)),
                          ),
                          child: Center(child: Text('AM', style: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600, color: _isAm ? Colors.white : AppTheme.textSecondary(context)))),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          FocusManager.instance.primaryFocus?.unfocus();
                          setState(() => _isAm = false);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: !_isAm ? AppTheme.primaryBlue : AppTheme.surfaceBg(context),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: !_isAm ? AppTheme.primaryBlue : AppTheme.border(context)),
                          ),
                          child: Center(child: Text('PM', style: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600, color: !_isAm ? Colors.white : AppTheme.textSecondary(context)))),
                        ),
                      ),
                    ),
                  ],
                ),
                _buildFieldMsg(),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryBlue,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Resend Schedule', style: TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ).animate().blur(begin: const Offset(6, 6), end: Offset.zero, duration: 240.ms);
  }
}

class _AnimatedDropdownPicker extends StatelessWidget {
  final IconData icon;
  final String hint;
  final List<TemplateItem> items;
  final TemplateItem? selected;
  final ValueChanged<TemplateItem?> onSelected;

  const _AnimatedDropdownPicker({
    required this.icon,
    required this.hint,
    required this.items,
    required this.selected,
    required this.onSelected,
  });

  void _showPicker(BuildContext context) {
    showBlurredDialog(
      context: context,
      builder: (ctx) {
        return Center(
          child: Container(
            width: min(MediaQuery.of(ctx).size.width * 0.88, 420),
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.62),
            margin: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: AppTheme.cardBg(ctx).withValues(alpha: AppTheme.isDark(ctx) ? 0.94 : 0.96),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppTheme.border(ctx)),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primaryBlue.withValues(alpha: 0.14),
                  blurRadius: 30,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          Icon(icon, color: AppTheme.primaryBlue, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Select ${hint.replaceAll('Select ', '')}',
                              style: TextStyle(
                                fontFamily: 'Outfit',
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textPrimary(ctx),
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(ctx),
                            icon: Icon(Icons.close_rounded, size: 20, color: AppTheme.textSecondary(ctx)),
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: AppTheme.border(ctx)),
                    if (items.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(28),
                        child: Text(
                          'No saved items yet.',
                          style: TextStyle(fontFamily: 'Inter', color: AppTheme.textSecondary(ctx)),
                        ),
                      )
                    else
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          itemCount: items.length,
                          separatorBuilder: (_, __) => Divider(height: 1, color: AppTheme.border(ctx)),
                          itemBuilder: (context, index) {
                            final item = items[index];
                            final isSelected = selected == item;
                            return ListTile(
                              onTap: () {
                                onSelected(item);
                                Navigator.pop(ctx);
                              },
                              leading: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppTheme.primaryBlue.withValues(alpha: 0.14)
                                      : AppTheme.surfaceBg(ctx),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  icon,
                                  color: isSelected ? AppTheme.primaryBlue : AppTheme.textSecondary(ctx),
                                  size: 20,
                                ),
                              ),
                              title: Text(
                                item.name,
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 15,
                                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                  color: isSelected ? AppTheme.primaryBlue : AppTheme.textPrimary(ctx),
                                ),
                              ),
                              trailing: isSelected
                                  ? const Icon(Icons.check_circle_rounded, color: AppTheme.primaryBlue)
                                  : null,
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ).animate().blur(begin: const Offset(6, 6), end: Offset.zero, duration: 240.ms);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasSelection = selected != null;
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        _showPicker(context);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppTheme.surfaceBg(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: hasSelection
                ? AppTheme.primaryBlue.withValues(alpha: 0.5)
                : AppTheme.border(context),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: hasSelection ? AppTheme.primaryBlue : AppTheme.textSecondary(context)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                selected?.name ?? hint,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  fontWeight: hasSelection ? FontWeight.w600 : FontWeight.w400,
                  color: hasSelection ? AppTheme.textPrimary(context) : AppTheme.textSecondary(context),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: AppTheme.textSecondary(context)),
          ],
        ),
      ),
    );
  }
}

// â”€â”€ Conflict Resolution Option Widget â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _ConflictOption extends StatefulWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _ConflictOption({required this.icon, required this.color, required this.title, required this.subtitle, required this.onTap});
  @override
  State<_ConflictOption> createState() => _ConflictOptionState();
}

class _ConflictOptionState extends State<_ConflictOption> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _hovered = true),
      onTapUp: (_) => setState(() => _hovered = false),
      onTapCancel: () => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _hovered ? widget.color.withOpacity(0.12) : widget.color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: widget.color.withOpacity(_hovered ? 0.5 : 0.25)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(color: widget.color.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
              child: Icon(widget.icon, color: widget.color, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.title, style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.w700, fontSize: 14, color: widget.color)),
                  const SizedBox(height: 3),
                  Text(widget.subtitle, style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppTheme.textMid, height: 1.4)),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, size: 14, color: widget.color.withOpacity(0.6)),
          ],
        ),
      ),
    );
  }
}
