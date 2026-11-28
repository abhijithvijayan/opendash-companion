import 'dart:io';

import 'package:crypto/crypto.dart';

import '../adb/adb_api.g.dart';

sealed class Verdict {
  const Verdict();
}

class Official extends Verdict {
  const Official();
}

/// Right package, not the release key: allowed only after the rider confirms.
class Unofficial extends Verdict {
  const Unofficial(this.why);
  final String why;
}

class Rejected extends Verdict {
  const Rejected(this.why);
  final String why;
}

/// [expectedSha256] is set for a download (from the release json) and null
/// for a file the rider picked.
Verdict verifyApk({
  required String fileSha256,
  String? expectedSha256,
  required ApkInfo? info,
  required String pinnedCert,
  required String expectedPackage,
}) {
  if (expectedSha256 != null && fileSha256.toLowerCase() != expectedSha256.toLowerCase()) {
    return const Rejected("The download doesn't match the release's checksum.");
  }
  if (info == null) return const Rejected('This file is not an Android app.');
  if (info.packageName != expectedPackage) return Rejected('This APK is ${info.packageName}, not S1 Dash.');
  final official = pinnedCert.isNotEmpty && info.certSha256.map((c) => c.toLowerCase()).contains(pinnedCert.toLowerCase());
  if (official) return const Official();
  if (expectedSha256 != null) return const Rejected("The download isn't signed with the release key.");
  return const Unofficial("This APK is not signed with S1 Dash's release key.");
}

Future<String> sha256OfFile(String path) async => (await sha256.bind(File(path).openRead()).first).toString();
