import 'package:flutter_test/flutter_test.dart';
import 'package:opendash_companion/scooter/pm_errors.dart';

void main() {
  test('different signing key', () {
    expect(explainInstallFailure('Install failed: Failure [INSTALL_FAILED_UPDATE_INCOMPATIBLE: Package in.abhijithvijayan.opendash signatures do not match]'),
        'A build signed by a different key is installed. Uninstall it first.');
  });
  test('downgrade', () {
    expect(explainInstallFailure('Failure [INSTALL_FAILED_VERSION_DOWNGRADE]'), 'The scooter already has a newer build.');
  });
  test('storage', () {
    expect(explainInstallFailure('Failure [INSTALL_FAILED_INSUFFICIENT_STORAGE]'), 'The scooter is out of storage.');
  });
  test('damaged apk', () {
    expect(explainInstallFailure('Failure [INSTALL_PARSE_FAILED_NOT_APK: Failed to parse]'), 'The APK is damaged or not an app.');
  });
  test('unknown code is named', () {
    expect(explainInstallFailure('Failure [INSTALL_FAILED_ABORTED: User rejected]'), 'Install failed: INSTALL_FAILED_ABORTED');
  });
  test('no code: first line', () {
    expect(explainInstallFailure('something odd\nmore'), 'Install failed: something odd');
  });
}
