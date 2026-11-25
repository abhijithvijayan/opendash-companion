import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../adb/adb.dart';
import '../adb/adb_api.g.dart';
import '../flows.dart';
import '../releases/release.dart';
import '../scooter/operations.dart';
import '../report/app_log.dart';
import 'prefs.dart';

const kOpenDashRepo = 'abhijithvijayan/opendash';
const kCompanionRepo = 'abhijithvijayan/opendash-companion';

/// Set by scripts/release.sh. 0 on a dev build, which never offers itself an update.
const kCompanionBuild = int.fromEnvironment('COMPANION_BUILD');
const kCompanionVersion = String.fromEnvironment('COMPANION_VERSION');
const kCompanionCertSha256 = String.fromEnvironment('COMPANION_CERT_SHA256');

final prefsProvider = Provider<Prefs>((ref) => throw UnimplementedError('overridden in main'));
final adbProvider = Provider<Adb>((ref) => PigeonAdb());
final inspectProvider = Provider<Inspect>((ref) => AdbHostApi().inspectApk);

/// The app's cache, which the installer's FileProvider shares from.
final downloadDirProvider = Provider<Directory>((ref) => Directory('${Directory.systemTemp.path}/downloads'));
final reportsDirProvider = Provider<Directory>((ref) => Directory('${Directory.systemTemp.path}/reports'));

/// Overridden in main with one in the app's files directory.
final appLogProvider = Provider<AppLog>((ref) => AppLog(File('${Directory.systemTemp.path}/logs/companion.log')));

final httpProvider = Provider<http.Client>((ref) {
  final c = http.Client();
  ref.onDispose(c.close);
  return c;
});

/// What a rider types, as the host to dial: `adb connect` taught them to add
/// `:5555`, and IPv6 comes bracketed when it carries a port.
String normalizeHost(String raw) {
  var h = raw.trim();
  final bracketed = RegExp(r'^\[(.+)\](?::\d+)?$').firstMatch(h);
  if (bracketed != null) return bracketed.group(1)!;
  if (':'.allMatches(h).length == 1) h = h.substring(0, h.indexOf(':'));
  return h;
}

class AckNotifier extends Notifier<bool> {
  @override
  bool build() => ref.read(prefsProvider).ackAccepted;

  Future<void> accept() async {
    await ref.read(prefsProvider).acceptAck();
    state = true;
  }
}

final ackProvider = NotifierProvider<AckNotifier, bool>(AckNotifier.new);

class RecentsNotifier extends Notifier<List<Recent>> {
  @override
  List<Recent> build() => ref.read(prefsProvider).recents;

  Future<void> remember(String host, {int? build}) async {
    final old = state.where((r) => r.host == host).firstOrNull;
    final next = [
      Recent(host, build: build ?? old?.build, seen: DateTime.now().millisecondsSinceEpoch),
      ...state.where((r) => r.host != host),
    ].take(5).toList();
    state = next;
    await ref.read(prefsProvider).setRecents(next);
  }

  Future<void> forget(String host) async {
    state = state.where((r) => r.host != host).toList();
    await ref.read(prefsProvider).setRecents(state);
  }
}

final recentsProvider = NotifierProvider<RecentsNotifier, List<Recent>>(RecentsNotifier.new);

class ConnectionState {
  const ConnectionState({this.host, this.outcome, this.status, this.busy = false, this.error});
  final String? host;
  final ConnectOutcome? outcome;
  final ScooterStatus? status;
  final bool busy;
  final String? error;

  bool get connected => outcome == ConnectOutcome.ok;
}

class ConnectionNotifier extends Notifier<ConnectionState> {
  @override
  ConnectionState build() => const ConnectionState();

  Adb get _adb => ref.read(adbProvider);

  Future<void> connect(String host) async {
    host = normalizeHost(host);
    state = ConnectionState(host: host, busy: true);
    try {
      final outcome = await _adb.connect(host);
      _log('connect $host: ${outcome.name}');
      state = ConnectionState(host: host, outcome: outcome, busy: outcome == ConnectOutcome.ok);
      if (outcome == ConnectOutcome.ok) await refresh();
    } catch (e) {
      _log('connect $host failed: $e');
      state = ConnectionState(host: host, outcome: ConnectOutcome.unreachable, error: '$e');
    }
  }

