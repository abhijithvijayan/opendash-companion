import 'package:flutter/services.dart';

import '../scooter/ids.dart';
import 'adb_api.g.dart';

enum ConnectOutcome { ok, unauthorized, unreachable }

enum ProvisionOutcome { ok, unimplemented, unreachable, failed }

/// The connection broke or was never there; [message] is for the rider.
class AdbFailure implements Exception {
  const AdbFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The installer refused the APK; [raw] is its text (`Failure [INSTALL_…]`).
class InstallFailure implements Exception {
  const InstallFailure(this.raw);
  final String raw;
  @override
  String toString() => raw;
}

abstract class Adb {
  Future<ConnectOutcome> connect(String host);
  Future<ProvisionOutcome> provision(String host);
  Future<ShellReply> shell(String cmd);
  Future<void> install(String apkPath, List<String> options, {void Function(int sent, int total)? onProgress});
  Future<void> push(String localPath, String remotePath, {void Function(int sent, int total)? onProgress});
  Future<void> pull(String remotePath, String localPath);
  Future<void> disconnect();
}

class PigeonAdb implements Adb, AdbEvents {
  PigeonAdb({AdbHostApi? api}) : api = api ?? AdbHostApi() {
    AdbEvents.setUp(this);
  }

  final AdbHostApi api;
  void Function(int sent, int total)? _onProgress;

  @override
  Future<ConnectOutcome> connect(String host) async {
    final reply = await api.connect(host, kAdbPort);
    return switch (reply.outcome) {
      'ok' => ConnectOutcome.ok,
      'unauthorized' => ConnectOutcome.unauthorized,
      _ => ConnectOutcome.unreachable,
    };
  }

  @override
  Future<ProvisionOutcome> provision(String host) async {
    final reply = await api.provision(host);
    return switch (reply.outcome) {
      'ok' => ProvisionOutcome.ok,
      'unimplemented' => ProvisionOutcome.unimplemented,
      'unreachable' => ProvisionOutcome.unreachable,
      _ => ProvisionOutcome.failed,
    };
  }

  @override
  Future<ShellReply> shell(String cmd) async {
    try {
      return await api.shell(cmd);
    } on PlatformException catch (e) {
      throw _failure(e);
    }
  }

  @override
  Future<void> install(String apkPath, List<String> options, {void Function(int sent, int total)? onProgress}) async {
    _onProgress = onProgress;
    try {
      await api.install(apkPath, options);
    } on PlatformException catch (e) {
      if (e.code == 'install_failed') throw InstallFailure(e.message ?? '');
      throw _failure(e);
    } finally {
      _onProgress = null;
    }
  }

  @override
  Future<void> push(String localPath, String remotePath, {void Function(int sent, int total)? onProgress}) async {
    _onProgress = onProgress;
    try {
      await api.push(localPath, remotePath);
    } on PlatformException catch (e) {
      throw _failure(e);
    } finally {
      _onProgress = null;
    }
  }

  @override
  Future<void> pull(String remotePath, String localPath) async {
    try {
      await api.pull(remotePath, localPath);
    } on PlatformException catch (e) {
      throw _failure(e);
    }
  }

  @override
  Future<void> disconnect() => api.disconnect();

  @override
  void installProgress(int sent, int total) => _onProgress?.call(sent, total);

  AdbFailure _failure(PlatformException e) => e.code == 'not_connected'
      ? const AdbFailure('Not connected to the scooter.')
      : const AdbFailure('Lost the connection to the scooter.');
}
