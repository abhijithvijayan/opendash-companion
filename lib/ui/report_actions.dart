import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../adb/adb.dart';
import '../report/report.dart';
import '../state/providers.dart';
import 'about_screen.dart' show versionLabel;
import 'actions.dart' show hostApiProvider;
import 'widgets.dart';

/// Opens a page in the browser. A provider, so tests can see what was opened.
final urlOpenerProvider = Provider<Future<bool> Function(Uri)>(
  (ref) =>
      (u) => launchUrl(u, mode: LaunchMode.externalApplication).catchError((_) => false),
);

/// Opens [url] in the browser, or says it couldn't.
Future<void> openUrl(BuildContext context, WidgetRef ref, String url) async {
  final ok = await ref.read(urlOpenerProvider)(Uri.parse(url));
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't open $url")));
  }
}

/// Opens a new GitHub issue with the versions filled in, on OpenDash's
/// repository or this app's, as the rider picks.
Future<void> reportProblem(BuildContext context, WidgetRef ref) async {
  final status = ref.read(connectionProvider).status;
  final repo = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            key: const ValueKey('report-opendash'),
            leading: const Icon(Icons.speed_rounded),
            title: const Text('Something wrong with OpenDash'),
            subtitle: const Text('On the dashboard itself'),
            onTap: () => Navigator.pop(c, kOpenDashRepo),
          ),
          ListTile(
            key: const ValueKey('report-companion'),
            leading: const Icon(Icons.phone_android_rounded),
            title: const Text('Something wrong with this app'),
            subtitle: const Text('Connecting, installing, updating'),
            onTap: () => Navigator.pop(c, kCompanionRepo),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (repo == null || !context.mounted) return;
  await openUrl(
    context,
    ref,
    issueUrl(repo, companion: versionLabel(), openDash: status?.openDashVersion, openDashBuild: status?.openDashBuild),
  );
}

