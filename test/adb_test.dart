import 'package:flutter_test/flutter_test.dart';
import 'package:opendash_companion/adb/adb.dart';
import 'package:opendash_companion/adb/adb_api.g.dart';

class _StubApi implements AdbHostApi {
  _StubApi(this.reply);
  final ProvisionReply reply;

  @override
  Future<ProvisionReply> provision(String host) async => reply;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('provision maps the reply outcome string to the enum', () async {
    for (final (s, e) in [
      ('ok', ProvisionOutcome.ok),
      ('unimplemented', ProvisionOutcome.unimplemented),
      ('unreachable', ProvisionOutcome.unreachable),
      ('failed', ProvisionOutcome.failed),
      ('???', ProvisionOutcome.failed),
    ]) {
      final adb = PigeonAdb(api: _StubApi(ProvisionReply(outcome: s)));
      expect(await adb.provision('h'), e);
    }
  });
}
