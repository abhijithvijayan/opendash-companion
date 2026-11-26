import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'adb/adb.dart';
import 'adb/adb_api.g.dart';
import 'releases/release.dart';
import 'releases/verify.dart';
import 'scooter/ids.dart';
import 'scooter/operations.dart';

/// Which screen to show when a scooter stays unauthorised after auto-provisioning.
enum AccessFallback { copyKey, sealed }

/// A scooter that refused provisioning (or was injected yet still refuses) can't be
/// helped by copying a key either; only an unreachable/unattempted one can.
AccessFallback accessFallbackFor(ProvisionOutcome? provision) => switch (provision) {
      null || ProvisionOutcome.unreachable => AccessFallback.copyKey,
      ProvisionOutcome.unimplemented || ProvisionOutcome.failed || ProvisionOutcome.ok => AccessFallback.sealed,
    };

typedef Inspect = Future<ApkInfo?> Function(String path);

const ManualRoute _companionByHand = (
  url: 'https://github.com/$kCompanionRepo/releases/latest',
  hint: 'You can also download the latest release from GitHub and install it yourself.',
);

/// Install from a file checks a picked APK against the release key too.
const ManualRoute _openDashByHand = (
  url: 'https://github.com/$kOpenDashRepo/releases/latest',
  hint: 'You can also download the APK from GitHub, then use Install from a file here.',
);

/// Empties the downloads directory. Only one operation runs at a time, so
/// whatever is in it is left over from one that has ended.
Future<void> clearDownloads(Directory dir) async {
  if (!dir.existsSync()) return;
  for (final f in dir.listSync()) {
    await f.delete(recursive: true).catchError((_) => f);
  }
}

(OpStep, StepAction) _download(http.Client client, Release r, Directory dir, void Function(String) done, Duration idleTimeout) => (
      OpStep('download', 'Download ${r.version}'),
      (step, changed) async {
        await clearDownloads(dir);
        try {
          done(await download(client, r, dir, (sent, total) {
            step.progress = total == 0 ? null : sent / total;
            changed();
          }, idleTimeout: idleTimeout, isCancelled: () => step.cancelled));
        } on TimeoutException {
          throw const StepError('The download stopped. Check the internet connection.');
        } on IOException catch (e) {
          throw StepError(e is HttpException ? e.message : 'The download stopped. Check the internet connection.');
        } on http.ClientException {
          throw const StepError('The download stopped. Check the internet connection.');
        }
      }
    );

(OpStep, StepAction) _verify(Release r, String Function() path, Inspect inspect, String pin, String package) => (
      OpStep('verify', 'Check the signature'),
      (step, changed) async {
        final p = path();
        final verdict = verifyApk(
            fileSha256: await sha256OfFile(p), expectedSha256: r.sha256, info: await inspect(p), pinnedCert: pin, expectedPackage: package);
        if (verdict is Rejected) {
          await File(p).delete().catchError((_) => File(p));
          throw StepError(verdict.why);
        }
      }
    );

/// Download an OpenDash release, check it, then install it on the scooter.
Operation githubInstallOps(Adb adb, http.Client client, Release r, Directory dir,
    {required Inspect inspect, required bool makeHome, Duration idleTimeout = const Duration(seconds: 30)}) {
  late String path;
  return Operation('Installing OpenDash ${r.version}', [
    _download(client, r, dir, (p) => path = p, idleTimeout),
    _verify(r, () => path, inspect, kOpenDashCertSha256, kOpenDashPackage),
    ...installSteps(adb, () => path, makeHome: makeHome),
  ], cleanup: () => clearDownloads(dir), manual: _openDashByHand);
}

/// Download an OpenDash release, check it, and leave it in OpenDash's inbox
/// on the scooter for OpenDash to check again and offer. The APK goes first,
/// the release file last: OpenDash ignores the inbox until the release file
/// is there, so a half-sent update is never picked up.
///
/// [manual]: the rider asked for it. OpenDash lets only such a send undo a
/// skip made on the dashboard.
Operation sendToScooterOps(Adb adb, http.Client client, Release r, Directory dir,
    {required Inspect inspect, required bool manual, Duration idleTimeout = const Duration(seconds: 30)}) {
  late String path;
  const inbox = '$kOpenDashInbox/incoming';
  return Operation('Sending OpenDash ${r.version} to the scooter', [
    _download(client, r, dir, (p) => path = p, idleTimeout),
    _verify(r, () => path, inspect, kOpenDashCertSha256, kOpenDashPackage),
    (
      OpStep('send', 'Send it to the scooter'),
      (step, changed) async {
        await shellStep(adb, 'rm -rf $inbox && mkdir -p $inbox')(step, changed);
        await adb.push(path, '$inbox/${r.apkName}.part', onProgress: (sent, total) {
          step.progress = total == 0 ? null : sent / total;
          changed();
        });
        step.progress = null;
        await shellStep(adb, 'mv $inbox/${r.apkName}.part $inbox/${r.apkName}')(step, changed);
        final json = File('${dir.path}/opendash-release.json');
        await json.writeAsString(jsonEncode({
          'version': r.version,
          'build': r.build,
          'apk': r.apkName,
          'sha256': r.sha256,
          'notes': r.notes,
          'published': r.published,
          'manual': manual,
        }));
        await adb.push(json.path, '$inbox/opendash-release.json.part');
        await shellStep(adb, 'mv $inbox/opendash-release.json.part $inbox/opendash-release.json')(step, changed);
      }
    ),
  ], cleanup: () => clearDownloads(dir), manual: _openDashByHand);
}

/// Download a companion release, check it against the companion's own key,
/// then hand it to Android's installer, which asks the rider.
Operation companionUpdateOps(http.Client client, Release r, Directory dir,
    {required Inspect inspect, required String pinnedCert, required Future<void> Function(String path) handOff}) {
  late String path;
  return Operation('Updating this app to ${r.version}', [
    _download(client, r, dir, (p) => path = p, const Duration(seconds: 30)),
    _verify(r, () => path, inspect, pinnedCert, kCompanionPackage),
    // Android's installer has its own copy once handOff returns.
    (OpStep('handoff', 'Open the installer'), (step, changed) => handOff(path)),
  ], cleanup: () => clearDownloads(dir), manual: _companionByHand);
}
