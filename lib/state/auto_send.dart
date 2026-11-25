import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../flows.dart';
import '../releases/release.dart';
import '../scooter/operations.dart';
import 'providers.dart';

/// Whether the app sends [r] to the scooter without being asked: only when
/// OpenDash checks for updates by itself, and never a build skipped on either
/// side or already sent.
bool shouldAutoSend(Release r, ScooterStatus s, {required int companionSkipped}) {
  final accepts = s.accepts;
  final installed = s.openDashBuild;
  if (accepts == null || !accepts.auto || installed == null) return false;
  if (r.build <= installed) return false;
  if (r.build == accepts.skipped || r.build == companionSkipped) return false;
  return s.stagedBuild != r.build;
}

/// Sends a new OpenDash release to a connected scooter when OpenDash wants
/// it, once per scooter and build in a session.
class AutoSendNotifier extends Notifier<void> {
  final _tried = <String>{};

  @override
  void build() {
    ref.listen(connectionProvider, (_, _) => _consider());
    ref.listen(openDashReleaseProvider, (_, _) => _consider());
  }

  void _consider() {
    final conn = ref.read(connectionProvider);
    final status = conn.status;
    final release = ref.read(openDashReleaseProvider).value;
    if (!conn.connected || conn.busy || status == null || release is! ReleaseFound) return;
    if (!ref.read(ackProvider) || ref.read(operationProvider.notifier).running) return;
    final r = release.release;
    if (!shouldAutoSend(r, status, companionSkipped: ref.read(skippedOpenDashProvider))) return;
    if (!_tried.add('${conn.host}#${r.build}')) return;
    ref.read(operationProvider.notifier).start(
          sendToScooterOps(ref.read(adbProvider), ref.read(httpProvider), r, ref.read(downloadDirProvider),
              inspect: ref.read(inspectProvider), manual: false),
          background: true,
        );
  }
}

final autoSendProvider = NotifierProvider<AutoSendNotifier, void>(AutoSendNotifier.new);
