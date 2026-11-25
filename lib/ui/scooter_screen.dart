import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' hide StepState;

import '../releases/release.dart';
import '../scooter/operations.dart';
import '../state/providers.dart';
import 'actions.dart';
import 'release_notes_sheet.dart';
import 'report_actions.dart';
import 'update_notices.dart';
import 'widgets.dart';

class MakeHomeNotifier extends Notifier<bool> {
  @override
  bool build() => ref.read(prefsProvider).makeHome;

  Future<void> set(bool v) async {
    state = v;
    await ref.read(prefsProvider).setMakeHome(v);
  }
}

final makeHomeProvider = NotifierProvider<MakeHomeNotifier, bool>(MakeHomeNotifier.new);

class ScooterScreen extends ConsumerWidget {
  const ScooterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conn = ref.watch(connectionProvider);
    final status = conn.status;
    final t = Theme.of(context);
    final cs = t.colorScheme;

    // Only the rider leaving disconnects. The Connect screen also pops this
    // route when it reconnects, and that pop must not close the new link.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        ref.read(connectionProvider.notifier).disconnect();
        Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Your scooter'),
            Text(conn.host ?? '', style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ]),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: conn.busy
                  ? null
                  : () {
                      ref.invalidate(openDashReleaseProvider);
                      ref.read(connectionProvider.notifier).refresh();
                    },
            ),
          ],
        ),
        body: switch (status) {
          null when conn.busy => const Center(child: CircularProgressIndicator()),
          null => ListView(padding: const EdgeInsets.all(20), children: [_Lost(host: conn.host, error: conn.error)]),
          ScooterStatus(isOlaHeadUnit: false) => ListView(
              padding: const EdgeInsets.all(20),
              children: [Notice(
                icon: Icons.block_rounded,
                color: cs.error,
                title: "This isn't an Ola head unit",
                body: "The stock dashboard isn't installed on ${conn.host}, so this app won't change anything on it.",
              )],
            ),
          final s => _Body(status: s, lost: !conn.connected, host: conn.host, error: conn.error),
        },
      ),
    );
  }
}

class _Lost extends ConsumerWidget {
  const _Lost({required this.host, this.error});
  final String? host;
  final String? error;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Notice(
          icon: Icons.wifi_off_rounded,
          color: Theme.of(context).colorScheme.error,
          title: 'Lost the connection to the scooter',
          body: error,
          actions: [
            if (host != null)
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                onPressed: () => ref.read(connectionProvider.notifier).connect(host!),
                child: const Text('Reconnect'),
              ),
          ],
        );
}

class _Body extends ConsumerWidget {
  const _Body({required this.status, required this.lost, required this.host, this.error});
  final ScooterStatus status;
  final bool lost;
  final String? host;
  final String? error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final enabled = ref.watch(actionsEnabledProvider);
    final check = ref.watch(openDashReleaseProvider);
    final latest = switch (check.value) { ReleaseFound(:final release) => release, _ => null };
    final installed = status.openDashInstalled;

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(openDashReleaseProvider);
        await ref.read(connectionProvider.notifier).refresh();
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          if (lost) ...[_Lost(host: host, error: error), const SizedBox(height: 8)],
          const _BackgroundSend(),
          _StatusCard(status: status, latest: latest),
          if (installed && status.stagedBuild != latest?.build)
            OpenDashUpdateNotice(
              installedBuild: status.openDashBuild!,
              onUpdate: enabled ? (r) => installFromGitHub(context, ref, r, update: true) : null,
            ),
          const CompanionUpdateNotice(),
          switch (check) {
            AsyncData(value: CheckFailed(:final why)) => Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Notice(
                  icon: Icons.cloud_off_rounded,
                  color: cs.tertiary,
                  title: "Couldn't check for updates",
                  body: '$why Everything else still works.',
                  actions: [TextButton(onPressed: () => ref.invalidate(openDashReleaseProvider), child: const Text('Retry'))],
                ),
              ),
            AsyncData(value: ReleaseMissing()) => const Padding(
                padding: EdgeInsets.only(top: 16),
                child: Notice(
                    icon: Icons.inventory_2_outlined,
                    title: 'No OpenDash release found',
                    body: 'GitHub has no published release yet. You can still install from a file.'),
              ),
            _ => const SizedBox.shrink(),
          },
          const SectionLabel('OpenDash'),
          if (!installed && latest != null) ...[
            FilledButton.icon(
              onPressed: enabled ? () => installFromGitHub(context, ref, latest, update: false) : null,
              icon: const Icon(Icons.download_rounded),
              label: Text('Install OpenDash ${latest.version}'),
            ),
            const SizedBox(height: 10),
          ],
          if (installed && latest != null && latest.build > status.openDashBuild!) ...[
            if (status.stagedBuild == latest.build) ...[
              Notice(
                icon: Icons.mark_email_read_outlined,
                title: 'OpenDash ${latest.version} is waiting on the dashboard',
                body: 'It was sent to the scooter. Install it there, from Settings, Updates, or update now from here.',
              ),
              const SizedBox(height: 10),
            ],
            FilledButton.icon(
              onPressed: enabled ? () => installFromGitHub(context, ref, latest, update: true) : null,
              icon: const Icon(Icons.system_update_rounded),
              label: Text('Update to ${latest.version}'),
            ),
            const SizedBox(height: 10),
            if (status.accepts != null && status.stagedBuild != latest.build) ...[
              OutlinedButton.icon(
                onPressed: enabled ? () => sendToScooter(context, ref, latest) : null,
                icon: const Icon(Icons.send_to_mobile_outlined),
                label: const Text('Send to scooter'),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 6, 4, 10),
                child: Text('Leaves it on the scooter to install from the dashboard later.',
                    style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ),
            ],
          ],
          if (installed) ...[
            FilledButton.icon(
              onPressed: enabled ? () => launchOpenDash(context, ref, viaHome: status.openDashIsHome) : null,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Start OpenDash'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: enabled ? () => restartOpenDash(context, ref, viaHome: status.openDashIsHome) : null,
              icon: const Icon(Icons.restart_alt_rounded),
              label: const Text('Restart OpenDash'),
            ),
            const SizedBox(height: 10),
            if (latest != null && latest.build <= status.openDashBuild!) ...[
              OutlinedButton.icon(
                onPressed: enabled ? () => installFromGitHub(context, ref, latest, update: false) : null,
                icon: const Icon(Icons.restart_alt_rounded),
                label: Text('Reinstall ${latest.version}'),
              ),
              const SizedBox(height: 10),
            ],
          ],
          OutlinedButton.icon(
            onPressed: enabled ? () => installFromFile(context, ref) : null,
            icon: const Icon(Icons.folder_open_rounded),
            label: const Text('Install from a file'),
          ),
          if (latest != null) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(onPressed: () => showReleaseNotes(context, latest), child: Text("What's new in ${latest.version}")),
            ),
          ],
          Card(
            child: SwitchListTile(
              value: ref.watch(makeHomeProvider),
              onChanged: (v) => ref.read(makeHomeProvider.notifier).set(v),
              title: const Text('Make OpenDash the home screen'),
              subtitle: const Text('When installing or updating'),
            ),
          ),
          if (installed) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: cs.error, side: BorderSide(color: cs.error.withValues(alpha: 0.5))),
              onPressed: enabled ? () => uninstallOpenDash(context, ref) : null,
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('Uninstall OpenDash'),
            ),
          ],
          const SectionLabel('Other apps on the scooter'),
          Text(
            "Apps installed on top of the stock software. This app can't vouch for them; remove any you don't trust.",
            style: t.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          _OtherApps(apps: status.otherApps, enabled: enabled),
          ProblemSection(enabled: enabled),
        ],
      ),
    );
  }
}

