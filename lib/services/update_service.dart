import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';

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
  });

  String? get platformDownloadUrl {
    if (kIsWeb) return null;
    if (Platform.isWindows) return windowsDownloadUrl;
    if (Platform.isAndroid) return apkDownloadUrl;
    return null;
  }

  int get platformAssetSize {
    if (kIsWeb) return 0;
    if (Platform.isWindows) return windowsSize;
    if (Platform.isAndroid) return apkSize;
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
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final release = ReleaseInfo.fromJson(data);

        final hasUpdate = _isNewerVersion(release.version, currentVersion);
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

  /// Compares semantic versions (e.g. '1.0.1' > '1.0.0')
  static bool _isNewerVersion(String latest, String current) {
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

  /// Downloads the platform installer (APK/EXE) with real-time progress and launches it
  static Future<void> downloadAndInstall({
    required String downloadUrl,
    required void Function(double progress, int receivedBytes, int totalBytes) onProgress,
  }) async {
    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(downloadUrl));
      request.headers['User-Agent'] = 'MailFlow-Updater';

      final response = await client.send(request);
      if (response.statusCode != 200) {
        throw Exception('Download failed with status ${response.statusCode}');
      }

      final isWindows = !kIsWeb && Platform.isWindows;
      final fileName = isWindows ? 'MailFlow-Windows-Setup.exe' : 'MailFlow-update.apk';
      final totalBytes = response.contentLength ?? 0;
      final tempDir = await getTemporaryDirectory();
      final saveFile = File('${tempDir.path}/$fileName');

      if (await saveFile.exists()) {
        await saveFile.delete();
      }

      final sink = saveFile.openWrite();
      int receivedBytes = 0;

      await for (final chunk in response.stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (totalBytes > 0) {
          final progress = receivedBytes / totalBytes;
          onProgress(progress, receivedBytes, totalBytes);
        } else {
          onProgress(0.0, receivedBytes, totalBytes);
        }
      }

      await sink.flush();
      await sink.close();

      // Launch installer
      final result = await OpenFilex.open(
        saveFile.path,
        type: isWindows ? null : 'application/vnd.android.package-archive',
      );

      if (result.type != ResultType.done) {
        throw Exception(result.message);
      }
    } finally {
      client.close();
    }
  }
}

