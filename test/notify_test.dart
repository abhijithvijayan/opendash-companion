import 'package:flutter_test/flutter_test.dart';
import 'package:opendash_companion/releases/notify.dart';
import 'package:opendash_companion/releases/release.dart';

Release rel(int b) => Release(version: '1.$b', build: b, sha256: '', apkUrl: '', apkName: '');

void main() {
  UpdateNotice? run(Release? l, {int installed = 5, int skipped = 0, int last = 0}) =>
      decideNotice(latest: l, installedBuild: installed, skippedBuild: skipped, lastNotifiedBuild: last);

  test('newer un-notified build notifies', () {
    final n = run(rel(7));
    expect(n!.build, 7);
    expect(n.version, '1.7');
  });
  test('already notified build is null', () => expect(run(rel(7), last: 7), isNull));
  test('skipped build is null', () => expect(run(rel(7), skipped: 7), isNull));
  test('null release is null', () => expect(run(null), isNull));
  test('older or equal release is null', () {
    expect(run(rel(4)), isNull);
    expect(run(rel(5)), isNull);
  });
}