  Future<void> refresh() async {
    final host = state.host;
    if (host == null || !state.connected) return;
    state = ConnectionState(host: host, outcome: state.outcome, status: state.status, busy: true);
    try {
      final status = await readStatus(_adb);
      _log(describeStatus(status));
      state = ConnectionState(host: host, outcome: ConnectOutcome.ok, status: status);
      await ref.read(recentsProvider.notifier).remember(host, build: status.openDashBuild ?? 0);
    } on AdbFailure catch (e) {
      _log('status read failed: ${e.message}');
      state = ConnectionState(host: host, outcome: ConnectOutcome.unreachable, error: e.message);
    }
  }

  void _log(String line) => ref.read(appLogProvider).add(line);

  Future<void> disconnect() async {
    _log('disconnect');
    await _adb.disconnect();
    state = const ConnectionState();
  }
}

final connectionProvider = NotifierProvider<ConnectionNotifier, ConnectionState>(ConnectionNotifier.new);

/// The OpenDash build on the scooter: read now when connected, else the one
/// last seen on the most recent scooter (0 = seen without OpenDash).
final knownBuildProvider = Provider<int?>((ref) {
  final conn = ref.watch(connectionProvider);
  if (conn.status != null) return conn.status!.openDashBuild;
  final recents = ref.watch(recentsProvider);
  final b = recents.isEmpty ? null : recents.first.build;
  return b == 0 ? null : b;
});

final openDashReleaseProvider = FutureProvider<ReleaseCheck>(
    (ref) => fetchLatest(ref.watch(httpProvider), repo: kOpenDashRepo, jsonAsset: 'opendash-release.json'));

final companionReleaseProvider = FutureProvider<ReleaseCheck>(
    (ref) => fetchLatest(ref.watch(httpProvider), repo: kCompanionRepo, jsonAsset: 'companion-release.json'));

class SkipNotifier extends Notifier<int> {
  SkipNotifier(this.companion);
  final bool companion;

  @override
  int build() => companion ? ref.read(prefsProvider).skippedCompanion : ref.read(prefsProvider).skippedOpenDash;

  Future<void> skip(int b) async {
    state = b;
    final p = ref.read(prefsProvider);
    await (companion ? p.setSkippedCompanion(b) : p.setSkippedOpenDash(b));
  }
}

final skippedOpenDashProvider = NotifierProvider<SkipNotifier, int>(() => SkipNotifier(false));
final skippedCompanionProvider = NotifierProvider<SkipNotifier, int>(() => SkipNotifier(true));

class OperationState {
  const OperationState(this.title, this.steps, {required this.running, this.background = false});
  final String title;
  final List<OpStep> steps;
  final bool running;

  /// Started by the app itself (an automatic send): shown inline, not on
  /// the progress screen.
  final bool background;

  bool get failed => steps.any((s) => s.state == StepState.failed);
}

class OperationNotifier extends Notifier<OperationState?> {
  @override
  OperationState? build() => null;

  bool get running => state?.running ?? false;

  Future<void> start(Operation op, {bool background = false}) async {
    if (running) return;
    state = OperationState(op.title, op.steps, running: true, background: background);
    await for (final steps in op.run()) {
      state = OperationState(op.title, steps, running: true, background: background);
    }
    state = OperationState(op.title, state!.steps, running: false, background: background);
    ref.read(appLogProvider).add(describeOperation(op.title, state!.steps, background: background));
    await ref.read(connectionProvider.notifier).refresh();
  }

  void clear() {
    if (!running) state = null;
  }
}

final operationProvider = NotifierProvider<OperationNotifier, OperationState?>(OperationNotifier.new);

final actionsEnabledProvider = Provider<bool>((ref) {
  final conn = ref.watch(connectionProvider);
  final op = ref.watch(operationProvider);
  return ref.watch(ackProvider) && conn.connected && !conn.busy && !(op?.running ?? false);
});

/// One line for the app's log: what the scooter looked like.
String describeStatus(ScooterStatus s) {
  if (!s.isOlaHeadUnit) return 'status: not an Ola head unit';
  final od = s.openDashInstalled ? 'OpenDash ${s.openDashVersion} (build ${s.openDashBuild})' : 'OpenDash not installed';
  return 'status: $od, home ${s.openDashIsHome ? 'OpenDash' : 'stock'}, density ${s.density}, '
      '${s.otherApps.where((a) => !a.isOpenDash).length} other apps';
}

/// The app's log entry for a finished operation: every step and how it went.
String describeOperation(String title, List<OpStep> steps, {bool background = false}) => [
      '${background ? 'background ' : ''}operation "$title":',
      for (final st in steps) '  ${st.state.name.padRight(7)} ${st.label}${st.detail == null ? '' : ': ${st.detail}'}',
    ].join('\n');
