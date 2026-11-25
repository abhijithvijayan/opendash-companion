import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opendash_companion/report/app_log.dart';
import 'package:opendash_companion/report/report.dart';
import 'package:opendash_companion/scooter/ids.dart';

import 'fake_adb.dart';

void main() {
  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('report'));
  tearDown(() async => tmp.delete(recursive: true));

  group('AppLog', () {
    test('appends timestamped lines and reads them back', () {
      final log = AppLog(File('${tmp.path}/a.log'), now: () => DateTime.utc(2026, 11, 25, 10));
      log.add('connect 10.0.0.2: ok');
      log.add('second');
      expect(log.read(), '2026-11-25T10:00:00.000Z connect 10.0.0.2: ok\n2026-11-25T10:00:00.000Z second\n');
    });

    test('keeps only the newest part when it grows past its cap', () {
      final log = AppLog(File('${tmp.path}/a.log'), maxBytes: 200);
      for (var i = 0; i < 50; i++) {
        log.add('line $i');
      }
      final text = log.read();
      expect(text.length, lessThanOrEqualTo(200));
      expect(text, contains('line 49'));
      expect(text, isNot(contains('line 0\n')));
      expect(text.split('\n').first, contains('line')); // starts on a whole line
    });

    test('a log that was never written reads empty', () {
      expect(AppLog(File('${tmp.path}/none.log')).read(), '');
    });
  });

  group('issueUrl', () {
    test('fills in versions only', () {
      final u = Uri.parse(issueUrl('abhijithvijayan/opendash', companion: 'v0.1.0 · build 42', openDash: '0.3.1', openDashBuild: 30100));
      expect(u.host, 'github.com');
      expect(u.path, '/abhijithvijayan/opendash/issues/new');
      expect(u.queryParameters['body'], 'OpenDash Companion: v0.1.0 · build 42\nOpenDash: 0.3.1 (build 30100)\n\nWhat happened:\n');
    });

    test('without OpenDash on the scooter', () {
      final body = Uri.parse(issueUrl('a/b', companion: 'Development build')).queryParameters['body']!;
      expect(body, 'OpenDash Companion: Development build\n\nWhat happened:\n');
    });
  });

  group('buildLogBundle', () {
    Map<String, String> unzip(File f) {
      final a = ZipDecoder().decodeBytes(f.readAsBytesSync());
      return {for (final e in a.files) e.name: String.fromCharCodes(e.content as List<int>)};
    }

    test("zips this app's log and OpenDash's own logs, not the bus recordings", () async {
      final log = AppLog(File('${tmp.path}/companion.log'))..add('hello');
      final adb = FakeAdb()
        ..files['$kOpenDashLogDir/opendash.jsonl'] = '{"e":1}'
        ..files['$kOpenDashLogDir/opendash.1.jsonl'] = '{"e":0}';
      final remote = [
        for (final n in ['opendash.jsonl', 'opendash.1.jsonl', 'bus-1.jsonl', 'raw-2.jsonl']) ScooterLog(n, 10),
      ];
      final b = await buildLogBundle(log, Directory('${tmp.path}/reports'), adb: adb, remote: remote, summary: 'OpenDash: 0.3.1');
      expect(b.pulled, 2);
      final z = unzip(b.zip);
      expect(z.keys, unorderedEquals(['companion.log', 'summary.txt', 'opendash/opendash.jsonl', 'opendash/opendash.1.jsonl']));
      expect(z['companion.log'], contains('hello'));
      expect(z['summary.txt'], 'OpenDash: 0.3.1\n');
      expect(adb.log.where((c) => c.startsWith('pull')), hasLength(2));
    });

    test('still shares this app\'s log when the scooter has none, or a pull fails', () async {
      final log = AppLog(File('${tmp.path}/companion.log'))..add('hello');
      final adb = FakeAdb(); // listed but the pull fails
      final b = await buildLogBundle(log, Directory('${tmp.path}/reports'), adb: adb, remote: const [ScooterLog('opendash.jsonl', 10)]);
      expect(b.pulled, 0);
      expect(b.failed, 1);
      expect(unzip(b.zip).keys, ['companion.log']);
    });

    test("this app's log can be left out", () async {
      final adb = FakeAdb()..files['$kOpenDashLogDir/opendash.jsonl'] = 'x';
      final b = await buildLogBundle(
        AppLog(File('${tmp.path}/c.log')),
        Directory('${tmp.path}/reports'),
        adb: adb,
        remote: const [ScooterLog('opendash.jsonl', 1)],
        kinds: {LogKind.openDash},
      );
      expect(unzipNames(b.zip), ['opendash/opendash.jsonl']);
    });

    test('without a scooter', () async {
      final b = await buildLogBundle(AppLog(File('${tmp.path}/companion.log')), Directory('${tmp.path}/reports'));
      expect(unzip(b.zip).keys, ['companion.log']);
    });

    test('an earlier bundle is cleared away', () async {
      final dir = Directory('${tmp.path}/reports');
      final log = AppLog(File('${tmp.path}/companion.log'));
      final first = await buildLogBundle(log, dir);
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      final second = await buildLogBundle(log, dir);
      expect(first.zip.existsSync(), isFalse);
      expect(second.zip.existsSync(), isTrue);
    });
  });

  group('scooter logs', () {
    const listing = '''total 72
-rw-rw---- 1 10224 1078   576 2026-11-25 17:32 burst-20261125T120245-10325-command_failed.jsonl
-rw-rw---- 1 10224 1078 38211 2026-11-25 17:33 bus-20261125T120235-273.jsonl
-rw-rw---- 1 10224 1078 22271 2026-11-25 17:33 opendash.jsonl
-rw-rw---- 1 10224 1078 90000 2026-11-25 17:30 opendash.1.jsonl
-rw-rw---- 1 10224 1078 5000000 2026-11-25 17:30 raw-1.jsonl
-rw-rw---- 1 10224 1078    10 2026-11-25 17:30 notes.txt
drwxrws--- 2 10224 1078  4096 2026-11-25 17:30 old
''';

    test('parses ls -ln into files of each kind, ignoring the rest', () {
      final logs = parseScooterLogs(listing);
      expect(logs.map((l) => l.name), [
        'burst-20261125T120245-10325-command_failed.jsonl',
        'bus-20261125T120235-273.jsonl',
        'opendash.jsonl',
        'opendash.1.jsonl',
        'raw-1.jsonl',
      ]);
      expect(logs.firstWhere((l) => l.name == 'opendash.jsonl').bytes, 22271);
      expect(logs.where((l) => l.kind == LogKind.openDash), hasLength(2));
      expect(logs.where((l) => l.kind == LogKind.canBus), hasLength(3));
    });

    test('an empty or missing folder lists nothing', () {
      expect(parseScooterLogs(''), isEmpty);
      expect(parseScooterLogs('ls: /sdcard/x: No such file or directory'), isEmpty);
    });

    test('sizes read for people', () {
      expect(formatBytes(512), '512 B');
      expect(formatBytes(22271), '22 KB');
      expect(formatBytes(5000000), '4.8 MB');
      expect(formatBytes(0), '0 B');
    });

    test('only the chosen kinds are pulled', () async {
      final log = AppLog(File('${tmp.path}/companion.log'))..add('hello');
      final remote = parseScooterLogs(listing);
      final adb = FakeAdb();
      for (final l in remote) {
        adb.files['$kOpenDashLogDir/${l.name}'] = l.name;
      }
      final b = await buildLogBundle(log, Directory('${tmp.path}/reports'), adb: adb, remote: remote, kinds: {LogKind.canBus});
      expect(
        unzipNames(b.zip),
        unorderedEquals(['can/burst-20261125T120245-10325-command_failed.jsonl', 'can/bus-20261125T120235-273.jsonl', 'can/raw-1.jsonl']),
      );
      expect(b.pulled, 3);
    });

    test('progress counts each file pulled', () async {
      final remote = parseScooterLogs(listing);
      final adb = FakeAdb();
      for (final l in remote) {
        adb.files['$kOpenDashLogDir/${l.name}'] = 'x';
      }
      final seen = <String>[];
      await buildLogBundle(
        AppLog(File('${tmp.path}/c.log')),
        Directory('${tmp.path}/reports'),
        adb: adb,
        remote: remote,
        kinds: LogKind.values.toSet(),
        onProgress: (done, total) => seen.add('$done/$total'),
      );
      expect(seen, ['0/5', '1/5', '2/5', '3/5', '4/5', '5/5']);
    });
  });
}

List<String> unzipNames(File f) => ZipDecoder().decodeBytes(f.readAsBytesSync()).files.map((e) => e.name).toList();
