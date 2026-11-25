import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:opendash_companion/licenses.dart';
import 'package:opendash_companion/ui/about_screen.dart';

void main() {
  test('version label', () {
    expect(versionLabel(version: '', build: 0), 'Development build');
    expect(versionLabel(version: '0.1.0', build: 42), 'v0.1.0 · build 42');
    expect(versionLabel(version: '', build: 42), 'Build 42');
  });

  testWidgets('About credits the author and the libraries', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AboutScreen()));
    expect(find.text('Development build'), findsOneWidget);
    for (final key in [
      'about-repo',
      'about-issues-companion',
      'about-opendash',
      'about-issues-opendash',
      'about-licenses',
      'about-author',
    ]) {
      await tester.scrollUntilVisible(find.byKey(ValueKey(key)), 200);
      expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
    }
    expect(find.text('abhijithvijayan'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Kadb'), -200);
    expect(find.text('Kadb'), findsOneWidget);
    expect(find.text('Archivo'), findsOneWidget);
  });

  testWidgets('the licence page lists the Android libraries and the font', (tester) async {
    registerLicenses();
    final names = <String>{};
    await tester.runAsync(() async {
      await for (final e in LicenseRegistry.licenses) {
        names.addAll(e.packages);
      }
    });
    expect(names, containsAll(['Archivo', 'Kadb', 'Bouncy Castle', 'spake2-java', 'curve25519-elisabeth']));
  });
}
