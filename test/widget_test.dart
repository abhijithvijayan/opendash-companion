import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:opendash_companion/adb/adb_api.g.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:opendash_companion/adb/adb.dart';
import 'package:opendash_companion/main.dart';
import 'package:opendash_companion/state/prefs.dart';
import 'package:opendash_companion/ui/manual_key_screen.dart';
import 'package:opendash_companion/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:archive/archive_io.dart';
import 'package:opendash_companion/report/app_log.dart';
import 'package:opendash_companion/scooter/ids.dart';
import 'package:opendash_companion/ui/actions.dart';
import 'package:opendash_companion/ui/report_actions.dart';
import 'fake_adb.dart';

class _SecondTime extends FakeAdb {
  _SecondTime() : super(answers: {'pm path com.olaelectric.hmiclient': 'package:/x.apk'}) {
    // unreachable → the copy-key ManualKeyScreen (with "Try again"), not the sealed dead-end.
    provisionOutcome = ProvisionOutcome.unreachable;
  }
  int calls = 0;
  @override
  Future<ConnectOutcome> connect(String host) async => ++calls == 1 ? ConnectOutcome.unauthorized : ConnectOutcome.ok;
}

const _withOpenDash = {
  'pm path com.olaelectric.hmiclient': 'package:/x.apk',
  'dumpsys package in.abhijithvijayan.opendash': 'versionCode=2041\nversionName=0.2.1\n',
};

class _Flaky extends FakeAdb {
  _Flaky() : super(answers: _withOpenDash);
  bool broken = false;
  int disconnects = 0;
  @override
  Future<ShellReply> shell(String cmd) async {
    if (broken) throw const AdbFailure('Lost the connection to the scooter.');
    return super.shell(cmd);
  }

  @override
  Future<void> disconnect() async => disconnects++;
}

MockClient _releases(int build, String version) => MockClient((req) async {
      if (req.url.host == 'api.github.com') {
        return http.Response(
            jsonEncode({
              'body': 'notes',
              'published_at': '2026-11-30T00:00:00Z',
              'assets': [
                {'name': 'opendash-release.json', 'browser_download_url': 'https://dl/j'},
                {'name': 'o.apk', 'browser_download_url': 'https://dl/o.apk'},
              ],
            }),
            200);
      }
      return http.Response(jsonEncode({'version': version, 'build': build, 'apk': 'o.apk', 'sha256': 'ab'}), 200);
    });

