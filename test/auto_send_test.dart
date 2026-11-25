import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:opendash_companion/adb/adb_api.g.dart';
import 'package:opendash_companion/releases/release.dart';
import 'package:opendash_companion/scooter/ids.dart';
import 'package:opendash_companion/scooter/operations.dart';
import 'package:opendash_companion/scooter/parse.dart';
import 'package:opendash_companion/state/auto_send.dart';
import 'package:opendash_companion/state/prefs.dart';
import 'package:opendash_companion/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_adb.dart';

const _rel = Release(version: '0.2.2', build: 2050, sha256: 'ab', apkUrl: 'u', apkName: 'o.apk');

ScooterStatus _status({bool? auto = true, int installed = 2041, int skipped = 0, int? staged}) => ScooterStatus(
      isOlaHeadUnit: true,
      openDashBuild: installed,
      accepts: auto == null ? null : OpenDashAccepts(auto: auto, installed: installed, skipped: skipped),
      stagedBuild: staged,
    );

final _apk = List.filled(64, 3);
final _sha = sha256.convert(_apk).toString();

MockClient _github() => MockClient((req) async {
      final u = req.url.toString();
      if (u.startsWith('https://api.github.com/')) {
        return http.Response(
            jsonEncode({
              'body': 'n',
              'assets': [
                {'name': 'opendash-release.json', 'browser_download_url': 'https://dl/j'},
                {'name': 'o.apk', 'browser_download_url': 'https://dl/o.apk'},
              ],
            }),
            200);
      }
      if (u == 'https://dl/j') return http.Response(jsonEncode({'version': '0.2.2', 'build': 2050, 'apk': 'o.apk', 'sha256': _sha}), 200);
      return http.Response.bytes(_apk, 200);
    });

Future<(ProviderContainer, FakeAdb)> _make({required String accepts}) async {
  SharedPreferences.setMockInitialValues({'ack_version': kAckVersion});
  final adb = FakeAdb(answers: {
    'pm path com.olaelectric.hmiclient': 'package:/x.apk',
    'dumpsys package in.abhijithvijayan.opendash': 'versionCode=2041\nversionName=0.2.1\n',
    'cat $kOpenDashInbox/accepts.json': accepts,
  });
  final dir = await Directory.systemTemp.createTemp();
  final c = ProviderContainer(overrides: [
    prefsProvider.overrideWithValue(Prefs(await SharedPreferences.getInstance())),
    adbProvider.overrideWithValue(adb),
    httpProvider.overrideWithValue(_github()),
    inspectProvider.overrideWithValue((_) async =>
        ApkInfo(packageName: kOpenDashPackage, versionName: '0.2.2', versionCode: 2050, certSha256: [kOpenDashCertSha256])),
    downloadDirProvider.overrideWithValue(dir),
  ]);
  addTearDown(c.dispose);
  c.listen(autoSendProvider, (_, _) {});
  return (c, adb);
}

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 300));

void main() {
  group('shouldAutoSend', () {
    test('newer, auto on, nothing skipped or staged → send', () => expect(shouldAutoSend(_rel, _status(), companionSkipped: 0), isTrue));
    test('OpenDash checks only when asked → no', () => expect(shouldAutoSend(_rel, _status(auto: false), companionSkipped: 0), isFalse));
    test('OpenDash published nothing → no', () => expect(shouldAutoSend(_rel, _status(auto: null), companionSkipped: 0), isFalse));
    test('skipped on the dashboard → no', () => expect(shouldAutoSend(_rel, _status(skipped: 2050), companionSkipped: 0), isFalse));
    test('skipped in this app → no', () => expect(shouldAutoSend(_rel, _status(), companionSkipped: 2050), isFalse));
    test('already sent → no', () => expect(shouldAutoSend(_rel, _status(staged: 2050), companionSkipped: 0), isFalse));
    test('not newer → no', () => expect(shouldAutoSend(_rel, _status(installed: 2050), companionSkipped: 0), isFalse));
  });

  test('connecting to a scooter that wants updates sends the new one by itself, once', () async {
    final (c, adb) = await _make(accepts: '{"v":1,"auto":true,"installed":2041,"skipped":0}');
    await c.read(connectionProvider.notifier).connect('10.1.1.5');
    await _settle();
    expect(adb.log.where((l) => l.startsWith('push ')), hasLength(2));
    expect(c.read(operationProvider)!.background, isTrue);
    await c.read(connectionProvider.notifier).refresh();
    await _settle();
    expect(adb.log.where((l) => l.startsWith('push ')), hasLength(2), reason: 'not sent twice in a session');
  });

  test('with automatic checks off on the dashboard, nothing is sent by itself', () async {
    final (c, adb) = await _make(accepts: '{"v":1,"auto":false,"installed":2041,"skipped":0}');
    await c.read(connectionProvider.notifier).connect('10.1.1.5');
    await _settle();
    expect(adb.log.where((l) => l.startsWith('push ')), isEmpty);
    expect(c.read(operationProvider), isNull);
  });
}
