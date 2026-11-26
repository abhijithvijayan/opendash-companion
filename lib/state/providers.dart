import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../adb/adb.dart';
import '../adb/adb_api.g.dart';
import '../discovery/identity.dart';
import '../flows.dart';
import '../releases/release.dart';
import '../scooter/operations.dart';
import '../report/app_log.dart';
import '../scooter/ids.dart';
import 'prefs.dart';

export '../scooter/ids.dart' show kOpenDashRepo, kCompanionRepo, kCompanionBuild, kCompanionVersion;

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

  Future<void> remember(String host, {String? mac, int? build}) async {
    // Collapse onto the same scooter: by identity (MAC) when known, else by a
    // shared address. One physical scooter stays one entry across its addresses.
    final old = state
        .where((r) => (mac != null && r.mac == mac) || r.host == host || r.addresses.contains(host))
        .firstOrNull;
    final addresses = <String>{...?old?.addresses, host}.toList();
    final display = addresses.firstWhere((a) => !a.contains(':'), orElse: () => addresses.first);
    final merged = Recent(
      display,
      mac: mac ?? old?.mac,
      addresses: addresses,
      build: build ?? old?.build,
      seen: DateTime.now().millisecondsSinceEpoch,
    );
    final next = [merged, ...state.where((r) => r != old)].take(5).toList();
    state = next;
    await ref.read(prefsProvider).setRecents(next);
  }

  Future<void> forget(String host) async {
    state = state.where((r) => r.host != host && !r.addresses.contains(host)).toList();
    await ref.read(prefsProvider).setRecents(state);
  }
}

final recentsProvider = NotifierProvider<RecentsNotifier, List<Recent>>(RecentsNotifier.new);

class ConnectionState {
  const ConnectionState({this.host, this.outcome, this.status, this.busy = false, this.error, this.provision});
  final String? host;
  final ConnectOutcome? outcome;
  final ScooterStatus? status;
  final bool busy;
  final String? error;

  /// Result of auto-provisioning the adb key; null when it wasn't attempted.
  final ProvisionOutcome? provision;

  bool get connected => outcome == ConnectOutcome.ok;
}

class ConnectionNotifier extends Notifier<ConnectionState> {
  @override
  ConnectionState build() => const ConnectionState();

  Adb get _adb => ref.read(adbProvider);

  /// Identity of the scooter being connected (its MAC), threaded from
  /// discovery/recents so remembering and prior-mode survive the address change.
  String? _mac;

  /// Device key for storage: the MAC when known, else the dialed host. Uninstall
  /// reads the prior mode under this same key.
  String? deviceKey(String? host) => _mac ?? host;

  Future<void> connect(String host, {String? mac}) async {
    host = normalizeHost(host);
    _mac = mac ?? macFromLinkLocal(host);
    state = ConnectionState(host: host, busy: true);
    try {
      var outcome = await _adb.connect(host);
      _log('connect $host: ${outcome.name}');
      if (outcome == ConnectOutcome.unauthorized) {
        final (prov, prior) = await _adb.provision(host);
        _log('provision $host: ${prov.name}');
        if (prov == ProvisionOutcome.ok) {
          if (prior != null && prior.isNotEmpty && prior != 'mfg') {
            await ref.read(prefsProvider).setPriorScooterMode(_mac ?? host, prior);
          }
          outcome = await _adb.connect(host);
          _log('reconnect $host: ${outcome.name}');
        }
        if (outcome != ConnectOutcome.ok) {
          state = ConnectionState(host: host, outcome: ConnectOutcome.unauthorized, provision: prov);
          return;
        }
      }
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
      await ref.read(recentsProvider.notifier).remember(host, mac: _mac, build: status.openDashBuild ?? 0);
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
  const OperationState(this.title, this.steps, {required this.running, this.background = false, this.manual});
  final String title;

  /// [Operation.manual]: offered once it has failed.
  final ManualRoute? manual;
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
    state = OperationState(op.title, op.steps, running: true, background: background, manual: op.manual);
    await for (final steps in op.run()) {
      state = OperationState(op.title, steps, running: true, background: background, manual: op.manual);
    }
    state = OperationState(op.title, state!.steps, running: false, background: background, manual: op.manual);
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
