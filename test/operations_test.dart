import 'package:flutter_test/flutter_test.dart';
import 'package:opendash_companion/adb/adb.dart';
import 'package:opendash_companion/scooter/operations.dart';

import 'fake_adb.dart';

Future<List<OpStep>> finish(Operation op) => op.run().last;

void main() {
  test('an install from a file cleans up after itself, also when the install fails', () async {
    var cleaned = 0;
    await finish(installOps(FakeAdb(), '/c/o.apk', makeHome: false, cleanup: () async => cleaned++));
    final failed = installOps(FakeAdb(installError: const InstallFailure('Failure [INSTALL_FAILED_INVALID_APK]')), '/c/o.apk',
        makeHome: false, cleanup: () async => cleaned++);
    await finish(failed);
    expect(failed.failed, isTrue);
    expect(cleaned, 2);
  });

  test('install runs the steps in order', () async {
    final adb = FakeAdb(answers: {'cmd package set-home-activity': 'Success', 'am start': 'Status: ok'});
    final steps = await finish(installOps(adb, '/c/o.apk', makeHome: true));
    expect(adb.log, [
      'wm density reset',
      'settings put secure screensaver_enabled 0',
      'am force-stop in.abhijithvijayan.opendash',
      'install /c/o.apk -r -g',
      'cmd package set-home-activity in.abhijithvijayan.opendash/.MainActivity',
      'input keyevent KEYCODE_WAKEUP',
      'am force-stop in.abhijithvijayan.opendash',
      'am start -a android.intent.action.MAIN -c android.intent.category.HOME',
    ]);
    expect(steps.every((s) => s.state == StepState.done), isTrue);
  });

  test('install without home skips set-home-activity', () async {
    final adb = FakeAdb();
    await finish(installOps(adb, '/c/o.apk', makeHome: false));
    expect(adb.log.any((c) => c.contains('set-home-activity')), isFalse);
  });

  test('install stops at a failing step', () async {
    final adb = FakeAdb(installError: const InstallFailure('Failure [INSTALL_FAILED_UPDATE_INCOMPATIBLE]'));
    final steps = await finish(installOps(adb, '/c/o.apk', makeHome: true));
    final install = steps.firstWhere((s) => s.id == 'install');
    expect(install.state, StepState.failed);
    expect(install.detail, 'A build signed by a different key is installed. Uninstall it first.');
    expect(steps.firstWhere((s) => s.id == 'launch').state, StepState.waiting);
    expect(adb.log.any((c) => c.startsWith('am start')), isFalse);
  });

  test('a lost connection fails the running step with a plain message', () async {
    final adb = FakeAdb(installError: const AdbFailure('Lost the connection to the scooter.'));
    final steps = await finish(installOps(adb, '/c/o.apk', makeHome: true));
    expect(steps.firstWhere((s) => s.id == 'install').detail, 'Lost the connection to the scooter.');
  });

  test('launch error output fails the step', () async {
    final adb = FakeAdb(answers: {'am start': 'Error: Activity class does not exist.'});
    final steps = await finish(launchOps(adb, viaHome: false));
    expect(adb.log, [
      'input keyevent KEYCODE_WAKEUP',
      'am force-stop in.abhijithvijayan.opendash',
      'am start -S -W -n in.abhijithvijayan.opendash/.MainActivity',
    ]);
    expect(steps.single.state, StepState.failed);
  });

  test('a step can see that its operation was cancelled (so long work can bail)', () {
    final op = Operation('t', [(OpStep('a', 'A'), (s, ch) async {})]);
    expect(op.steps.single.cancelled, isFalse);
    op.cancel();
    expect(op.steps.single.cancelled, isTrue);
  });

  test('cancelling an operation stops it and leaves the remaining steps unrun', () async {
    late Operation op;
    op = Operation('t', [
      (OpStep('a', 'A'), (step, changed) async => op.cancel()),
      (OpStep('b', 'B'), (step, changed) async => fail('must not run after cancel')),
    ]);
    final steps = await op.run().last;
    expect(op.cancelled, isTrue);
    expect(steps.firstWhere((s) => s.id == 'b').state, StepState.waiting);
  });

  test('a step that fails because of a cancel is marked cancelled, not failed', () async {
    late Operation op;
    op = Operation('t', [
      (OpStep('a', 'A'), (step, changed) async {
        op.cancel();
        throw const AdbFailure('Lost the connection to the scooter.');
      }),
    ]);
    final steps = await op.run().last;
    expect(steps.single.state, StepState.cancelled);
    expect(steps.single.detail, isNull);
  });

  test('launch stock dash via home wakes, force-stops stock, then fires the HOME intent', () async {
    final adb = FakeAdb(answers: {'am start': 'Starting: Intent { act=android.intent.action.MAIN }'});
    final steps = await finish(launchStockOps(adb, viaHome: true));
    expect(adb.log, [
      'input keyevent KEYCODE_WAKEUP',
      'am force-stop com.olaelectric.hmiclient',
      'am start -a android.intent.action.MAIN -c android.intent.category.HOME',
    ]);
    expect(steps.single.state, StepState.done);
  });

  test('launch stock dash directly when the stock dash is not the home app', () async {
    final adb = FakeAdb(answers: {'am start': 'Status: ok'});
    final steps = await finish(launchStockOps(adb, viaHome: false));
    expect(adb.log, [
      'input keyevent KEYCODE_WAKEUP',
      'am force-stop com.olaelectric.hmiclient',
      'am start -S -W -n com.olaelectric.hmiclient/.MainActivity',
    ]);
    expect(steps.single.state, StepState.done);
  });

  test('launch via home wakes, force-stops, then fires the HOME intent', () async {
    final adb = FakeAdb(answers: {'am start': 'Starting: Intent { act=android.intent.action.MAIN }'});
    final steps = await finish(launchOps(adb, viaHome: true));
    expect(adb.log, [
      'input keyevent KEYCODE_WAKEUP',
      'am force-stop in.abhijithvijayan.opendash',
      'am start -a android.intent.action.MAIN -c android.intent.category.HOME',
    ]);
    expect(steps.single.state, StepState.done);
  });

  test('home launch error output fails the step too', () async {
    final adb = FakeAdb(answers: {'am start': 'Error: no home'});
    final steps = await finish(launchOps(adb, viaHome: true));
    expect(steps.single.state, StepState.failed);
  });

  test('home screen refusal is a warning, the launch still runs', () async {
    final adb = FakeAdb(answers: {'cmd package set-home-activity': 'Error: unknown command', 'am start': 'Status: ok'});
    final steps = await finish(installOps(adb, '/c/o.apk', makeHome: true));
    expect(steps.firstWhere((s) => s.id == 'home').state, StepState.warning);
    expect(steps.firstWhere((s) => s.id == 'launch').state, StepState.done);
  });

  test('uninstall gives home back, starts stock, uninstalls, resets density', () async {
    final adb = FakeAdb(answers: {'pm uninstall': 'Success', 'cmd package set-home-activity': 'Success'});
    final steps = await finish(uninstallOps(adb));
    expect(adb.log, [
      'cmd package set-home-activity com.olaelectric.hmiclient/.MainActivity',
      'am start -W -n com.olaelectric.hmiclient/.MainActivity',
      'pm uninstall in.abhijithvijayan.opendash',
      'wm density reset',
    ]);
    expect(steps.every((s) => s.state == StepState.done), isTrue);
  });

  test('uninstall restores the prior mode as the last step', () async {
    final adb = FakeAdb(answers: {'pm uninstall': 'Success', 'cmd package set-home-activity': 'Success'});
    final steps = await finish(uninstallOps(adb, host: 'h', priorMode: 'cust'));
    expect(adb.log.last, 'setScooterMode h cust');
    expect(steps.last.id, 'mode');
    expect(steps.every((s) => s.state == StepState.done), isTrue);
  });

  test('uninstall skips the mode restore when there is no prior or it is mfg', () async {
    for (final mode in [null, 'mfg']) {
      final adb = FakeAdb(answers: {'pm uninstall': 'Success', 'cmd package set-home-activity': 'Success'});
      await finish(uninstallOps(adb, host: 'h', priorMode: mode));
      expect(adb.log.any((l) => l.startsWith('setScooterMode')), isFalse);
    }
  });

  test('a dropped link while restoring the mode does not fail the uninstall', () async {
    final adb = FakeAdb(answers: {'pm uninstall': 'Success', 'cmd package set-home-activity': 'Success'})..setModeError = const AdbFailure('lost');
    final steps = await finish(uninstallOps(adb, host: 'h', priorMode: 'cust'));
    expect(steps.every((s) => s.state == StepState.done), isTrue);
  });

  test('pm uninstall without Success fails', () async {
    final adb = FakeAdb(answers: {'pm uninstall': 'Failure [DELETE_FAILED_INTERNAL_ERROR]', 'cmd package set-home-activity': 'Success'});
    final steps = await finish(uninstallOps(adb));
    expect(steps.firstWhere((s) => s.id == 'uninstall').state, StepState.failed);
    expect(adb.log.contains('wm density reset'), isFalse);
  });

  test('uninstalling another app', () async {
    final adb = FakeAdb(answers: {'pm uninstall': 'Success'});
    await finish(uninstallOtherOps(adb, 'com.example.mod'));
    expect(adb.log, ['pm uninstall com.example.mod']);
  });

  test('uninstalling the stock dashboard or Ola packages is refused', () {
    final adb = FakeAdb();
    expect(() => uninstallOtherOps(adb, 'com.olaelectric.hmiclient'), throwsArgumentError);
    expect(() => uninstallOtherOps(adb, 'com.olaelectric.ota'), throwsArgumentError);
  });

  test('readStatus', () async {
    final adb = FakeAdb(answers: {
      'pm path com.olaelectric.hmiclient': 'package:/system/priv-app/HMIClient/HMIClient.apk',
      'dumpsys package in.abhijithvijayan.opendash': '    versionCode=2041 minSdk=24\n    versionName=0.2.1\n',
      'cmd package resolve-activity': 'priority=0\nin.abhijithvijayan.opendash/.MainActivity\n',
      'wm density': 'Physical density: 240\nOverride density: 160\n',
      'pm list packages -3': 'package:in.abhijithvijayan.opendash\npackage:com.example.mod\npackage:com.olaelectric.ota\n',
      'dumpsys package com.example.mod': '    versionCode=3\n    versionName=1.2\n',
      'cat /sdcard/Android/data/in.abhijithvijayan.opendash/files/companion/accepts.json': '{"v":1,"auto":false,"installed":2041,"skipped":0}',
      'cat /sdcard/Android/data/in.abhijithvijayan.opendash/files/companion/incoming/opendash-release.json': '{"build":2050,"apk":"o.apk","sha256":"ab"}',
    });
    final s = await readStatus(adb);
    expect(s.isOlaHeadUnit, isTrue);
    expect(s.openDashVersion, '0.2.1');
    expect(s.openDashBuild, 2041);
    expect(s.openDashIsHome, isTrue);
    expect(s.density, 160);
    expect(s.accepts!.auto, isFalse);
    expect(s.stagedBuild, 2050);
    expect(s.otherApps.map((a) => (a.package, a.versionName, a.isOpenDash)), [
      ('in.abhijithvijayan.opendash', '0.2.1', true),
      ('com.example.mod', '1.2', false),
    ]);
  });

  test('readStatus on a device without the stock dashboard', () async {
    final s = await readStatus(FakeAdb());
    expect(s.isOlaHeadUnit, isFalse);
    expect(s.openDashBuild, isNull);
  });
}
