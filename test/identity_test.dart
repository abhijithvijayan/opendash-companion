import 'package:flutter_test/flutter_test.dart';
import 'package:opendash_companion/discovery/identity.dart';

void main() {
  group('macFromLinkLocal', () {
    test('extracts the EUI-64 MAC, flipping the U/L bit and stripping scope', () {
      expect(macFromLinkLocal('fe80::b6ed:d5ff:fe25:2a61%wlan0'), 'b4:ed:d5:25:2a:61');
    });

    test('is case-insensitive and returns a lowercased MAC', () {
      expect(macFromLinkLocal('FE80::B6ED:D5FF:FE25:2A61'), 'b4:ed:d5:25:2a:61');
    });

    test('returns null for a non-EUI-64 (privacy) link-local IID', () {
      expect(macFromLinkLocal('fe80::1122:3344:5566:7788'), isNull);
    });

    test('returns null for a global IPv6 and for IPv4', () {
      expect(macFromLinkLocal('2401:4900::1'), isNull);
      expect(macFromLinkLocal('172.20.10.5'), isNull);
    });
  });
}
