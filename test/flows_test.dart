import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:opendash_companion/adb/adb_api.g.dart';
import 'package:opendash_companion/flows.dart';
import 'package:opendash_companion/releases/release.dart';
import 'package:opendash_companion/scooter/ids.dart';
import 'package:opendash_companion/scooter/operations.dart';

import 'fake_adb.dart';

final _bytes = List.filled(64, 1);
final _sha = sha256.convert(_bytes).toString();
final _client = MockClient((_) async => http.Response.bytes(_bytes, 200));

Release _rel(String sha) => Release(version: '0.2.2', build: 2050, sha256: sha, apkUrl: 'https://dl/o.apk', apkName: 'o.apk');

ApkInfo _info(String cert) => ApkInfo(packageName: kOpenDashPackage, versionName: '0.2.2', versionCode: 2050, certSha256: [cert]);

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp());

  test('an official download is installed', () async {
    final adb = FakeAdb(answers: {'am start': 'Status: ok'});
    final op = githubInstallOps(adb, _client, _rel(_sha), dir, inspect: (_) async => _info(kOpenDashCertSha256), makeHome: true);
    final steps = await op.run().last;
    expect(steps.map((s) => s.id).take(2), ['download', 'verify']);
    expect(steps.every((s) => s.state == StepState.done), isTrue);
    expect(adb.log.where((c) => c.startsWith('install ')).single, startsWith('install ${dir.path}/o.apk'));
  });

  test('a checksum mismatch never reaches the scooter', () async {
    final adb = FakeAdb();
    final op = githubInstallOps(adb, _client, _rel('00'), dir, inspect: (_) async => _info(kOpenDashCertSha256), makeHome: true);
    final steps = await op.run().last;
    expect(steps.firstWhere((s) => s.id == 'verify').state, StepState.failed);
    expect(adb.log, isEmpty);
  });

  test('a download signed by another key never reaches the scooter', () async {
    final adb = FakeAdb();
    final op = githubInstallOps(adb, _client, _rel(_sha), dir, inspect: (_) async => _info('ff'), makeHome: true);
    await op.run().last;
    expect(adb.log, isEmpty);
  });

  test('the companion update is verified against its own pin before Android sees it', () async {
    final handed = <String>[];
    final op = companionUpdateOps(_client, _rel(_sha), dir,
        inspect: (_) async => ApkInfo(packageName: kCompanionPackage, versionName: '', versionCode: 2, certSha256: ['ab']),
        pinnedCert: 'ab',
        handOff: (p) async => handed.add(p));
    final steps = await op.run().last;
    expect(steps.every((s) => s.state == StepState.done), isTrue);
    expect(handed.single, '${dir.path}/o.apk');
  });

  test('a companion update with the wrong key is not handed to Android', () async {
    final handed = <String>[];
    final op = companionUpdateOps(_client, _rel(_sha), dir,
        inspect: (_) async => ApkInfo(packageName: kCompanionPackage, versionName: '', versionCode: 2, certSha256: ['cd']),
        pinnedCert: 'ab',
        handOff: (p) async => handed.add(p));
    await op.run().last;
    expect(handed, isEmpty);
  });

  test('a stalled download fails its step with a plain message', () async {
    final client = MockClient.streaming((req, body) async => http.StreamedResponse(StreamController<List<int>>().stream, 200));
    final adb = FakeAdb();
    final op = githubInstallOps(adb, client, _rel(_sha), dir,
        inspect: (_) async => _info(kOpenDashCertSha256), makeHome: true, idleTimeout: const Duration(milliseconds: 100));
    final steps = await op.run().last;
    final d = steps.firstWhere((s) => s.id == 'download');
    expect(d.state, StepState.failed);
    expect(d.detail, 'The download stopped. Check the internet connection.');
    expect(adb.log, isEmpty);
  });

  test('sending stages the APK, then the release file last', () async {
    final adb = FakeAdb();
    final rel = Release(version: '0.2.2', build: 2050, sha256: _sha, apkUrl: 'https://dl/o.apk', apkName: 'o.apk', notes: 'Notes.', published: '2026-11-30');
    final steps = await sendToScooterOps(adb, _client, rel, dir, inspect: (_) async => _info(kOpenDashCertSha256), manual: true).run().last;
    expect(steps.every((s) => s.state == StepState.done), isTrue);
    const inbox = '/sdcard/Android/data/in.abhijithvijayan.opendash/files/companion/incoming';
    expect(adb.log, [
      'rm -rf $inbox && mkdir -p $inbox',
      'push ${dir.path}/o.apk $inbox/o.apk.part',
      'mv $inbox/o.apk.part $inbox/o.apk',
      'push ${dir.path}/opendash-release.json $inbox/opendash-release.json.part',
      'mv $inbox/opendash-release.json.part $inbox/opendash-release.json',
    ]);
    final json = File('${dir.path}/opendash-release.json').readAsStringSync();
    expect(json, contains('"build":2050'));
    expect(json, contains('"sha256":"$_sha"'));
    expect(json, contains('"apk":"o.apk"'));
    expect(json, contains('"notes":"Notes."'));
  });

  test('a send the rider asked for says so; one the app made by itself does not', () async {
    final rel = Release(version: '0.2.2', build: 2050, sha256: _sha, apkUrl: 'https://dl/o.apk', apkName: 'o.apk');
    await sendToScooterOps(FakeAdb(), _client, rel, dir, inspect: (_) async => _info(kOpenDashCertSha256), manual: true).run().last;
    expect(File('${dir.path}/opendash-release.json').readAsStringSync(), contains('"manual":true'));
    await sendToScooterOps(FakeAdb(), _client, rel, dir, inspect: (_) async => _info(kOpenDashCertSha256), manual: false).run().last;
    expect(File('${dir.path}/opendash-release.json').readAsStringSync(), contains('"manual":false'));
  });

  test('a send that fails the check never reaches the scooter', () async {
    final adb = FakeAdb();
    await sendToScooterOps(adb, _client, _rel('00'), dir, inspect: (_) async => _info(kOpenDashCertSha256), manual: true).run().last;
    expect(adb.log, isEmpty);
  });
}
