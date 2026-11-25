import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Raised when the acknowledgement's text changes, so it is shown again.
const kAckVersion = 1;

class Recent {
  const Recent(this.host, {this.build, this.seen = 0});
  final String host;

  /// The OpenDash build last seen on this scooter.
  final int? build;
  final int seen;

  Map<String, Object?> toJson() => {'host': host, 'build': build, 'seen': seen};

  static Recent? fromJson(Object? m) =>
      m is Map && m['host'] is String ? Recent(m['host'] as String, build: m['build'] as int?, seen: m['seen'] as int? ?? 0) : null;
}

class Prefs {
  Prefs(this._p);
  final SharedPreferences _p;

  bool get ackAccepted => (_p.getInt('ack_version') ?? 0) >= kAckVersion;
  Future<void> acceptAck() => _p.setInt('ack_version', kAckVersion);

  List<Recent> get recents {
    try {
      final list = jsonDecode(_p.getString('recents') ?? '[]') as List;
      return [for (final m in list) ?Recent.fromJson(m)];
    } catch (_) {
      return const [];
    }
  }

  Future<void> setRecents(List<Recent> r) => _p.setString('recents', jsonEncode([for (final x in r) x.toJson()]));

  Map<String, String> get _priorModes {
    try {
      final m = jsonDecode(_p.getString('prior_scootermode') ?? '{}') as Map;
      return {for (final e in m.entries) if (e.key is String && e.value is String) e.key as String: e.value as String};
    } catch (_) {
      return {};
    }
  }

  /// The scooter's mode before we provisioned it, to restore on uninstall.
  String? priorScooterMode(String host) => _priorModes[host];
  Future<void> setPriorScooterMode(String host, String mode) =>
      _p.setString('prior_scootermode', jsonEncode({..._priorModes, host: mode}));
  Future<void> clearPriorScooterMode(String host) =>
      _p.setString('prior_scootermode', jsonEncode({..._priorModes}..remove(host)));

  int get skippedOpenDash => _p.getInt('skipped_opendash') ?? 0;
  Future<void> setSkippedOpenDash(int b) => _p.setInt('skipped_opendash', b);
  int get skippedCompanion => _p.getInt('skipped_companion') ?? 0;
  Future<void> setSkippedCompanion(int b) => _p.setInt('skipped_companion', b);

  bool get makeHome => _p.getBool('make_home') ?? true;
  Future<void> setMakeHome(bool v) => _p.setBool('make_home', v);
}
