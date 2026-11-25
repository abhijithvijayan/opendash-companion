import 'dart:convert';

import 'ids.dart';

({String? versionName, int? versionCode}) parseDumpsysVersion(String out) {
  final code = RegExp(r'versionCode=(\d+)').firstMatch(out);
  final name = RegExp(r'versionName=(\S+)').firstMatch(out);
  return (versionName: name?.group(1), versionCode: code == null ? null : int.parse(code.group(1)!));
}

String? parseHomeActivity(String out) {
  final lines = out.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty && l.contains('/') && !l.contains(' '));
  return lines.isEmpty ? null : lines.last;
}

({int? physical, int? override}) parseDensity(String out) {
  int? read(String label) {
    final m = RegExp('$label density: (\\d+)').firstMatch(out);
    return m == null ? null : int.parse(m.group(1)!);
  }

  return (physical: read('Physical'), override: read('Override'));
}

List<String> parseThirdPartyPackages(String out) => [
      for (final line in out.split('\n'))
        if (line.trim().startsWith('package:'))
          if (line.trim().substring(8) case final pkg when pkg.isNotEmpty && !isStockPackage(pkg) && pkg != kCompanionPackage) pkg,
    ];

/// OpenDash's answer: send updates by itself ([auto]), the build it runs and
/// the build its rider skipped.
class OpenDashAccepts {
  const OpenDashAccepts({required this.auto, required this.installed, required this.skipped});
  final bool auto;
  final int installed;
  final int skipped;
}

Map<String, Object?>? _json(String out) {
  try {
    final m = jsonDecode(out.trim());
    return m is Map ? m.cast<String, Object?>() : null;
  } on FormatException {
    return null;
  }
}

OpenDashAccepts? parseAccepts(String out) {
  final m = _json(out);
  final auto = m?['auto'];
  final installed = m?['installed'];
  final skipped = m?['skipped'];
  if (auto is! bool || installed is! int || skipped is! int) return null;
  return OpenDashAccepts(auto: auto, installed: installed, skipped: skipped);
}

int? parseStagedBuild(String out) => switch (_json(out)?['build']) { final int b => b, _ => null };