/// A modal "working" dialog whose text can change, closed exactly once.
class _Busy {
  _Busy(BuildContext context, String text) : _nav = Navigator.of(context, rootNavigator: true), label = ValueNotifier(text) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
              const SizedBox(width: 20),
              Expanded(
                child: ValueListenableBuilder(valueListenable: label, builder: (_, t, _) => Text(t)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  final NavigatorState _nav;
  final ValueNotifier<String> label;
  bool _open = true;

  void close() {
    if (_open) _nav.pop();
    _open = false;
  }
}

/// Lets the rider pick which logs to share, with their sizes. Null if they
/// back out.
Future<Set<LogKind>?> chooseLogs(BuildContext context, {required int appLogBytes, required List<ScooterLog> remote}) {
  int size(LogKind k) => k == LogKind.companion ? appLogBytes : remote.where((l) => l.kind == k).fold(0, (a, l) => a + l.bytes);
  int count(LogKind k) => remote.where((l) => l.kind == k).length;
  final chosen = {LogKind.companion, if (count(LogKind.openDash) > 0) LogKind.openDash};

  return showModalBottomSheet<Set<LogKind>>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) {
        final t = Theme.of(c);
        final muted = t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant);
        Widget option(LogKind k, String title, String what) {
          final n = k == LogKind.companion ? 1 : count(k);
          return CheckboxListTile(
            key: ValueKey('log-${k.name}'),
            value: chosen.contains(k),
            onChanged: n == 0 ? null : (v) => setState(() => v! ? chosen.add(k) : chosen.remove(k)),
            title: Text(title),
            subtitle: Text(n == 0 ? 'None on the scooter' : '$what · ${formatBytes(size(k))}'),
          );
        }

        final total = chosen.fold(0, (a, k) => a + size(k));
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text('Which logs?', style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                ),
                option(LogKind.companion, "This app's log", 'Connections and every install step'),
                option(LogKind.openDash, "OpenDash's log", 'What happened on the dashboard'),
                option(
                  LogKind.canBus,
                  'CAN bus recordings',
                  '${count(LogKind.canBus)} file${count(LogKind.canBus) == 1 ? '' : 's'}, for a wrong reading or a fault',
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Text(
                    'OpenDash masks the VIN, serial numbers, phone and network names before writing its logs. '
                    'Read them before you post them publicly. The zip is smaller than the sizes shown.',
                    style: muted,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: FilledButton.icon(
                    key: const ValueKey('log-share'),
                    onPressed: chosen.isEmpty ? null : () => Navigator.pop(c, {...chosen}),
                    icon: const Icon(Icons.ios_share_rounded),
                    label: Text(chosen.isEmpty ? 'Pick at least one' : 'Share ${formatBytes(total)}'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

/// Asks which logs to share (when the scooter has OpenDash's), zips them and
/// opens the share sheet so the rider can attach the zip to an issue.
Future<void> shareLogs(BuildContext context, WidgetRef ref) async {
  final conn = ref.read(connectionProvider);
  final fromScooter = conn.connected && conn.status?.openDashInstalled == true;
  final messenger = ScaffoldMessenger.of(context);
  final appLog = ref.read(appLogProvider);
  final adb = ref.read(adbProvider);

  var remote = const <ScooterLog>[];
  var kinds = {LogKind.companion};
  if (fromScooter) {
    final busy = _Busy(context, "Reading the scooter's logs…");
    try {
      remote = await listScooterLogs(adb);
    } on AdbFailure catch (e) {
      messenger.showSnackBar(SnackBar(content: Text("Couldn't list OpenDash's logs (${e.message}); sharing this app's log only.")));
    } finally {
      busy.close();
    }
    if (remote.isNotEmpty) {
      if (!context.mounted) return;
      final picked = await chooseLogs(context, appLogBytes: appLog.read().length, remote: remote);
      if (picked == null) return;
      kinds = picked;
    }
  }
  if (!context.mounted) return;

  final busy = _Busy(context, 'Collecting logs…');
  final LogBundle bundle;
  try {
    final status = conn.status;
    bundle = await buildLogBundle(
      appLog,
      ref.read(reportsDirProvider),
      adb: remote.isEmpty ? null : adb,
      remote: remote,
      kinds: kinds,
      summary: ['OpenDash Companion: ${versionLabel()}', if (status != null) describeStatus(status)].join('\n'),
      onProgress: (done, total) {
        if (total > 0) busy.label.value = 'Collecting logs… $done of $total';
      },
    );
  } catch (e) {
    busy.close();
    messenger.showSnackBar(SnackBar(content: Text("Couldn't collect the logs: $e")));
    return;
  }
  busy.close();
  if (bundle.failed > 0) {
    messenger.showSnackBar(
      SnackBar(content: Text("${bundle.failed} file${bundle.failed == 1 ? '' : 's'} couldn't be read from the scooter and were left out.")),
    );
  }
  try {
    await ref.read(hostApiProvider).shareFile(bundle.zip.path, 'application/zip', 'OpenDash logs');
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text("Couldn't open the share sheet: $e")));
  }
}

/// "Report a problem" and "Share logs", with what the logs hold.
class ProblemSection extends ConsumerWidget {
  const ProblemSection({super.key, this.enabled = true});

  /// False while an operation is using the connection.
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Something wrong?'),
        Text(
          "Share logs lets you pick this app's log, OpenDash's log and the CAN bus recordings, and puts them in one zip "
          'to attach to a report.',
          style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const ValueKey('share-logs'),
                onPressed: enabled ? () => shareLogs(context, ref) : null,
                icon: const Icon(Icons.ios_share_rounded),
                label: const Text('Share logs'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                key: const ValueKey('report-problem'),
                onPressed: () => reportProblem(context, ref),
                icon: const Icon(Icons.bug_report_outlined),
                label: const Text('Report a problem'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
