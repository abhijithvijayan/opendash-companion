import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:opendash_companion/scooter/ids.dart';

/// A fork's release workflow passes its own repository, so its app updates
/// itself from, and links to, the fork's releases.
void main() {
  test('without COMPANION_REPO a build uses this project\'s releases', () {
    expect(kCompanionRepo, 'abhijithvijayan/opendash-companion');
  });

  test('a release is told which repository it came from', () {
    expect(File('scripts/release.sh').readAsStringSync(), contains('--dart-define=COMPANION_REPO='));
    expect(File('.github/workflows/release.yml').readAsStringSync(), contains(r'COMPANION_REPO: ${{ github.repository }}'));
  });
}
