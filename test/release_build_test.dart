import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:opendash_companion/scooter/ids.dart';

/// A fork's release workflow passes its own repository, so its app updates
/// itself from, and links to, the fork's releases.
void main() {
  test('without COMPANION_REPO a build uses this project\'s releases', () {
    expect(kCompanionRepo, 'abhijithvijayan/opendash-companion');
  });

  test('without OPENDASH_REPO and OPENDASH_CERT_SHA256 it installs this project\'s OpenDash, checked against its key', () {
    expect(kOpenDashRepo, 'abhijithvijayan/opendash');
    expect(kOpenDashCertSha256, '25f012a33b86ab2365b480b594998a131fa8e0edc3768c9e258440f98d4ba7ee');
  });

  test('a fork of both apps can point its release at its own OpenDash and key, together', () {
    final script = File('scripts/release.sh').readAsStringSync();
    expect(script, contains('--dart-define=OPENDASH_REPO='));
    expect(script, contains('--dart-define=OPENDASH_CERT_SHA256='));
    final workflow = File('.github/workflows/release.yml').readAsStringSync();
    expect(workflow, contains(r'OPENDASH_REPO: ${{ vars.OPENDASH_REPO }}'));
    expect(workflow, contains(r'OPENDASH_CERT_SHA256: ${{ vars.OPENDASH_CERT_SHA256 }}'));
  });

  test('a release is told which repository it came from', () {
    expect(File('scripts/release.sh').readAsStringSync(), contains('--dart-define=COMPANION_REPO='));
    expect(File('.github/workflows/release.yml').readAsStringSync(), contains(r'COMPANION_REPO: ${{ github.repository }}'));
  });
}
