import 'package:flutter_test/flutter_test.dart';
import 'package:opendash_companion/scooter/parse.dart';

void main() {
  group('parseDumpsysVersion', () {
    test('reads the first versionCode and versionName', () {
      const out = '''
Packages:
  Package [in.abhijithvijayan.opendash] (5d1c2a):
    versionCode=2041 minSdk=24 targetSdk=36
    versionName=0.2.1
    signatures=PackageSignatures{...}
''';
      final v = parseDumpsysVersion(out);
      expect(v.versionCode, 2041);
      expect(v.versionName, '0.2.1');
    });

    test('is empty when the package is absent', () {
      final v = parseDumpsysVersion('Unable to find package: in.abhijithvijayan.opendash\n');
      expect(v.versionCode, isNull);
      expect(v.versionName, isNull);
    });
  });

  test('parseHomeActivity takes the last component line', () {
    const out = 'priority=0 preferredOrder=0 match=0x108000 specificIndex=-1 isDefault=false\nin.abhijithvijayan.opendash/.MainActivity\n';
    expect(parseHomeActivity(out), 'in.abhijithvijayan.opendash/.MainActivity');
    expect(parseHomeActivity('No activity found\n'), isNull);
  });

  test('parseDensity reads physical and override', () {
    expect(parseDensity('Physical density: 240\nOverride density: 160\n'), (physical: 240, override: 160));
    expect(parseDensity('Physical density: 240\n'), (physical: 240, override: null));
  });

  test('other apps filter: drops stock, com.olaelectric.* and this app, keeps OpenDash and the rest', () {
    const out = '''
package:com.olaelectric.hmiclient
package:com.olaelectric.ota
package:in.abhijithvijayan.opendash
package:com.example.somemod
package:com.hxmst.otablocker
package:in.abhijithvijayan.opendash.companion
package:com.android.hmiserverapp
package:com.ola.mfgapp
package:com.ola.olalogger.receiver
''';
    expect(parseThirdPartyPackages(out), ['in.abhijithvijayan.opendash', 'com.example.somemod', 'com.hxmst.otablocker']);
  });

  test('parseAccepts reads what OpenDash published', () {
    final a = parseAccepts('{"v":1,"auto":true,"installed":2041,"skipped":2050}')!;
    expect((a.auto, a.installed, a.skipped), (true, 2041, 2050));
    expect(parseAccepts('cat: /sdcard/Android/data/x/files/companion/accepts.json: No such file or directory'), isNull);
    expect(parseAccepts('{"v":1}'), isNull);
  });

  test('parseStagedBuild reads the build already sent', () {
    expect(parseStagedBuild('{"version":"0.2.2","build":2050,"apk":"o.apk","sha256":"ab"}'), 2050);
    expect(parseStagedBuild('cat: x: No such file or directory'), isNull);
  });
}
