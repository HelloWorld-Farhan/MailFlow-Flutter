import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:permission_handler/permission_handler.dart';
import 'notification_service.dart';

enum UpdateDownloadStatus { idle, downloading, installing, error }

class UpdateDownloadSnapshot {
  final UpdateDownloadStatus status;
  final double progress;
  final int receivedBytes;
  final int totalBytes;
  final String? version;
  final String? errorMessage;
  final String? filePath;

  const UpdateDownloadSnapshot({
    required this.status,
    this.progress = 0.0,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.version,
    this.errorMessage,
    this.filePath,
  });

  const UpdateDownloadSnapshot.idle() : this(status: UpdateDownloadStatus.idle);
}

class ReleaseInfo {
  final String tagName;
  final String version;
  final String name;
  final String body;
  final String? publishedAt;
  final String? apkDownloadUrl;
  final int apkSize;
  final String? windowsDownloadUrl;
  final int windowsSize;
  final String? macosDownloadUrl;
  final int macosSize;

  ReleaseInfo({
    required this.tagName,
    required this.version,
    required this.name,
    required this.body,
    this.publishedAt,
    this.apkDownloadUrl,
    this.apkSize = 0,
    this.windowsDownloadUrl,
    this.windowsSize = 0,
    this.macosDownloadUrl,
    this.macosSize = 0,
  });

  String? get platformDownloadUrl {
    if (kIsWeb) return null;
    if (defaultTargetPlatform == TargetPlatform.windows) return windowsDownloadUrl;
    if (defaultTargetPlatform == TargetPlatform.android) return apkDownloadUrl;
    if (defaultTargetPlatform == TargetPlatform.macOS) return macosDownloadUrl;
    return null;
  }

  int get platformAssetSize {
    if (kIsWeb) return 0;
    if (defaultTargetPlatform == TargetPlatform.windows) return windowsSize;
    if (defaultTargetPlatform == TargetPlatform.android) return apkSize;
    if (defaultTargetPlatform == TargetPlatform.macOS) return macosSize;
    return 0;
  }

  factory ReleaseInfo.fromJson(Map<String, dynamic> json) {
    final tagName = (json['tag_name'] ?? '').toString();
    // Extract semver (e.g. '1.0.1') from any tag string format (v1.0.1, APK-MailFlow-V1.0.0, etc.)
    final match = RegExp(r'(\d+\.\d+\.\d+)').firstMatch(tagName);
    final version = match != null ? match.group(1)! : (tagName.startsWith('v') ? tagName.substring(1) : tagName);

    String? apkUrl;
    int apkSize = 0;
    String? windowsUrl;
    int windowsSize = 0;
    String? macosUrl;
    int macosSize = 0;
    final assets = json['assets'] as List<dynamic>?;
    if (assets != null) {
      for (final asset in assets) {
        final name = (asset['name'] ?? '').toString().toLowerCase();
        if (name.endsWith('.apk') && apkUrl == null) {
          apkUrl = asset['browser_download_url']?.toString();
          apkSize = (asset['size'] as num?)?.toInt() ?? 0;
        } else if (name.endsWith('.exe') && windowsUrl == null) {
          windowsUrl = asset['browser_download_url']?.toString();
          windowsSize = (asset['size'] as num?)?.toInt() ?? 0;
        } else if (name.endsWith('.dmg') && macosUrl == null) {
          macosUrl = asset['browser_download_url']?.toString();
          macosSize = (asset['size'] as num?)?.toInt() ?? 0;
        }
      }
    }

    return ReleaseInfo(
      tagName: tagName,
      version: version,
      name: json['name']?.toString() ?? tagName,
      body: json['body']?.toString() ?? 'No changelog provided.',
      publishedAt: json['published_at']?.toString(),
      apkDownloadUrl: apkUrl,
      apkSize: apkSize,
      windowsDownloadUrl: windowsUrl,
      windowsSize: windowsSize,
      macosDownloadUrl: macosUrl,
      macosSize: macosSize,
    );
  }
}

