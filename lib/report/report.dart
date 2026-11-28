import 'dart:io';

import 'package:archive/archive_io.dart';

import '../adb/adb.dart';
import '../scooter/ids.dart';
import 'app_log.dart';

/// A new issue on [repo] with the versions filled in. Nothing that identifies
/// the rider, the phone or the scooter; the rider writes the rest.
String issueUrl(String repo, {required String companion, String? openDash, int? openDashBuild}) {
  final lines = [
    'S1 Dash Companion: $companion',
    if (openDash != null) 'S1 Dash: $openDash${openDashBuild == null ? '' : ' (build $openDashBuild)'}',
  ];
  return 'https://github.com/$repo/issues/new?body=${Uri.encodeComponent('${lines.join('\n')}\n\nWhat happened:\n')}';
}

enum LogKind {
  /// This app's own log: connections and every step it ran.
  companion,

  /// OpenDash's own log and its rotations. Masked before it's written.
  openDash,

  /// The CAN bus recordings in the same folder: changed frames, event bursts
  /// and raw captures. Large; needed for a wrong reading or a fault.
  canBus,
}

/// A log file in OpenDash's folder on the scooter.
class ScooterLog {
  const ScooterLog(this.name, this.bytes);
  final String name;
  final int bytes;

  LogKind? get kind => _openDashLog.hasMatch(name)
      ? LogKind.openDash
      : _canLog.hasMatch(name)
      ? LogKind.canBus
      : null;
}

final _openDashLog = RegExp(r'^opendash(\.\d+)?\.jsonl$');
final _canLog = RegExp(r'^(bus|burst|raw)-[\w.-]+\.jsonl$');

/// `ls -ln` of OpenDash's log folder, as the files this app knows how to send.
List<ScooterLog> parseScooterLogs(String ls) => [
  for (final line in ls.split('\n'))
    if (line.startsWith('-'))
      if (line.trim().split(RegExp(r'\s+')) case final f when f.length >= 8)
        if (ScooterLog(f.last, int.tryParse(f[4]) ?? 0) case final l when l.kind != null) l,
];

/// Lists OpenDash's logs on the scooter without pulling anything.
Future<List<ScooterLog>> listScooterLogs(Adb adb) async => parseScooterLogs((await adb.shell('ls -ln $kOpenDashLogDir')).output);

String formatBytes(int b) {
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).round()} KB';
  return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
}

class LogBundle {
  const LogBundle(this.zip, {this.pulled = 0, this.failed = 0});
  final File zip;

  /// Scooter files that made it in, and ones that couldn't be read.
  final int pulled;
  final int failed;
}

/// Zips the chosen [kinds] into [dir] (cleared first, so only the newest
/// bundle is kept): this app's log, and from [remote] (the scooter's listing)
/// the files of the chosen kinds, pulled over [adb]. A file that can't be
/// pulled is left out and counted in [LogBundle.failed].
Future<LogBundle> buildLogBundle(
  AppLog log,
  Directory dir, {
  Adb? adb,
  List<ScooterLog> remote = const [],
  Set<LogKind> kinds = const {LogKind.companion, LogKind.openDash},
  String? summary,
  void Function(int done, int total)? onProgress,
}) async {
  if (dir.existsSync()) await dir.delete(recursive: true);
  final work = await Directory('${dir.path}/work').create(recursive: true);

  if (kinds.contains(LogKind.companion)) await File('${work.path}/companion.log').writeAsString(log.read());
  if (summary != null) await File('${work.path}/summary.txt').writeAsString('$summary\n');

  final wanted = adb == null
      ? const <ScooterLog>[]
      : [
          for (final l in remote)
            if (kinds.contains(l.kind)) l,
        ];
  var pulled = 0, failed = 0;
  onProgress?.call(0, wanted.length);
  for (final (i, l) in wanted.indexed) {
    final sub = Directory('${work.path}/${l.kind == LogKind.canBus ? 'can' : 'opendash'}');
    await sub.create();
    try {
      await adb!.pull('$kOpenDashLogDir/${l.name}', '${sub.path}/${l.name}');
      pulled++;
    } on AdbFailure {
      failed++;
    }
    onProgress?.call(i + 1, wanted.length);
  }
  for (final d in work.listSync().whereType<Directory>()) {
    if (d.listSync().isEmpty) await d.delete();
  }

  final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
  final zip = File('${dir.path}/opendash-companion-logs-$stamp.zip');
  final enc = ZipFileEncoder()..create(zip.path);
  for (final f in work.listSync(recursive: true).whereType<File>()) {
    await enc.addFile(f, f.path.substring(work.path.length + 1));
  }
  await enc.close();
  await work.delete(recursive: true);
  return LogBundle(zip, pulled: pulled, failed: failed);
}
