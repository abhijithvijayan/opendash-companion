import 'dart:async';
import 'dart:io';

import 'package:nsd/nsd.dart' as nsd;

import '../scooter/ids.dart';
import 'device.dart';
import 'identity.dart';

/// Ensures a link-local address is dial-able by attaching an interface scope
/// (`%iface`) when it has none. An IPv4 address, a global IPv6, or an
/// already-scoped link-local is returned unchanged. When no interface is given,
/// a Wi-Fi/AP interface from [ifaceNames] is preferred, else the first.
String scopedHost(String host, String? iface, List<String> ifaceNames) {
  final isLinkLocal = host.contains(':') && host.toLowerCase().startsWith('fe80');
  if (!isLinkLocal || host.contains('%')) return host;
  final scope = iface ??
      ifaceNames.firstWhere(
        (n) => n.startsWith('wlan') || n.startsWith('ap'),
        orElse: () => ifaceNames.isNotEmpty ? ifaceNames.first : '',
      );
  return scope.isEmpty ? host : '$host%$scope';
}

/// Discovers adb devices advertised over mDNS (`_adb._tcp`, which AOSP `adbd`
/// publishes). Each service is one device carrying all its addresses; the stock
/// diagnostics port (50005) is probed to tag Ola head units. Empties silently
/// if mDNS is unavailable — the ping6/subnet sweep still runs as fallback.
Stream<DiscoveredDevice> mdnsScan({Duration timeout = const Duration(seconds: 6)}) {
  var stopped = false;
  final out = StreamController<DiscoveredDevice>(onCancel: () => stopped = true);
  final seen = <String>{};
  () async {
    nsd.Discovery? disc;
    try {
      final ifaceNames = await _wifiIfaceNames();
      disc = await nsd.startDiscovery('_adb._tcp', ipLookupType: nsd.IpLookupType.any);
      Future<void> handle(nsd.Service s, nsd.ServiceStatus status) async {
        if (stopped || status != nsd.ServiceStatus.found) return;
        final name = s.name;
        if (name != null && seen.contains(name)) return;
        final dev = await _toDevice(s, ifaceNames);
        if (dev == null || stopped || out.isClosed) return;
        // Mark seen only once a real, address-bearing device is emitted, so a
        // bare found-event can't block the later resolved one for the service.
        if (name != null) seen.add(name);
        out.add(dev);
      }

      disc.addServiceListener(handle);
      for (final s in disc.services) {
        if (stopped) break;
        await handle(s, nsd.ServiceStatus.found);
      }
      // Poll so Stop (subscription cancel) or screen dispose ends discovery
      // promptly, instead of running the full timeout and its probes.
      final deadline = DateTime.now().add(timeout);
      while (!stopped && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    } catch (_) {
      // mDNS unavailable or denied; discovery falls back to the sweep.
    } finally {
      if (disc != null) {
        try {
          await nsd.stopDiscovery(disc);
        } catch (_) {}
      }
      if (!out.isClosed) await out.close();
    }
  }();
  return out.stream;
}

Future<DiscoveredDevice?> _toDevice(nsd.Service s, List<String> ifaceNames) async {
  final addrs = <Addr>[];
  String? mac;
  for (final ia in s.addresses ?? const <InternetAddress>[]) {
    final host = scopedHost(ia.address, null, ifaceNames);
    addrs.add(Addr(host));
    mac ??= macFromLinkLocal(host);
  }
  if (addrs.isEmpty) return null;
  final probe = addrs.firstWhere((a) => a.isIpv4, orElse: () => addrs.first);
  final diag = await _open(probe.host, kDiagnosticsPort, const Duration(milliseconds: 1200));
  return DiscoveredDevice(addresses: addrs, diagnostics: diag, mac: mac, mdnsName: s.name);
}

Future<List<String>> _wifiIfaceNames() async {
  try {
    final ifaces = await NetworkInterface.list(includeLinkLocal: true, type: InternetAddressType.any);
    return [
      for (final i in ifaces)
        if (i.name != 'lo' && !i.name.startsWith('rmnet') && !i.name.startsWith('dummy')) i.name,
    ];
  } catch (_) {
    return const [];
  }
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
