import 'dart:async';

import '../adb/adb.dart';
import 'ids.dart';
import 'parse.dart';
import 'pm_errors.dart';

enum StepState { waiting, running, done, warning, failed }

class OpStep {
  OpStep(this.id, this.label);

  final String id;
  final String label;
  StepState state = StepState.waiting;
  String? detail;

  /// 0..1 while bytes are moving, else null.
  double? progress;

  OpStep copy() => OpStep(id, label)
    ..state = state
    ..detail = detail
    ..progress = progress;
}

/// A step's work. Throw [StepError] to fail it, [StepWarning] to warn and go on.
typedef StepAction = Future<void> Function(OpStep step, void Function() changed);

class StepError implements Exception {
  const StepError(this.message);
  final String message;
}

class StepWarning implements Exception {
  const StepWarning(this.message);
  final String message;
}

class Operation {
  Operation(this.title, List<(OpStep, StepAction)> plan)
      : steps = [for (final p in plan) p.$1],
        _actions = [for (final p in plan) p.$2];

  final String title;
  final List<OpStep> steps;
  final List<StepAction> _actions;

  bool get failed => steps.any((s) => s.state == StepState.failed);

  /// Snapshots of every step after each change; the last one is final.
  Stream<List<OpStep>> run() {
    final out = StreamController<List<OpStep>>();
    void emit() => out.add([for (final s in steps) s.copy()]);
    () async {
      emit();
      for (var i = 0; i < steps.length; i++) {
        final step = steps[i];
        step.state = StepState.running;
        emit();
        try {
          await _actions[i](step, emit);
          step.state = StepState.done;
        } on StepWarning catch (w) {
          step.state = StepState.warning;
          step.detail = w.message;
        } on StepError catch (e) {
          step.state = StepState.failed;
          step.detail = e.message;
        } on InstallFailure catch (e) {
          step.state = StepState.failed;
          step.detail = explainInstallFailure(e.raw);
        } on AdbFailure catch (e) {
          step.state = StepState.failed;
          step.detail = e.message;
        } catch (e) {
          step.state = StepState.failed;
          step.detail = 'Something went wrong: $e';
        }
        step.progress = null;
        emit();
        if (step.state == StepState.failed) break;
      }
      await out.close();
    }();
    return out.stream;
  }
}

String _firstLine(String s) => s.trim().split('\n').first;

StepAction shellStep(Adb adb, String cmd) => (step, changed) async {
      final r = await adb.shell(cmd);
      if (r.exitCode != 0) throw StepError(_firstLine(r.output).isEmpty ? 'The scooter refused: $cmd' : _firstLine(r.output));
    };

StepAction _soft(Adb adb, String cmd, String warning) => (step, changed) async {
      final r = await adb.shell(cmd);
      if (r.exitCode != 0 || r.output.contains('Error') || r.output.contains('Exception')) throw StepWarning(warning);
    };

StepAction _launch(Adb adb) => (step, changed) async {
      await adb.shell('am force-stop $kOpenDashPackage');
      final r = await adb.shell('am start -S -W -n $kOpenDashActivity');
      if (r.output.contains('Error') || r.output.contains('Exception')) throw StepError(_firstLine(r.output));
    };

Operation installOps(Adb adb, String apkPath, {required bool makeHome}) =>
    Operation('Installing OpenDash', installSteps(adb, () => apkPath, makeHome: makeHome));

/// The install steps, reading the APK's path only when the install starts
/// (a download step before them supplies it).
List<(OpStep, StepAction)> installSteps(Adb adb, String Function() apkPath, {required bool makeHome}) => [
      (OpStep('density', 'Set the display density'), shellStep(adb, 'wm density 160')),
      (OpStep('screensaver', 'Turn off the screensaver'),
          _soft(adb, 'settings put secure screensaver_enabled 0', "Couldn't turn off the screensaver.")),
      (OpStep('stop', 'Stop OpenDash'), shellStep(adb, 'am force-stop $kOpenDashPackage')),
      (
        OpStep('install', 'Install OpenDash'),
        (step, changed) => adb.install(apkPath(), const ['-r', '-g'], onProgress: (sent, total) {
              step.progress = total == 0 ? null : sent / total;
              changed();
            })
      ),
      if (makeHome)
        (
          OpStep('home', 'Make OpenDash the home screen'),
          _soft(adb, 'cmd package set-home-activity $kOpenDashActivity',
              "Couldn't make it the home screen. Pick OpenDash when the scooter asks which home app to use.")
        ),
      (OpStep('launch', 'Start OpenDash'), _launch(adb)),
    ];

