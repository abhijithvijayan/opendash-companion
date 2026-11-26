// Films the install flow for the OpenDash launch videos: a phone-sized
// recording of Connect, the scooter screen and an install, frame by frame.
// Lives outside test/, so `flutter test` does not run it. Run:
//   flutter test tool/promo/render_test.dart
// Frames land in build/promo/frames; the OpenDash repo's video tool reads them.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:opendash_companion/adb/adb.dart';
import 'package:opendash_companion/adb/adb_api.g.dart';
import 'package:opendash_companion/flows.dart';
import 'package:opendash_companion/main.dart';
import 'package:opendash_companion/releases/release.dart';
import 'package:opendash_companion/report/app_log.dart';
import 'package:opendash_companion/scooter/ids.dart';
import 'package:opendash_companion/scooter/operations.dart';
import 'package:opendash_companion/state/prefs.dart';
import 'package:opendash_companion/state/providers.dart';
import 'package:opendash_companion/ui/manual_key_screen.dart';
import 'package:opendash_companion/ui/progress_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test/fake_adb.dart';

const fps = 60;
const step = Duration(microseconds: 1000000 ~/ fps);
const phone = Size(1080, 2340);
const dpr = 2.625;
/// The OpenDash the film installs: the version in the OpenDash checkout next
/// to this one, and the build number OpenDash's release gives it.
final version = RegExp(r'^version:\s*([0-9.]+)', multiLine: true)
        .firstMatch(File('../opendash/pubspec.yaml').readAsStringSync())!
        .group(1)!;
final build = int.parse(Process.runSync('scripts/build-number.sh', [version], workingDirectory: '../opendash').stdout.toString().trim());
const out = 'build/promo/frames';

/// A scooter with the stock dashboard and no OpenDash, until the install.
class _Scooter extends FakeAdb {
  _Scooter() : super(answers: {});
  bool installed = false;

  @override
  Future<ConnectOutcome> connect(String host) async {
    await Future<void>.delayed(const Duration(milliseconds: 700));
    return ConnectOutcome.ok;
  }

  @override
  Future<ShellReply> shell(String cmd) async {
    String reply = '';
    if (cmd.startsWith('pm path $kStockPackage')) reply = 'package:/system/app/hmi.apk';
    if (cmd.startsWith('dumpsys package $kOpenDashPackage')) {
      reply = installed ? 'versionCode=$build\nversionName=$version\n' : 'Unable to find package: $kOpenDashPackage\n';
    }
    if (cmd.startsWith('cmd package resolve-activity')) reply = installed ? '$kOpenDashActivity\n' : '$kStockActivity\n';
    if (cmd.startsWith('wm density')) reply = installed ? 'Physical density: 240\nOverride density: 160\n' : 'Physical density: 240\n';
    if (cmd.startsWith('pm list packages -3')) reply = installed ? 'package:$kOpenDashPackage\n' : '';
    return ShellReply(output: reply, exitCode: 0);
  }
}

MockClient _github() => MockClient((req) async {
      if (req.url.host == 'api.github.com') {
        return http.Response(
            jsonEncode({
              'body': 'notes',
              'published_at': '2026-11-25T00:00:00Z',
              'assets': [
                {'name': 'opendash-release.json', 'browser_download_url': 'https://dl/j'},
                {'name': 'opendash-$version.apk', 'browser_download_url': 'https://dl/o.apk'},
              ],
            }),
            200);
      }
      return http.Response(jsonEncode({'version': version, 'build': build, 'apk': 'opendash-$version.apk', 'sha256': 'ab'}), 200);
    });

Future<void> _loadFonts() async {
  Future<void> load(String family, String path) async {
    final bytes = File(path).readAsBytesSync();
    await (FontLoader(family)..addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)))).load();
  }

  await load('Archivo', 'assets/fonts/Archivo-Variable.ttf');
  final root = Platform.environment['FLUTTER_ROOT'];
  final icons = File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (icons.existsSync()) await load('MaterialIcons', icons.path);
}

