import 'dart:io';

import 'package:opendash_companion/adb/adb.dart';
import 'package:opendash_companion/adb/adb_api.g.dart';

/// Records every command; answers a shell line from the first matching prefix.
class FakeAdb implements Adb {
  FakeAdb({Map<String, String>? answers, this.installError}) : answers = answers ?? {};

  final Map<String, String> answers;
  final Object? installError;
  final List<String> log = [];
  ProvisionOutcome provisionOutcome = ProvisionOutcome.ok;
  String? provisionDetail;
  int provisionCalls = 0;
  Object? setModeError;

  @override
  Future<ConnectOutcome> connect(String host) async => ConnectOutcome.ok;

  @override
  Future<(ProvisionOutcome, String?)> provision(String host) async {
    provisionCalls++;
    return (provisionOutcome, provisionDetail);
  }

  @override
  Future<ProvisionOutcome> setScooterMode(String host, String mode) async {
    log.add('setScooterMode $host $mode');
    if (setModeError != null) throw setModeError!;
    return ProvisionOutcome.ok;
  }

  @override
  Future<ShellReply> shell(String cmd) async {
    log.add(cmd);
    for (final e in answers.entries) {
      if (cmd.startsWith(e.key)) return ShellReply(output: e.value, exitCode: 0);
    }
    return ShellReply(output: '', exitCode: 0);
  }

  @override
  Future<void> install(String apkPath, List<String> options, {void Function(int sent, int total)? onProgress}) async {
    log.add('install $apkPath ${options.join(' ')}');
    if (installError != null) throw installError!;
    onProgress?.call(10, 10);
  }

  @override
  Future<void> push(String localPath, String remotePath, {void Function(int sent, int total)? onProgress}) async {
    log.add('push $localPath $remotePath');
    pushed[remotePath] = localPath;
    onProgress?.call(10, 10);
  }

  final pushed = <String, String>{};

  /// Remote path -> contents, served by [pull]. A missing path fails like adb does.
  final Map<String, String> files = {};

  @override
  Future<void> pull(String remotePath, String localPath) async {
    log.add('pull $remotePath');
    final c = files[remotePath];
    if (c == null) throw const AdbFailure('Lost the connection to the scooter.');
    await File(localPath).writeAsString(c);
  }

  @override
  Future<void> disconnect() async {}
}
