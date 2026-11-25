import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../adb/adb_api.g.dart';
import '../flows.dart';
import '../releases/release.dart';
import '../releases/verify.dart';
import '../scooter/ids.dart';
import '../scooter/operations.dart';
import '../state/prefs.dart';
import '../state/providers.dart';
import 'progress_screen.dart';
import 'widgets.dart';

final hostApiProvider = Provider<AdbHostApi>((ref) => AdbHostApi());

const _uninstallNote = 'OpenDash turned off the stock dashboard\'s update auto-download. Use OpenDash\'s '
    '"Restore stock update settings" first, or turn it on later in the stock dashboard.';

Future<void> _run(BuildContext context, WidgetRef ref, Operation op) {
  final done = ref.read(operationProvider.notifier).start(op);
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProgressScreen()));
  return done;
}

Future<void> installFromGitHub(BuildContext context, WidgetRef ref, Release r, {required bool update}) async {
  final ok = await confirm(context,
      title: update ? 'Update to OpenDash ${r.version}?' : 'Install OpenDash ${r.version}?', body: kParkedWarning, confirm: update ? 'Update' : 'Install');
  if (!ok || !context.mounted) return;
  _run(
      context,
      ref,
      githubInstallOps(ref.read(adbProvider), ref.read(httpProvider), r, ref.read(downloadDirProvider),
          inspect: ref.read(inspectProvider), makeHome: ref.read(prefsProvider).makeHome));
}

/// Leaves the update on the scooter for OpenDash to offer. Nothing restarts,
/// so no "parked" question.
void sendToScooter(BuildContext context, WidgetRef ref, Release r) => _run(
    context,
    ref,
    sendToScooterOps(ref.read(adbProvider), ref.read(httpProvider), r, ref.read(downloadDirProvider),
        inspect: ref.read(inspectProvider), manual: true));

Future<void> installFromFile(BuildContext context, WidgetRef ref) async {
  final picked = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: const ['apk']);
  final path = picked?.files.single.path;
  if (path == null || !context.mounted) return;
  final verdict = verifyApk(
    fileSha256: await sha256OfFile(path),
    info: await ref.read(inspectProvider)(path),
    pinnedCert: kOpenDashCertSha256,
    expectedPackage: kOpenDashPackage,
  );
  if (!context.mounted) return;
  switch (verdict) {
    case Rejected(:final why):
      await showDialog<void>(
          context: context,
          builder: (c) => AlertDialog(
                title: const Text("Can't install this file"),
                content: Text(why),
                actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
              ));
      return;
    case Unofficial():
      final go = await confirm(context,
          title: 'Not an official build',
          body: "This APK is not signed with OpenDash's release key. Install it only if you built it yourself.",
          confirm: 'Install anyway',
          danger: true);
      if (!go || !context.mounted) return;
    case Official():
      break;
  }
  if (!context.mounted) return;
  final ok = await confirm(context, title: 'Install this OpenDash build?', body: kParkedWarning, confirm: 'Install');
  if (!ok || !context.mounted) return;
  _run(context, ref, installOps(ref.read(adbProvider), path, makeHome: ref.read(prefsProvider).makeHome));
}

Future<void> launchOpenDash(BuildContext context, WidgetRef ref, {required bool viaHome}) async {
  final ok = await confirm(context, title: 'Start OpenDash?', body: kParkedWarning, confirm: 'Start');
  if (!ok || !context.mounted) return;
  _run(context, ref, launchOps(ref.read(adbProvider), viaHome: viaHome));
}

/// Force-stop + relaunch (launchOps does a fresh-Surface start), to recover a crashed or white-screened dashboard.
Future<void> restartOpenDash(BuildContext context, WidgetRef ref, {required bool viaHome}) async {
  final ok = await confirm(context, title: 'Restart OpenDash?', body: kParkedWarning, confirm: 'Restart');
  if (!ok || !context.mounted) return;
  _run(context, ref, launchOps(ref.read(adbProvider), viaHome: viaHome));
}

/// Keep the stored prior mode unless the whole uninstall succeeded, so a retry can still restore it.
Future<void> forgetPriorModeIfUninstalled(Operation op, Prefs prefs, String? host) async {
  if (host != null && !op.failed) await prefs.clearPriorScooterMode(host);
}

Future<void> uninstallOpenDash(BuildContext context, WidgetRef ref) async {
  final ok = await confirm(context,
      title: 'Uninstall OpenDash?',
      body: '$kParkedWarning\n\nThe stock dashboard becomes the home screen again and the display density is reset.\n\n$_uninstallNote',
      confirm: 'Uninstall',
      danger: true);
  if (!ok || !context.mounted) return;
  final prefs = ref.read(prefsProvider);
  final host = ref.read(connectionProvider).host;
  final prior = host == null ? null : prefs.priorScooterMode(host);
  final op = uninstallOps(ref.read(adbProvider), host: host, priorMode: prior);
  await _run(context, ref, op);
  await forgetPriorModeIfUninstalled(op, prefs, host);
}

Future<void> uninstallOther(BuildContext context, WidgetRef ref, String pkg) async {
  final ok = await confirm(context,
      title: 'Uninstall $pkg?', body: 'This removes $pkg and its data from the scooter.', confirm: 'Uninstall', danger: true);
  if (!ok || !context.mounted) return;
  _run(context, ref, uninstallOtherOps(ref.read(adbProvider), pkg));
}

Future<void> updateCompanion(BuildContext context, WidgetRef ref, Release r) async {
  final api = ref.read(hostApiProvider);
  if (!await api.canInstallOnPhone()) {
    if (!context.mounted) return;
    final go = await confirm(context,
        title: 'Allow updates',
        body: 'Android needs your permission for this app to install its own updates. Turn on "Allow from this source", then come back.',
        confirm: 'Open settings');
    if (go) await api.openInstallPermission();
    return;
  }
  if (!context.mounted) return;
  _run(
      context,
      ref,
      companionUpdateOps(ref.read(httpProvider), r, ref.read(downloadDirProvider),
          inspect: ref.read(inspectProvider), pinnedCert: kCompanionCertSha256, handOff: api.installOnPhone));
}