Future<void> pumpApp(WidgetTester t,
    {Map<String, Object> prefs = const {},
    Adb? adb,
    http.Client? client,
    AdbHostApi? hostApi,
    Directory? dir,
    Future<bool> Function(Uri)? opener}) async {
  final tmp = dir ?? Directory.systemTemp.createTempSync('companion-test');
  SharedPreferences.setMockInitialValues(prefs);
  final p = Prefs(await SharedPreferences.getInstance());
  await t.pumpWidget(ProviderScope(overrides: [
    prefsProvider.overrideWithValue(p),
    adbProvider.overrideWithValue(adb ?? FakeAdb()),
    publicKeyProvider.overrideWith((ref) async => 'QAAAAKEY opendash-companion'),
    httpProvider.overrideWithValue(client ?? MockClient((_) async => http.Response('', 404))),
    appLogProvider.overrideWithValue(AppLog(File('${tmp.path}/companion.log'))),
    reportsDirProvider.overrideWithValue(Directory('${tmp.path}/reports')),
    if (hostApi != null) hostApiProvider.overrideWithValue(hostApi),
    if (opener != null) urlOpenerProvider.overrideWithValue(opener),
  ], child: const CompanionApp()));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('first launch shows the acknowledgement; accepting it opens Connect', (t) async {
    await pumpApp(t);
    expect(find.text('Before you start'), findsOneWidget);
    expect(find.text('Connect to your scooter'), findsNothing);
    final button = find.text('I understand');
    await t.scrollUntilVisible(button, 200);
    await t.tap(button);
    await t.pumpAndSettle();
    expect(find.text('Connect to your scooter'), findsNothing, reason: 'needs the box ticked first');
    await t.scrollUntilVisible(find.byType(CheckboxListTile), -200);
    await t.tap(find.byType(CheckboxListTile));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(button, 200);
    await t.tap(button);
    await t.pumpAndSettle();
    expect(find.text('Connect to your scooter'), findsOneWidget);
  });

  testWidgets('an accepted acknowledgement goes straight to Connect', (t) async {
    await pumpApp(t, prefs: {'ack_version': kAckVersion});
    expect(find.text('Connect to your scooter'), findsOneWidget);
  });

  testWidgets('accepted on the second try: lands on the scooter screen, nothing blank', (t) async {
    await pumpApp(t, prefs: {'ack_version': kAckVersion}, adb: _SecondTime());
    await t.enterText(find.byType(TextField), '10.1.1.5');
    await t.tap(find.text('Connect'));
    await t.pumpAndSettle();
    expect(find.text('Set up access'), findsOneWidget);
    await t.tap(find.text('Try again'));
    await t.pumpAndSettle();
    expect(find.text('Your scooter'), findsOneWidget);
    expect(find.text('Set up access'), findsNothing);
    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.text('Connect to your scooter'), findsOneWidget);
  });

  testWidgets('Reconnect after a lost connection lands on a working scooter screen', (t) async {
    final adb = _Flaky();
    await pumpApp(t, prefs: {'ack_version': kAckVersion}, adb: adb);
    await t.enterText(find.byType(TextField), '10.1.1.5');
    await t.tap(find.text('Connect'));
    await t.pumpAndSettle();
    expect(find.text('Start OpenDash'), findsOneWidget);
    adb.broken = true;
    await t.tap(find.byTooltip('Refresh'));
    await t.pumpAndSettle();
    expect(find.text('Lost the connection to the scooter'), findsOneWidget);
    adb.broken = false;
    await t.tap(find.text('Reconnect'));
    await t.pumpAndSettle();
    expect(adb.disconnects, 0);
    expect(find.text('Start OpenDash'), findsOneWidget);
  });

  testWidgets('a skipped version can still be installed from the actions', (t) async {
    await pumpApp(t, prefs: {'ack_version': kAckVersion, 'skipped_opendash': 2050}, adb: FakeAdb(answers: _withOpenDash), client: _releases(2050, '0.2.2'));
    await t.enterText(find.byType(TextField), '10.1.1.5');
    await t.tap(find.text('Connect'));
    await t.pumpAndSettle();
    expect(find.text('OpenDash 0.2.2 is out'), findsNothing);
    await t.scrollUntilVisible(find.text('Update to 0.2.2'), 200);
    expect(find.text('Update to 0.2.2'), findsOneWidget);
  });

  testWidgets('Restart OpenDash is offered only when OpenDash is installed', (t) async {
    await pumpApp(t, prefs: {'ack_version': kAckVersion}, adb: FakeAdb(answers: _withOpenDash));
    await t.enterText(find.byType(TextField), '10.1.1.5');
    await t.tap(find.text('Connect'));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.text('Restart OpenDash'), 200);
    expect(find.text('Restart OpenDash'), findsOneWidget);
  });

  testWidgets('Restart OpenDash is absent when OpenDash is not installed', (t) async {
    await pumpApp(t, prefs: {'ack_version': kAckVersion});
    await t.enterText(find.byType(TextField), '10.1.1.5');
    await t.tap(find.text('Connect'));
    await t.pumpAndSettle();
    expect(find.text('Your scooter'), findsOneWidget);
    expect(find.text('Restart OpenDash'), findsNothing);
  });

  testWidgets('Send to scooter is offered when OpenDash takes updates from the phone', (t) async {
    final adb = FakeAdb(answers: {
      ..._withOpenDash,
      'cat /sdcard/Android/data/in.abhijithvijayan.opendash/files/companion/accepts.json': '{"v":1,"auto":false,"installed":2041,"skipped":0}',
    });
    await pumpApp(t, prefs: {'ack_version': kAckVersion}, adb: adb, client: _releases(2050, '0.2.2'));
    await t.enterText(find.byType(TextField), '10.1.1.5');
    await t.tap(find.text('Connect'));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.text('Send to scooter'), 200);
    expect(find.text('Send to scooter'), findsOneWidget);
  });

  testWidgets('an update already sent says so instead of offering to send again', (t) async {
    final adb = FakeAdb(answers: {
      ..._withOpenDash,
      'cat /sdcard/Android/data/in.abhijithvijayan.opendash/files/companion/accepts.json': '{"v":1,"auto":false,"installed":2041,"skipped":0}',
      'cat /sdcard/Android/data/in.abhijithvijayan.opendash/files/companion/incoming/opendash-release.json': '{"build":2050}',
    });
    await pumpApp(t, prefs: {'ack_version': kAckVersion}, adb: adb, client: _releases(2050, '0.2.2'));
    await t.enterText(find.byType(TextField), '10.1.1.5');
    await t.tap(find.text('Connect'));
    await t.pumpAndSettle();
    expect(find.text('OpenDash 0.2.2 is waiting on the dashboard'), findsOneWidget);
    expect(find.text('Send to scooter'), findsNothing);
    expect(find.text('OpenDash 0.2.2 is out'), findsNothing, reason: 'one card for one update');
  });
  testWidgets('Share logs asks which logs, then zips the chosen ones and opens the share sheet', (t) async {
    final dir = Directory.systemTemp.createTempSync('companion-test');
    final share = _Share();
    final adb = FakeAdb(answers: {
      ..._withOpenDash,
      'ls -ln $kOpenDashLogDir': '-rw-rw---- 1 1 1 22271 2026-11-25 17:33 opendash.jsonl\n'
          '-rw-rw---- 1 1 1 5000000 2026-11-25 17:33 raw-1.jsonl\n'
          '-rw-rw---- 1 1 1 540 2026-11-25 17:33 bus-1.jsonl\n',
    })
      ..files['$kOpenDashLogDir/opendash.jsonl'] = '{"e":"boot"}'
      ..files['$kOpenDashLogDir/bus-1.jsonl'] = '{"f":1}'
      ..files['$kOpenDashLogDir/raw-1.jsonl'] = '{"f":2}';
    await pumpApp(t, prefs: {'ack_version': kAckVersion}, adb: adb, hostApi: share, dir: dir);
    await t.enterText(find.byType(TextField), '10.1.1.5');
    await t.tap(find.text('Connect'));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.byKey(const ValueKey('share-logs')), 200);
    await t.ensureVisible(find.byKey(const ValueKey('share-logs')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('share-logs')));
    await t.pumpAndSettle();

    // The chooser: this app's and OpenDash's logs ticked, the CAN recordings not.
    expect(find.text('Which logs?'), findsOneWidget);
    expect(t.widget<CheckboxListTile>(find.byKey(const ValueKey('log-companion'))).value, isTrue);
    expect(t.widget<CheckboxListTile>(find.byKey(const ValueKey('log-openDash'))).value, isTrue);
    expect(t.widget<CheckboxListTile>(find.byKey(const ValueKey('log-canBus'))).value, isFalse);
    expect(find.textContaining('4.8 MB'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('log-canBus')));
    await t.tap(find.byKey(const ValueKey('log-companion')));
    await t.pumpAndSettle();

    await t.tap(find.byKey(const ValueKey('log-share')));
    await _untilShared(t, share);
    expect(share.shared, isNotNull);
    final names = ZipDecoder().decodeBytes(File(share.shared!).readAsBytesSync()).files.map((f) => f.name).toList();
    expect(names, unorderedEquals(['summary.txt', 'opendash/opendash.jsonl', 'can/bus-1.jsonl', 'can/raw-1.jsonl']));
    expect(find.textContaining('Collecting logs'), findsNothing);
  });

  testWidgets("Share logs without OpenDash on the scooter shares this app's log straight away", (t) async {
    final dir = Directory.systemTemp.createTempSync('companion-test');
    final share = _Share();
    await pumpApp(t, prefs: {'ack_version': kAckVersion}, adb: FakeAdb(answers: {'pm path com.olaelectric.hmiclient': 'package:/x.apk'}), hostApi: share, dir: dir);
    await t.enterText(find.byType(TextField), '10.1.1.5');
    await t.tap(find.text('Connect'));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.byKey(const ValueKey('share-logs')), 200);
    await t.ensureVisible(find.byKey(const ValueKey('share-logs')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('share-logs')));
    await _untilShared(t, share);
    expect(find.text('Which logs?'), findsNothing);
    final names = ZipDecoder().decodeBytes(File(share.shared!).readAsBytesSync()).files.map((f) => f.name).toList();
    expect(names, unorderedEquals(['companion.log', 'summary.txt']));
  });

  testWidgets('Report a problem opens a filled-in issue on the repository the rider picks', (t) async {
    final opened = <Uri>[];
    await pumpApp(
      t,
      prefs: {'ack_version': kAckVersion},
      adb: FakeAdb(answers: _withOpenDash),
      opener: (u) async {
        opened.add(u);
        return true;
      },
    );
    await t.enterText(find.byType(TextField), '10.1.1.5');
    await t.tap(find.text('Connect'));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.byKey(const ValueKey('report-problem')), 200);
    await t.ensureVisible(find.byKey(const ValueKey('report-problem')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('report-problem')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('report-opendash')));
    await t.pumpAndSettle();
    final u = opened.single;
    expect(u.toString(), startsWith('https://github.com/abhijithvijayan/opendash/issues/new?body='));
    expect(u.queryParameters['body'], contains('OpenDash: 0.2.1 (build 2041)'));
  });
}

/// Frames for the dialogs, real time for the file work, until the share sheet opens.
Future<void> _untilShared(WidgetTester t, _Share share) async {
  for (var i = 0; i < 100 && share.shared == null; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await t.pump(const Duration(milliseconds: 50));
  }
  await t.pumpAndSettle();
}

class _Share extends AdbHostApi {
  String? shared;
  @override
  Future<void> shareFile(String path, String mimeType, String subject) async => shared = path;
}