void main() {
  testWidgets('film the install flow', timeout: Timeout.none, (t) async {
    await _loadFonts();
    t.view.physicalSize = phone;
    t.view.devicePixelRatio = dpr;
    t.view.padding = const FakeViewPadding(top: 24 * dpr, bottom: 16 * dpr);
    t.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(t.view.reset);
    addTearDown(t.platformDispatcher.clearPlatformBrightnessTestValue);

    final tmp = Directory.systemTemp.createTempSync('promo');
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({'ack_version': kAckVersion, 'make_home': true});
    final prefs = Prefs(await SharedPreferences.getInstance());
    final adb = _Scooter();
    final key = GlobalKey();
    await t.pumpWidget(RepaintBoundary(
      key: key,
      child: ProviderScope(overrides: [
        prefsProvider.overrideWithValue(prefs),
        adbProvider.overrideWithValue(adb),
        publicKeyProvider.overrideWith((ref) async => 'QAAAAKEY opendash-companion'),
        httpProvider.overrideWithValue(_github()),
        appLogProvider.overrideWithValue(AppLog(File('${tmp.path}/companion.log'))),
        reportsDirProvider.overrideWithValue(Directory('${tmp.path}/reports')),
      ], child: const CompanionApp()),
    ));
    await t.pump(const Duration(seconds: 1));

    final dir = Directory(out);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    dir.createSync(recursive: true);
    final taps = File('build/promo/taps.json');
    final tapLog = <Map<String, Object>>[];
    var frame = 0;

    Future<void> film(double seconds) async {
      final n = (seconds * fps).round();
      for (var i = 0; i < n; i++) {
        await t.pump(step);
        final render = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await t.runAsync(() async {
          final image = await render.toImage(pixelRatio: dpr);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          File('$out/${frame.toString().padLeft(5, '0')}.png').writeAsBytesSync(png!.buffer.asUint8List());
        });
        frame++;
      }
    }

    /// Shows where a finger lands; the video draws the dot from taps.json.
    Future<void> tap(Finder f) async {
      final c = t.getCenter(f);
      tapLog.add({'frame': frame, 'x': c.dx * dpr, 'y': c.dy * dpr});
      await film(0.25);
      await t.tap(f, warnIfMissed: false);
    }

    await film(0.8);
    const host = '192.168.1.42';
    await t.tap(find.byType(TextField));
    for (var i = 1; i <= host.length; i++) {
      await t.enterText(find.byType(TextField), host.substring(0, i));
      await film(0.09);
    }
    await film(0.4);
    await tap(find.text('Connect'));
    await film(2.2);
    expect(find.text('Your scooter'), findsOneWidget);
    await film(1.2);

    await tap(find.text('Install OpenDash $version'));
    await film(0.9);
    // The dialog's own button would start a real download; the film closes
    // it and runs the same steps, each taking a moment instead.
    final install = find.descendant(of: find.byType(AlertDialog), matching: find.text('Install'));
    tapLog.add({'frame': frame, 'x': t.getCenter(install).dx * dpr, 'y': t.getCenter(install).dy * dpr});
    await film(0.25);
    final nav = t.state<NavigatorState>(find.byType(Navigator).first);
    nav.pop(false);
    final container = ProviderScope.containerOf(t.element(find.byType(CompanionApp)));
    final real = githubInstallOps(adb, _github(),
        Release(version: version, build: build, sha256: 'ab', apkUrl: 'https://dl/o.apk', apkName: 'opendash-$version.apk'), tmp,
        inspect: (_) async => throw UnimplementedError(), makeHome: true);
    final op = Operation(real.title, [
      for (final s in real.steps)
        (
          OpStep(s.id, s.label),
          (OpStep st, void Function() changed) async {
            if (s.id == 'download') {
              for (var p = 0; p <= 20; p++) {
                st.progress = p / 20;
                changed();
                await Future<void>.delayed(const Duration(milliseconds: 60));
              }
            } else {
              await Future<void>.delayed(const Duration(milliseconds: 420));
            }
            if (s.id == 'install') adb.installed = true;
          },
        ),
    ]);
    container.read(operationProvider.notifier).start(op);
    nav.push(MaterialPageRoute<void>(builder: (_) => const ProgressScreen()));
    await film(5.6);
    expect(find.text('All done'), findsOneWidget);
    await film(1.0);
    await tap(find.text('Done'));
    await film(2.0);
    taps.writeAsStringSync(jsonEncode({'fps': fps, 'width': phone.width, 'height': phone.height, 'frames': frame, 'taps': tapLog}));
    // ignore: avoid_print
    print('filmed $frame frames, ${(frame / fps).toStringAsFixed(1)} s');
  });
}
