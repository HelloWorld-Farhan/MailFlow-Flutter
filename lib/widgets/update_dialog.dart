import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/update_service.dart';
import '../theme/app_theme.dart';

class UpdateDialog extends StatefulWidget {
  final UpdateCheckResult? initialResult;
  const UpdateDialog({super.key, this.initialResult});

  static Future<void> show(BuildContext context, {UpdateCheckResult? initialResult}) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'UpdateDialog',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, anim1, anim2) {
        return UpdateDialog(initialResult: initialResult);
      },
      transitionBuilder: (context, anim1, anim2, child) {
        final curved = CurvedAnimation(parent: anim1, curve: Curves.easeOutBack);
        final blur = (anim1.value * 10.0).clamp(0.0, 10.0);
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: () => Navigator.of(context).maybePop(),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.28 * anim1.value),
                  ),
                ),
              ),
            ),
            ScaleTransition(
              scale: Tween<double>(begin: 0.90, end: 1.0).animate(curved),
              child: FadeTransition(opacity: anim1, child: child),
            ),
          ],
        );
      },
    );
  }

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

enum _UpdateState { checking, upToDate, available, downloading, installing, error }

class _UpdateDialogState extends State<UpdateDialog> {
  _UpdateState _state = _UpdateState.checking;
  UpdateCheckResult? _checkResult;
  double _downloadProgress = 0.0;
  int _receivedBytes = 0;
  int _totalBytes = 0;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final preset = widget.initialResult;
    if (preset != null && preset.latestRelease != null) {
      _checkResult = preset;
      _state = preset.hasUpdate ? _UpdateState.available : _UpdateState.upToDate;
    } else {
      _runCheck();
    }
  }

  Future<void> _runCheck() async {
    setState(() {
      _state = _UpdateState.checking;
      _errorMessage = null;
    });

    final result = await UpdateService.checkForUpdates();
    if (!mounted) return;

    setState(() {
      _checkResult = result;
      if (result.errorMessage != null && result.latestRelease == null) {
        _state = _UpdateState.error;
        _errorMessage = result.errorMessage;
      } else if (result.hasUpdate && result.latestRelease != null) {
        _state = _UpdateState.available;
      } else {
        _state = _UpdateState.upToDate;
      }
    });
  }

  Future<void> _startDownload() async {
    final downloadUrl = _checkResult?.latestRelease?.platformDownloadUrl;
    if (downloadUrl == null) {
      setState(() {
        _state = _UpdateState.error;
        _errorMessage = 'Download link is not available for this platform.';
      });
      return;
    }

    setState(() {
      _state = _UpdateState.downloading;
      _downloadProgress = 0.0;
    });

    try {
      await UpdateService.ensureInstallPermission();
      await UpdateService.downloadAndInstall(
        downloadUrl: downloadUrl,
        onProgress: (progress, received, total) {
          if (mounted) {
            setState(() {
              _downloadProgress = progress;
              _receivedBytes = received;
              _totalBytes = total;
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _state = _UpdateState.installing;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _state = _UpdateState.error;
          _errorMessage = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 MB';
    final mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
      child: Center(
        child: Container(
          width: MediaQuery.of(context).size.width * 0.88,
          constraints: const BoxConstraints(maxWidth: 368, maxHeight: 490),
          margin: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: AppTheme.cardBg(context).withValues(alpha: AppTheme.isDark(context) ? 0.92 : 0.86),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: (AppTheme.isDark(context) ? AppTheme.lightBlue : AppTheme.primaryBlue).withValues(alpha: 0.24),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primaryBlue.withValues(alpha: 0.14),
                blurRadius: 36,
                offset: const Offset(0, 12),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 20),
                  Flexible(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: _buildBody(),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildActions(),
                ],
              ),
            ),
          ),
        ),
      ).animate().blur(begin: const Offset(8, 8), end: Offset.zero, duration: 280.ms),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: AppTheme.primaryBlue.withOpacity(0.10),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.primaryBlue.withOpacity(0.20)),
          ),
          child: Image.asset('assets/Logo.png'),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Software Update',
                style: TextStyle(
                  fontFamily: 'Outfit',
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary(context),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Current: v${_checkResult?.currentVersion ?? "1.0.0"}',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textSecondary(context),
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: Icon(Icons.close_rounded, color: AppTheme.textSecondary(context)),
          splashRadius: 20,
        ),
      ],
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case _UpdateState.checking:
        return Column(
          children: [
            const SizedBox(height: 30),
            const SizedBox(
              width: 44,
              height: 44,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation(AppTheme.primaryBlue),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Checking GitHub for updates...',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                color: AppTheme.textMid,
              ),
            ),
            const SizedBox(height: 30),
          ],
        );

      case _UpdateState.upToDate:
        return Column(
          children: [
            const SizedBox(height: 16),
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded, color: Colors.green, size: 36),
            ).animate().scale(curve: Curves.easeOutBack, duration: 400.ms),
            const SizedBox(height: 16),
            const Text(
              'You’re Up to Date!',
              style: TextStyle(
                fontFamily: 'Outfit',
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppTheme.textDark,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'MailFlow v${_checkResult?.currentVersion ?? "1.0.0"} is currently the latest version available.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                color: AppTheme.textMid,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
          ],
        );

      case _UpdateState.available:
        final release = _checkResult!.latestRelease!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.primaryBlue.withOpacity(0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.primaryBlue.withOpacity(0.15)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.rocket_launch_rounded, color: AppTheme.primaryBlue, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'New Version Available: v${release.version}',
                          style: const TextStyle(
                            fontFamily: 'Outfit',
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textDark,
                          ),
                        ),
                        if (release.platformAssetSize > 0)
                          Text(
                            'Download size: ${_formatBytes(release.platformAssetSize)}',
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 12,
                              color: AppTheme.textMid,
                            ),
                          ),
                        if (release.platformDownloadUrl == null)
                          const Text(
                            'Download this release from GitHub Releases on this device.',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 12,
                              color: AppTheme.textMid,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'What’s Changed',
              style: TextStyle(
                fontFamily: 'Outfit',
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary(context),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.surfaceBg(context),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.border(context)),
              ),
              child: Text(
                release.body.trim().isEmpty ? 'Performance improvements and bug fixes.' : release.body,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  color: AppTheme.textPrimary(context),
                  height: 1.4,
                ),
              ),
            ),
          ],
        );

      case _UpdateState.downloading:
        final pct = (_downloadProgress * 100).toInt();
        return Column(
          children: [
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Downloading update...',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary(context),
                  ),
                ),
                Text(
                  '$pct%',
                  style: const TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primaryBlue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: _downloadProgress > 0 ? _downloadProgress : null,
                minHeight: 10,
                backgroundColor: AppTheme.border(context),
                valueColor: const AlwaysStoppedAnimation(AppTheme.primaryBlue),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '${_formatBytes(_receivedBytes)} / ${_formatBytes(_totalBytes)}',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 12,
                color: AppTheme.textSecondary(context),
              ),
            ),
            const SizedBox(height: 16),
          ],
        );

      case _UpdateState.installing:
        return Column(
          children: [
            const SizedBox(height: 20),
            const SizedBox(
              width: 44,
              height: 44,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation(AppTheme.primaryBlue),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Launching package installer...',
              style: TextStyle(
                fontFamily: 'Outfit',
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary(context),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Please follow on-screen prompt to complete update.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                color: AppTheme.textSecondary(context),
              ),
            ),
            const SizedBox(height: 20),
          ],
        );

      case _UpdateState.error:
        return Column(
          children: [
            const SizedBox(height: 16),
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.error_outline_rounded, color: Colors.red, size: 32),
            ),
            const SizedBox(height: 14),
            Text(
              'Update Check Failed',
              style: TextStyle(
                fontFamily: 'Outfit',
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary(context),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _errorMessage ?? 'An unexpected error occurred.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 12,
                color: AppTheme.textSecondary(context),
              ),
            ),
            const SizedBox(height: 16),
          ],
        );
    }
  }

  Widget _buildActions() {
    switch (_state) {
      case _UpdateState.checking:
        return const SizedBox.shrink();

      case _UpdateState.installing:
        return Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: BorderSide(color: AppTheme.border(context)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(
                  'Close',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary(context),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: _startDownload,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryBlue,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text(
                  'Retry Install',
                  style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        );

      case _UpdateState.upToDate:
        return Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _runCheck,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: BorderSide(color: AppTheme.border(context)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(
                  'Check Again',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary(context),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryBlue,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text(
                  'Done',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        );

      case _UpdateState.available:
        final hasInstaller = _checkResult?.latestRelease?.platformDownloadUrl != null;
        return Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: BorderSide(color: AppTheme.border(context)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(
                  hasInstaller ? 'Later' : 'Close',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary(context),
                  ),
                ),
              ),
            ),
            if (hasInstaller) ...[
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: _startDownload,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryBlue,
                    foregroundColor: Colors.white,
                    elevation: 2,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.download_rounded, size: 20),
                  label: const Text(
                    'Download & Install',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ],
        );

      case _UpdateState.downloading:
        return OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            side: BorderSide(color: AppTheme.border(context)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: Text(
            'Cancel',
            style: TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary(context),
            ),
          ),
        );

      case _UpdateState.error:
        return ElevatedButton.icon(
          onPressed: _runCheck,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryBlue,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text(
            'Retry',
            style: TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w600,
            ),
          ),
        );
    }
  }
}
