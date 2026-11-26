import 'package:flutter_test/flutter_test.dart';
import 'package:opendash_companion/discovery/device.dart';
import 'package:opendash_companion/discovery/scan.dart';

void main() {
  group('subnetHosts', () {
    test('every other host of the /24, gateway first, own address left out', () {
      final hosts = subnetHosts([(address: '192.168.1.23', iface: 'wlan0')]);
      expect(hosts.first, '192.168.1.1');
      expect(hosts.length, 253);
      expect(hosts, isNot(contains('192.168.1.23')));
      expect(hosts, contains('192.168.1.254'));
      expect(hosts, isNot(contains('192.168.1.0')));
      expect(hosts, isNot(contains('192.168.1.255')));
    });

    test('Wi-Fi and the phone hotspot are both covered, deduped', () {
      final hosts = subnetHosts([
        (address: '10.1.1.5', iface: 'wlan0'),
        (address: '192.168.43.1', iface: 'ap0'),
        (address: '10.1.1.6', iface: 'wlan1'),
      ]);
      expect(hosts, contains('10.1.1.105'));
      expect(hosts, contains('192.168.43.20'));
      expect(hosts, isNot(contains('192.168.43.1')));
      expect(hosts.toSet().length, hosts.length);
      expect(hosts, isNot(contains('10.1.1.5')));
      expect(hosts, isNot(contains('10.1.1.6')));
    });

    test('loopback and link-local are ignored', () {
      expect(subnetHosts([(address: '127.0.0.1', iface: 'lo'), (address: '169.254.3.4', iface: 'x')]), isEmpty);
    });
  });

  test('parsePing6Neighbours', () {
    const out = '''
PING ff02::1%wlan0(ff02::1) 56 data bytes
64 bytes from fe80::aaaa:bbbb:cccc:dddd%wlan0: icmp_seq=1 ttl=64 time=0.05 ms
64 bytes from fe80::b20c:9dff:feba:a122%wlan0: icmp_seq=1 ttl=64 time=3.2 ms (DUP!)
64 bytes from fe80::b20c:9dff:feba:a122: icmp_seq=2 ttl=64 time=3.0 ms
''';
    expect(parsePing6Neighbours(out, 'wlan0', own: {'fe80::aaaa:bbbb:cccc:dddd'}), ['fe80::b20c:9dff:feba:a122%wlan0']);
  });

  group('deviceFromHost', () {
    test('maps a link-local FoundHost to a device carrying its EUI-64 MAC', () {
      final d = deviceFromHost(const FoundHost('fe80::b6ed:d5ff:fe25:2a61%wlan0', diagnostics: true));
      expect(d.addresses.single.host, 'fe80::b6ed:d5ff:fe25:2a61%wlan0');
      expect(d.diagnostics, isTrue);
      expect(d.mac, 'b4:ed:d5:25:2a:61');
      expect(d.mdnsName, isNull);
    });

    test('leaves mac null for an IPv4 FoundHost', () {
      final d = deviceFromHost(const FoundHost('172.20.10.5', diagnostics: false));
      expect(d.mac, isNull);
      expect(d.addresses.single.host, '172.20.10.5');
    });
  });
}
