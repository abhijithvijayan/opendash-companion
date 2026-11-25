String explainInstallFailure(String raw) {
  final code = RegExp(r'(INSTALL_[A-Z_]+)').firstMatch(raw)?.group(1);
  if (code == null) {
    final first = raw.split('\n').first.trim();
    return 'Install failed: $first';
  }
  if (code == 'INSTALL_FAILED_UPDATE_INCOMPATIBLE') return 'A build signed by a different key is installed. Uninstall it first.';
  if (code == 'INSTALL_FAILED_VERSION_DOWNGRADE') return 'The scooter already has a newer build.';
  if (code == 'INSTALL_FAILED_INSUFFICIENT_STORAGE') return 'The scooter is out of storage.';
  if (code.startsWith('INSTALL_PARSE_FAILED_')) return 'The APK is damaged or not an app.';
  return 'Install failed: $code';
}
