/// One reachable address of a discovered device.
class Addr {
  const Addr(this.host);

  /// Dial-able host: an IPv4 literal, or an IPv6 literal (link-local scoped
  /// `%iface`).
  final String host;

  bool get isIpv4 => !host.contains(':');
  bool get isLinkLocal => host.toLowerCase().startsWith('fe80');
}

/// A device found by discovery, with every address it was seen at. A scooter
/// answering on both its IPv4 and its IPv6 link-local is one of these, not two.
class DiscoveredDevice {
  DiscoveredDevice({
    required this.addresses,
    required this.diagnostics,
    this.mac,
    this.mdnsName,
  });

  final List<Addr> addresses;

  /// The stock diagnostics port (50005) answered: an Ola head unit.
  final bool diagnostics;

  /// NIC MAC, when known (EUI-64 from a link-local, or read over adb).
  final String? mac;

  /// mDNS service instance name (e.g. `adb-a595e4dd`), when discovered by mDNS.
  final String? mdnsName;

  /// The address to dial: IPv4 when present (reachable in MFG/service mode),
  /// else the first (the link-local, in user mode).
  Addr get preferred => addresses.firstWhere((a) => a.isIpv4, orElse: () => addresses.first);

  /// Stable identity, most durable first (per spec): hardware MAC, then the
  /// mDNS instance name, then the address. Used to key recents.
  String get key => mac ?? mdnsName ?? (addresses.isNotEmpty ? addresses.first.host : '');
}

/// Collapses devices that are the same physical unit — sharing any identity
/// signal (MAC, mDNS instance name, or an address) — into one, transitively.
/// Unions all addresses, ORs [DiscoveredDevice.diagnostics], and keeps the
/// first MAC and mDNS name seen. First-appearance order is preserved.
List<DiscoveredDevice> groupDevices(Iterable<DiscoveredDevice> raw) {
  final list = raw.toList();
  final n = list.length;
  final parent = List.generate(n, (i) => i);
  int find(int x) {
    while (parent[x] != x) {
      parent[x] = parent[parent[x]];
      x = parent[x];
    }
    return x;
  }

  void union(int a, int b) => parent[find(a)] = find(b);

  final byMac = <String, int>{};
  final byName = <String, int>{};
  final byAddr = <String, int>{};
  void sig(Map<String, int> m, String? k, int i) {
    if (k == null) return;
    final j = m[k];
    if (j != null) {
      union(i, j);
    } else {
      m[k] = i;
    }
  }

  for (var i = 0; i < n; i++) {
    final d = list[i];
    sig(byMac, d.mac, i);
    sig(byName, d.mdnsName, i);
    for (final a in d.addresses) sig(byAddr, a.host, i);
  }

  final order = <int>[];
  final groups = <int, List<DiscoveredDevice>>{};
  for (var i = 0; i < n; i++) {
    final r = find(i);
    if (!groups.containsKey(r)) {
      groups[r] = [];
      order.add(r);
    }
    groups[r]!.add(list[i]);
  }
  return [for (final r in order) _merge(groups[r]!)];
}

DiscoveredDevice _merge(List<DiscoveredDevice> g) {
  final addrs = <String, Addr>{};
  var diag = false;
  String? mac, name;
  for (final d in g) {
    for (final a in d.addresses) addrs.putIfAbsent(a.host, () => a);
    diag = diag || d.diagnostics;
    mac ??= d.mac;
    name ??= d.mdnsName;
  }
  return DiscoveredDevice(addresses: addrs.values.toList(), diagnostics: diag, mac: mac, mdnsName: name);
}
