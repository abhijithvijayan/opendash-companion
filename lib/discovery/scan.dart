import 'dart:async';
import 'dart:io';

import '../scooter/ids.dart';

class FoundHost {
  const FoundHost(this.host, {required this.diagnostics});
  final String host;

  /// The stock diagnostics port answered too: this is an Ola head unit.
  final bool diagnostics;
}

/// Every other host of each address's /24. The `.1` of each subnet comes first:
/// on the scooter's own hotspot it is the scooter.
List<String> subnetHosts(List<({String address, String iface})> ipv4) {
  final own = {for (final a in ipv4) a.address};
  final first = <String>[];
  final rest = <String>[];
  final seen = <String>{};
  for (final a in ipv4) {
    final parts = a.address.split('.');
    if (parts.length != 4 || parts[0] == '127' || (parts[0] == '169' && parts[1] == '254')) continue;
    final prefix = parts.take(3).join('.');
    if (!seen.add(prefix)) continue;
    for (var i = 1; i <= 254; i++) {
      final h = '$prefix.$i';
      if (own.contains(h)) continue;
      (i == 1 ? first : rest).add(h);
    }
  }
  return [...first, ...rest];
}

List<String> parsePing6Neighbours(String out, String iface, {Set<String> own = const {}}) {
  final found = <String>[];
  for (final m in RegExp(r'bytes from ([0-9a-fA-F:]+)(?:%[\w.]+)?:').allMatches(out)) {
    final addr = m.group(1)!.toLowerCase();
    if (own.contains(addr)) continue;
    final scoped = '$addr%$iface';
    if (!found.contains(scoped)) found.add(scoped);
  }
  return found;
}

Future<bool> _open(String host, int port, Duration timeout) async {
  try {
    final s = await Socket.connect(host, port, timeout: timeout);
    s.destroy();
    return true;
  } catch (_) {
    return false;
  }
}

Future<List<String>> _ipv6Neighbours(List<NetworkInterface> ifaces) async {
  final out = <String>[];
  for (final i in ifaces) {
    final own = {
      for (final a in i.addresses)
        if (a.type == InternetAddressType.IPv6) a.address.split('%').first.toLowerCase(),
    };
    if (own.isEmpty) continue;
    try {
      final r = await Process.run('ping6', ['-c', '2', '-w', '3', 'ff02::1%${i.name}']).timeout(const Duration(seconds: 5));
      out.addAll(parsePing6Neighbours('${r.stdout}', i.name, own: own));
    } catch (_) {}
  }
  return out;
}

/// Hosts with adb (5555) open on the phone's networks: Wi-Fi, its own
/// hotspot, and IPv6 link-local neighbours.
Stream<FoundHost> scan({Duration probeTimeout = const Duration(milliseconds: 1200), int concurrency = 48}) {
  var stopped = false;
  final out = StreamController<FoundHost>(onCancel: () => stopped = true);
  () async {
    final ifaces = (await NetworkInterface.list(includeLinkLocal: true, type: InternetAddressType.any))
        .where((i) => i.name != 'lo' && !i.name.startsWith('rmnet') && !i.name.startsWith('dummy'))
        .toList();
    final v4 = [
      for (final i in ifaces)
        for (final a in i.addresses)
          if (a.type == InternetAddressType.IPv4) (address: a.address, iface: i.name),
    ];
    final queue = [...subnetHosts(v4), ...await _ipv6Neighbours(ifaces)];
    var next = 0;
    Future<void> worker() async {
      while (next < queue.length && !stopped) {
        final host = queue[next++];
        if (await _open(host, kAdbPort, probeTimeout)) {
          final diag = await _open(host, kDiagnosticsPort, probeTimeout);
          if (!stopped) out.add(FoundHost(host, diagnostics: diag));
        }
      }
    }

    await Future.wait([for (var i = 0; i < concurrency; i++) worker()]);
    await out.close();
  }();
  return out.stream;
}