Operation launchOps(Adb adb) => Operation('Starting OpenDash', [(OpStep('launch', 'Start OpenDash'), _launch(adb))]);

StepAction _pmUninstall(Adb adb, String pkg) => (step, changed) async {
      final r = await adb.shell('pm uninstall $pkg');
      if (!r.output.contains('Success')) throw StepError(_firstLine(r.output).isEmpty ? 'Uninstall failed.' : _firstLine(r.output));
    };

Operation uninstallOps(Adb adb) => Operation('Removing OpenDash', [
      (
        OpStep('home', 'Give the home screen back to the stock dashboard'),
        _soft(adb, 'cmd package set-home-activity $kStockActivity',
            "Couldn't set the stock dashboard as home. Pick it when the scooter asks which home app to use.")
      ),
      (OpStep('stock', 'Start the stock dashboard'), _soft(adb, 'am start -W -n $kStockActivity', "Couldn't start the stock dashboard; it starts on the next boot.")),
      (OpStep('uninstall', 'Uninstall OpenDash'), _pmUninstall(adb, kOpenDashPackage)),
      (OpStep('density', 'Reset the display density'), shellStep(adb, 'wm density reset')),
    ]);

Operation uninstallOtherOps(Adb adb, String pkg) {
  if (isStockPackage(pkg)) throw ArgumentError.value(pkg, 'pkg', 'stock packages are never removed');
  return Operation('Removing $pkg', [(OpStep('uninstall', 'Uninstall $pkg'), _pmUninstall(adb, pkg))]);
}

class OtherApp {
  const OtherApp(this.package, this.versionName, {required this.isOpenDash});
  final String package;
  final String? versionName;
  final bool isOpenDash;
}

class ScooterStatus {
  const ScooterStatus({
    required this.isOlaHeadUnit,
    this.openDashVersion,
    this.openDashBuild,
    this.openDashIsHome = false,
    this.density,
    this.otherApps = const [],
    this.accepts,
    this.stagedBuild,
  });

  final bool isOlaHeadUnit;
  final String? openDashVersion;
  final int? openDashBuild;
  final bool openDashIsHome;
  final int? density;
  final List<OtherApp> otherApps;

  /// OpenDash's answer for this app; null when it hasn't published one.
  final OpenDashAccepts? accepts;

  /// The build already sent and waiting on the dashboard.
  final int? stagedBuild;

  bool get openDashInstalled => openDashBuild != null;
}

Future<ScooterStatus> readStatus(Adb adb) async {
  final stock = await adb.shell('pm path $kStockPackage');
  if (!stock.output.contains('package:')) return const ScooterStatus(isOlaHeadUnit: false);
  final od = parseDumpsysVersion((await adb.shell('dumpsys package $kOpenDashPackage')).output);
  final home = parseHomeActivity(
      (await adb.shell('cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME')).output);
  final density = parseDensity((await adb.shell('wm density')).output);
  final pkgs = parseThirdPartyPackages((await adb.shell('pm list packages -3')).output);
  final others = <OtherApp>[];
  for (final pkg in pkgs) {
    if (pkg == kOpenDashPackage) {
      others.add(OtherApp(pkg, od.versionName, isOpenDash: true));
    } else {
      final v = parseDumpsysVersion((await adb.shell('dumpsys package $pkg')).output);
      others.add(OtherApp(pkg, v.versionName, isOpenDash: false));
    }
  }
  OpenDashAccepts? accepts;
  int? staged;
  if (od.versionCode != null) {
    accepts = parseAccepts((await adb.shell('cat $kOpenDashInbox/accepts.json')).output);
    staged = parseStagedBuild((await adb.shell('cat $kOpenDashInbox/incoming/opendash-release.json')).output);
  }
  return ScooterStatus(
    isOlaHeadUnit: true,
    accepts: accepts,
    stagedBuild: staged,
    openDashVersion: od.versionName,
    openDashBuild: od.versionCode,
    openDashIsHome: home == kOpenDashActivity,
    density: density.override ?? density.physical,
    otherApps: others,
  );
}