class UpdateCheckResult {
  final bool hasUpdate;
  final String currentVersion;
  final ReleaseInfo? latestRelease;
  final String? errorMessage;

  UpdateCheckResult({
    required this.hasUpdate,
    required this.currentVersion,
    this.latestRelease,
    this.errorMessage,
  });
}

class UpdateService {
  static const String _repoOwner = 'HelloWorld-Farhan';
  static const String _repoName = 'MailFlow-Flutter';
  static const String _latestReleaseUrl =
      'https://api.github.com/repos/$_repoOwner/$_repoName/releases/latest';

  /// Fetches current version and checks GitHub releases for a newer version
  static Future<UpdateCheckResult> checkForUpdates() async {
    String currentVersion = '1.0.0';
    try {
      final info = await PackageInfo.fromPlatform();
      currentVersion = info.version;
    } catch (_) {}

    try {
      final response = await http.get(
        Uri.parse(_latestReleaseUrl),
        headers: {
          'Accept': 'application/vnd.github.v3+json',
          'User-Agent': 'MailFlow-Updater',
          'Cache-Control': 'no-cache',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final release = ReleaseInfo.fromJson(data);

        final hasUpdate = isNewerVersion(release.version, currentVersion);
        return UpdateCheckResult(
          hasUpdate: hasUpdate,
          currentVersion: currentVersion,
          latestRelease: release,
        );
      } else if (response.statusCode == 404) {
        return UpdateCheckResult(
          hasUpdate: false,
          currentVersion: currentVersion,
          errorMessage: 'No published releases found on GitHub.',
        );
      } else {
        return UpdateCheckResult(
          hasUpdate: false,
          currentVersion: currentVersion,
          errorMessage: 'GitHub API error (${response.statusCode})',
        );
      }
    } catch (e) {
      return UpdateCheckResult(
        hasUpdate: false,
        currentVersion: currentVersion,
        errorMessage: 'Network error: $e',
      );
    }
  }

  /// Compares semantic versions (e.g. '1.0.1' > '1.0.0').
  static bool isNewerVersion(String latest, String current) {
    try {
      final cleanLatest = latest.split('+').first.trim();
      final cleanCurrent = current.split('+').first.trim();

      final lParts = cleanLatest.split('.').map((p) => int.tryParse(p) ?? 0).toList();
      final cParts = cleanCurrent.split('.').map((p) => int.tryParse(p) ?? 0).toList();

      for (int i = 0; i < 3; i++) {
        final l = i < lParts.length ? lParts[i] : 0;
        final c = i < cParts.length ? cParts[i] : 0;
        if (l > c) return true;
        if (l < c) return false;
      }
      return false;
    } catch (_) {
      return latest != current;
    }
  }

  /// Ensures Android "Install unknown apps" permission is granted before opening APK updates.
  /// In-place APK updates keep all SharedPreferences/user data intact unless uninstalled.
  static Future<bool> ensureInstallPermission() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    final status = await Permission.requestInstallPackages.status;
    if (status.isGranted) return true;
    final requested = await Permission.requestInstallPackages.request();
    return requested.isGranted;
  }

  /// App-wide download state so OTA downloads survive dialog dismissal & app minimization.
  static final ValueNotifier<UpdateDownloadSnapshot> downloadNotifier =
      ValueNotifier<UpdateDownloadSnapshot>(const UpdateDownloadSnapshot.idle());

