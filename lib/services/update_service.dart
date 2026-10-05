import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class AppUpdateInfo {
  final String version;
  final int build;
  final String downloadUrl;
  final String? notes;
  final bool force;

  const AppUpdateInfo({
    required this.version,
    required this.build,
    required this.downloadUrl,
    this.notes,
    this.force = false,
  });

  factory AppUpdateInfo.fromJson(Map<String, dynamic> json) {
    return AppUpdateInfo(
      version: json['version']?.toString() ?? '0.0.0',
      build: int.tryParse(json['build']?.toString() ?? '') ?? 0,
      downloadUrl: json['download_url']?.toString() ?? '',
      notes: json['notes']?.toString(),
      force: json['force'] == true,
    );
  }
}

class UpdateService {
  static const String manifestUrl =
      'https://raw.githubusercontent.com/felipekingx-maker/Felipe-Route/main/update_manifest.json';

  static Future<AppUpdateInfo?> checkForUpdate() async {
    try {
      final response = await http
          .get(
            Uri.parse(manifestUrl),
            headers: const {'Cache-Control': 'no-cache'},
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body);
      if (json is! Map<String, dynamic>) return null;

      final remote = AppUpdateInfo.fromJson(json);
      if (remote.downloadUrl.isEmpty) return null;

      final local = await PackageInfo.fromPlatform();
      final localBuild = int.tryParse(local.buildNumber) ?? 0;

      return remote.build > localBuild ? remote : null;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> openUpdate(AppUpdateInfo info) async {
    final uri = Uri.tryParse(info.downloadUrl);
    if (uri == null) return false;

    return launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
  }
}