/// A send the app started by itself, shown in place instead of taking the
/// screen.
class _BackgroundSend extends ConsumerWidget {
  const _BackgroundSend();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final op = ref.watch(operationProvider);
    if (op == null || !op.background) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final current = op.steps.where((s) => s.state == StepState.running).firstOrNull;
    final failed = op.steps.where((s) => s.state == StepState.failed).firstOrNull;
    final Widget notice;
    if (op.running) {
      notice = Notice(
        icon: Icons.send_to_mobile_outlined,
        title: op.title,
        body: current?.label,
        actions: [
          SizedBox(
            width: double.infinity,
            child: LinearProgressIndicator(value: current?.progress, minHeight: 6, borderRadius: BorderRadius.circular(4)),
          ),
        ],
      );
    } else if (failed != null) {
      notice = Notice(
        icon: Icons.error_outline_rounded,
        color: cs.error,
        title: "Couldn't send the update to the scooter",
        body: failed.detail,
        actions: [TextButton(onPressed: () => ref.read(operationProvider.notifier).clear(), child: const Text('Dismiss'))],
      );
    } else {
      return const SizedBox.shrink();
    }
    return Padding(padding: const EdgeInsets.only(bottom: 16), child: notice);
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.status, required this.latest});
  final ScooterStatus status;
  final Release? latest;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final installed = status.openDashInstalled;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                  color: (installed ? cs.primary : cs.onSurfaceVariant).withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
              child: Icon(installed ? Icons.speed_rounded : Icons.dashboard_outlined, color: installed ? cs.primary : cs.onSurfaceVariant),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(installed ? 'OpenDash ${status.openDashVersion ?? ''}' : "OpenDash isn't installed",
                    style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                Text(installed ? 'Build ${status.openDashBuild}' : 'The stock dashboard is running',
                    style: t.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 4),
          InfoRow('Home screen', status.openDashIsHome ? 'OpenDash' : 'Stock dashboard'),
          InfoRow('Display density', status.density == null ? '—' : '${status.density} dpi'),
          InfoRow('Latest release', latest?.version ?? '—'),
        ]),
      ),
    );
  }
}

class _OtherApps extends ConsumerWidget {
  const _OtherApps({required this.apps, required this.enabled});
  final List<OtherApp> apps;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final others = apps.where((a) => !a.isOpenDash).toList();
    if (others.isEmpty) {
      return Card(
        child: ListTile(
          leading: Icon(Icons.check_circle_outline_rounded, color: cs.primary),
          title: const Text('No other apps installed'),
        ),
      );
    }
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        for (final (i, a) in others.indexed) ...[
          if (i > 0) const Divider(indent: 16),
          ListTile(
            title: Text(a.package, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(a.versionName == null ? 'Unknown version' : 'Version ${a.versionName}'),
            trailing: TextButton(
              style: TextButton.styleFrom(foregroundColor: cs.error),
              onPressed: enabled ? () => uninstallOther(context, ref, a.package) : null,
              child: const Text('Uninstall'),
            ),
          ),
        ],
      ]),
    );
  }
}
