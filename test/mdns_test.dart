import 'package:flutter_test/flutter_test.dart';
import 'package:opendash_companion/discovery/mdns.dart';

void main() {
  group('scopedHost', () {
    test('attaches an interface scope to a bare link-local address', () {
      expect(scopedHost('fe80::b6ed:d5ff:fe25:2a61', null, ['wlan0']),
          'fe80::b6ed:d5ff:fe25:2a61%wlan0');
    });

    test('leaves an already-scoped link-local unchanged', () {
      expect(scopedHost('fe80::1%wlan0', null, ['wlan0']), 'fe80::1%wlan0');
    });

    test('leaves an IPv4 address unchanged', () {
      expect(scopedHost('172.20.10.5', null, ['wlan0']), '172.20.10.5');
    });

    test('prefers a wlan/ap interface when several are offered', () {
      expect(scopedHost('fe80::1', null, ['rmnet0', 'wlan0']), 'fe80::1%wlan0');
    });
  });
}