  static Future<void> startUpdateDownload({
    required String downloadUrl,
    required String version,
  }) async {
    if (downloadNotifier.value.status == UpdateDownloadStatus.downloading) return;

    downloadNotifier.value = UpdateDownloadSnapshot(
      status: UpdateDownloadStatus.downloading,
      version: version,
    );
    await NotificationService.showUpdateDownloadProgress(
      version: version,
      progressPct: 0,
      subtitle: 'Starting download...',
      indeterminate: true,
    );

    final client = http.Client();
    DateTime lastNotifAt = DateTime.fromMillisecondsSinceEpoch(0);
    int lastNotifPct = -1;

    try {
      await ensureInstallPermission();

      final request = http.Request('GET', Uri.parse(downloadUrl));
      request.headers['User-Agent'] = 'MailFlow-Updater';
      final response = await client.send(request);
      if (response.statusCode != 200) {
        throw Exception('Download failed with status ${response.statusCode}');
      }

      final isWindows = !kIsWeb && Platform.isWindows;
      final isMacOs = !kIsWeb && Platform.isMacOS;
      final fileName = isWindows
          ? 'MailFlow-Windows-Setup.exe'
          : (isMacOs ? 'MailFlow-macOS.dmg' : 'MailFlow-update.apk');
      final totalBytes = response.contentLength ?? 0;
      final tempDir = await getTemporaryDirectory();
      final saveFile = File('${tempDir.path}/$fileName');
      if (await saveFile.exists()) await saveFile.delete();

      final sink = saveFile.openWrite();
      int receivedBytes = 0;

      await for (final chunk in response.stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        final progress = totalBytes > 0 ? (receivedBytes / totalBytes).clamp(0.0, 1.0) : 0.0;
        final pct = (progress * 100).round();

        downloadNotifier.value = UpdateDownloadSnapshot(
          status: UpdateDownloadStatus.downloading,
          progress: progress,
          receivedBytes: receivedBytes,
          totalBytes: totalBytes,
          version: version,
          filePath: saveFile.path,
        );

        final now = DateTime.now();
        if (pct != lastNotifPct &&
            (pct - lastNotifPct >= 2 || now.difference(lastNotifAt).inMilliseconds >= 400)) {
          lastNotifPct = pct;
          lastNotifAt = now;
          final recMb = (receivedBytes / (1024 * 1024)).toStringAsFixed(1);
          final totMb = totalBytes > 0 ? '${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB' : '...';
          NotificationService.showUpdateDownloadProgress(
            version: version,
            progressPct: pct,
            subtitle: '$recMb MB / $totMb',
            indeterminate: totalBytes <= 0,
          );
        }
      }

      await sink.flush();
      await sink.close();

      if (!isWindows && !isMacOs && Platform.isAndroid) {
        final size = await saveFile.length();
        final header = await saveFile.openRead(0, 2).first.catchError((_) => <int>[]);
        if (size < 100 * 1024 || header.length < 2 || header[0] != 0x50 || header[1] != 0x4B) {
          throw Exception('Downloaded file is not a valid APK package.');
        }
        final allowed = await ensureInstallPermission();
        if (!allowed) {
          throw Exception('Please allow "Install unknown apps" for MailFlow in Android Settings and tap Retry.');
        }
      }

      downloadNotifier.value = UpdateDownloadSnapshot(
        status: UpdateDownloadStatus.installing,
        progress: 1.0,
        receivedBytes: receivedBytes,
        totalBytes: totalBytes,
        version: version,
        filePath: saveFile.path,
      );
      await NotificationService.showUpdateDownloadComplete(version);

      final result = await OpenFilex.open(
        saveFile.path,
        type: (isWindows || isMacOs) ? null : 'application/vnd.android.package-archive',
      );
      if (result.type != ResultType.done) {
        throw Exception(result.message);
      }
    } catch (e) {
      final msg = e.toString().replaceAll('Exception: ', '');
      downloadNotifier.value = UpdateDownloadSnapshot(
        status: UpdateDownloadStatus.error,
        version: version,
        errorMessage: msg,
      );
      await NotificationService.showUpdateDownloadFailed(msg);
    } finally {
      client.close();
    }
  }

  /// Re-opens the already-downloaded installer if available.
  static Future<void> retryDownloadedInstaller() async {
    final path = downloadNotifier.value.filePath;
    if (path == null || !await File(path).exists()) return;
    final isWindows = !kIsWeb && Platform.isWindows;
    final isMacOs = !kIsWeb && Platform.isMacOS;
    await OpenFilex.open(
      path,
      type: (isWindows || isMacOs) ? null : 'application/vnd.android.package-archive',
    );
  }
}

