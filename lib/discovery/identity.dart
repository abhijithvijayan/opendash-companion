import 'dart:io';

/// The NIC MAC embedded in an EUI-64 IPv6 link-local address (`fe80::…`), as
/// lowercase `aa:bb:cc:dd:ee:ff`, or null when [addr] is not an EUI-64
/// link-local — a global address, IPv4, or a privacy/randomized IID.
///
/// EUI-64 forms the interface id by inserting `ff:fe` in the middle of the
/// 48-bit MAC and flipping the universal/local bit; this reverses that, with
/// no I/O. Any `%iface` scope is stripped first.
String? macFromLinkLocal(String addr) {
  final a = InternetAddress.tryParse(addr.split('%').first);
  if (a == null || a.type != InternetAddressType.IPv6) return null;
  final b = a.rawAddress; // 16 bytes
  if (b[0] != 0xfe || b[1] != 0x80) return null; // fe80::/ link-local
  if (b[11] != 0xff || b[12] != 0xfe) return null; // EUI-64 marker
  final mac = [b[8] ^ 0x02, b[9], b[10], b[13], b[14], b[15]];
  return mac.map((x) => x.toRadixString(16).padLeft(2, '0')).join(':');
}
