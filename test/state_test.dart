import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opendash_companion/adb/adb.dart';
import 'package:opendash_companion/state/prefs.dart';
import 'package:opendash_companion/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_adb.dart';

Future<ProviderContainer> make({Map<String, Object> prefs = const {}, Adb? adb}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final p = Prefs(await SharedPreferences.getInstance());
  final c = ProviderContainer(overrides: [
    prefsProvider.overrideWithValue(p),
    adbProvider.overrideWithValue(adb ?? FakeAdb(answers: _scooter)),
  ]);
  addTearDown(c.dispose);
  return c;
}

const _scooter = {
  'pm path com.olaelectric.hmiclient': 'package:/system/priv-app/HMIClient/HMIClient.apk',
  'dumpsys package in.abhijithvijayan.opendash': 'versionCode=2041\nversionName=0.2.1\n',
};

void main() {
  test('actions stay off until the acknowledgement is accepted', () async {
    final c = await make();
    await c.read(connectionProvider.notifier).connect('10.1.1.5');
    expect(c.read(actionsEnabledProvider), isFalse);
    await c.read(ackProvider.notifier).accept();
    expect(c.read(actionsEnabledProvider), isTrue);
  });

  test('an accepted acknowledgement survives a restart', () async {
    final c = await make(prefs: {'ack_version': kAckVersion});
    expect(c.read(ackProvider), isTrue);
  });

  test('connecting remembers the host with the OpenDash build seen', () async {
    final c = await make();
    await c.read(connectionProvider.notifier).connect('10.1.1.5');
    final r = c.read(recentsProvider);
    expect(r.single.host, '10.1.1.5');
    expect(r.single.build, 2041);
    expect(c.read(knownBuildProvider), 2041);
  });

  test('recents keep five, newest first, one per host', () async {
    final c = await make();
    final n = c.read(recentsProvider.notifier);
    for (final h in ['a', 'b', 'c', 'd', 'e', 'f', 'b']) {
      await n.remember(h);
    }
    expect(c.read(recentsProvider).map((r) => r.host), ['b', 'f', 'e', 'd', 'c']);
  });

  test('remembering without a build keeps the old one', () async {
    final c = await make();
    final n = c.read(recentsProvider.notifier);
    await n.remember('a', build: 7);
    await n.remember('a');
    expect(c.read(recentsProvider).single.build, 7);
  });

  test('recents collapse a scooter seen over link-local then IPv4 into one entry, preferring IPv4', () async {
    final c = await make();
    final n = c.read(recentsProvider.notifier);
    await n.remember('fe80::b6ed:d5ff:fe25:2a61%wlan0', mac: 'b4:ed:d5:25:2a:61');
    await n.remember('172.20.10.5', mac: 'b4:ed:d5:25:2a:61');
    final r = c.read(recentsProvider);
    expect(r.length, 1);
    expect(r.single.host, '172.20.10.5');
    expect(r.single.addresses, containsAll(['fe80::b6ed:d5ff:fe25:2a61%wlan0', '172.20.10.5']));
  });

  test('old host-only recents load without data loss', () async {
    final c = await make(prefs: {'recents': '[{"host":"1.2.3.4","build":9,"seen":5}]'});
    final r = c.read(recentsProvider).single;
    expect(r.host, '1.2.3.4');
    expect(r.mac, isNull);
    expect(r.addresses, ['1.2.3.4']);
    expect(r.build, 9);
  });

  test('forget removes a merged entry by one of its addresses', () async {
    final c = await make();
    final n = c.read(recentsProvider.notifier);
    await n.remember('fe80::1%wlan0', mac: 'aa:aa:aa:aa:aa:aa');
    await n.remember('172.20.10.5', mac: 'aa:aa:aa:aa:aa:aa');
    await n.forget('172.20.10.5');
    expect(c.read(recentsProvider), isEmpty);
  });

  test('a prior non-mfg mode is remembered after provisioning', () async {
    final adb = _ProvisionsThenConnects()..provisionDetail = 'cust';
    final c = await make(adb: adb);
    await c.read(connectionProvider.notifier).connect('10.1.1.5');
    expect(c.read(prefsProvider).priorScooterMode('10.1.1.5'), 'cust');
  });

  test('an already-mfg scooter records no prior mode', () async {
    final adb = _ProvisionsThenConnects()..provisionDetail = 'mfg';
    final c = await make(adb: adb);
    await c.read(connectionProvider.notifier).connect('10.1.1.5');
    expect(c.read(prefsProvider).priorScooterMode('10.1.1.5'), isNull);
  });

  test('an unauthorised phone is provisioned and then connects', () async {
    final adb = _ProvisionsThenConnects();
    final c = await make(adb: adb);
    await c.read(connectionProvider.notifier).connect('10.1.1.5');
    expect(c.read(connectionProvider).connected, isTrue);
    expect(adb.provisionCalls, 1);
  });

  test('provision unimplemented leaves it unauthorised with the outcome recorded', () async {
    final c = await make(adb: _Refusing()..provisionOutcome = ProvisionOutcome.unimplemented);
    await c.read(ackProvider.notifier).accept();
    await c.read(connectionProvider.notifier).connect('10.1.1.5');
    final s = c.read(connectionProvider);
    expect(s.outcome, ConnectOutcome.unauthorized);
    expect(s.provision, ProvisionOutcome.unimplemented);
    expect(c.read(actionsEnabledProvider), isFalse);
  });

  test('provision ok but still unauthorised does not loop', () async {
    final adb = _Refusing()..provisionOutcome = ProvisionOutcome.ok;
    final c = await make(adb: adb);
    await c.read(connectionProvider.notifier).connect('10.1.1.5');
    expect(c.read(connectionProvider).provision, ProvisionOutcome.ok);
    expect(c.read(connectionProvider).connected, isFalse);
    expect(adb.provisionCalls, 1);
  });

  test('an already-trusted phone never provisions', () async {
    final adb = FakeAdb(answers: _scooter);
    final c = await make(adb: adb);
    await c.read(connectionProvider.notifier).connect('10.1.1.5');
    expect(adb.provisionCalls, 0);
  });

  test('skipping a build is remembered', () async {
    final c = await make();
    await c.read(skippedOpenDashProvider.notifier).skip(2050);
    expect(c.read(skippedOpenDashProvider), 2050);
    expect(c.read(prefsProvider).skippedOpenDash, 2050);
  });

  group('normalizeHost', () {
    test('drops the adb port people copy from `adb connect`', () {
      expect(normalizeHost(' 192.168.1.42:5555 '), '192.168.1.42');
      expect(normalizeHost('[fe80::1%wlan0]:5555'), 'fe80::1%wlan0');
    });
    test('leaves plain addresses alone', () {
      expect(normalizeHost('192.168.1.42'), '192.168.1.42');
      expect(normalizeHost('fe80::b20c:9dff:feba:a122%wlan0'), 'fe80::b20c:9dff:feba:a122%wlan0');
    });
  });

  test('connecting to "ip:5555" connects to the ip', () async {
    final adb = _Recording();
    final c = await make(adb: adb);
    await c.read(connectionProvider.notifier).connect('10.1.1.5:5555');
    expect(adb.hosts, ['10.1.1.5']);
  });
}

class _Refusing extends FakeAdb {
  @override
  Future<ConnectOutcome> connect(String host) async => ConnectOutcome.unauthorized;
}

class _Recording extends FakeAdb {
  _Recording() : super(answers: _scooter);
  final hosts = <String>[];
  @override
  Future<ConnectOutcome> connect(String host) async {
    hosts.add(host);
    return ConnectOutcome.ok;
  }
}

class _ProvisionsThenConnects extends FakeAdb {
  _ProvisionsThenConnects() : super(answers: _scooter);
  @override
  Future<ConnectOutcome> connect(String host) async =>
      provisionCalls == 0 ? ConnectOutcome.unauthorized : ConnectOutcome.ok;
}
