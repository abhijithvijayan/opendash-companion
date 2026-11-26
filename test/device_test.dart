import 'package:flutter_test/flutter_test.dart';
import 'package:opendash_companion/discovery/device.dart';

DiscoveredDevice dev({List<String> addrs = const [], bool diag = false, String? mac, String? name}) =>
    DiscoveredDevice(addresses: [for (final h in addrs) Addr(h)], diagnostics: diag, mac: mac, mdnsName: name);

void main() {
  group('Addr', () {
    test('classifies IPv4, link-local and global addresses', () {
      expect(Addr('172.20.10.5').isIpv4, isTrue);
      expect(Addr('fe80::1%wlan0').isLinkLocal, isTrue);
      expect(Addr('fe80::1%wlan0').isIpv4, isFalse);
      expect(Addr('2401:4900::1').isLinkLocal, isFalse);
    });
  });

  group('groupDevices', () {
    test('merges two mDNS hits sharing an instance name into one device, preferring IPv4', () {
      final r = groupDevices([
        dev(addrs: ['fe80::b6ed:d5ff:fe25:2a61%wlan0'], name: 'adb-a595e4dd', diag: true),
        dev(addrs: ['172.20.10.5'], name: 'adb-a595e4dd'),
      ]);
      expect(r.length, 1);
      expect(r.single.addresses.map((a) => a.host),
          containsAll(['172.20.10.5', 'fe80::b6ed:d5ff:fe25:2a61%wlan0']));
      expect(r.single.preferred.host, '172.20.10.5');
      expect(r.single.diagnostics, isTrue);
    });

    test('folds a fallback hit into an mDNS device by shared MAC', () {
      final r = groupDevices([
        dev(addrs: ['fe80::b6ed:d5ff:fe25:2a61%wlan0', '172.20.10.5'], name: 'adb-a595e4dd', mac: 'b4:ed:d5:25:2a:61', diag: true),
        dev(addrs: ['172.20.10.5'], mac: 'b4:ed:d5:25:2a:61'),
      ]);
      expect(r.length, 1);
      expect(r.single.diagnostics, isTrue);
      expect(r.single.key, 'b4:ed:d5:25:2a:61'); // MAC-first identity (per spec)
    });

    test('keeps devices with no shared identity signal separate', () {
      final r = groupDevices([
        dev(addrs: ['172.20.10.5'], mac: 'aa:aa:aa:aa:aa:aa'),
        dev(addrs: ['172.20.10.8'], mac: 'bb:bb:bb:bb:bb:bb'),
      ]);
      expect(r.length, 2);
    });

    test('preferred picks the link-local when no IPv4 is present', () {
      final r = groupDevices([dev(addrs: ['fe80::1%wlan0'], mac: 'aa:aa:aa:aa:aa:aa')]);
      expect(r.single.preferred.host, 'fe80::1%wlan0');
    });
  });
}
