import 'package:flutter_test/flutter_test.dart';
import 'package:opendash_companion/scooter/operations.dart';
import 'package:opendash_companion/state/prefs.dart';
import 'package:opendash_companion/ui/actions.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_adb.dart';

Future<Prefs> _prefs() async {
  SharedPreferences.setMockInitialValues({});
  final p = Prefs(await SharedPreferences.getInstance());
  await p.setPriorScooterMode('h', 'cust');
  return p;
}

void main() {
  test('a failed uninstall keeps the prior mode for a retry', () async {
    final prefs = await _prefs();
    final adb = FakeAdb(answers: {'pm uninstall': 'Failure [DELETE_FAILED]', 'cmd package set-home-activity': 'Success'});
    final op = uninstallOps(adb, host: 'h', priorMode: 'cust');
    await op.run().last;
    await forgetPriorModeIfUninstalled(op, prefs, 'h');
    expect(prefs.priorScooterMode('h'), 'cust');
    expect(adb.log.any((l) => l.startsWith('setScooterMode')), isFalse);
  });

  test('a successful uninstall clears the prior mode', () async {
    final prefs = await _prefs();
    final adb = FakeAdb(answers: {'pm uninstall': 'Success', 'cmd package set-home-activity': 'Success'});
    final op = uninstallOps(adb, host: 'h', priorMode: 'cust');
    await op.run().last;
    await forgetPriorModeIfUninstalled(op, prefs, 'h');
    expect(prefs.priorScooterMode('h'), isNull);
  });
}
