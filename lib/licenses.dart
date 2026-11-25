import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Adds what Flutter's licence page can't find by itself: the font, and the
/// Android libraries the adb layer is built on (they come in through Gradle,
/// not pub).
void registerLicenses() {
  LicenseRegistry.addLicense(() async* {
    final apache = await rootBundle.loadString('assets/licenses/apache-2.0.txt');
    yield LicenseEntryWithLineBreaks(['Archivo'], await rootBundle.loadString('assets/fonts/OFL.txt'));
    yield LicenseEntryWithLineBreaks([
      'Kadb',
      'Okio',
      'kotlinx.coroutines',
      'AndroidX',
      'ReLinker',
      'Apache Commons IO',
      'Apache Tika',
    ], apache);
    yield LicenseEntryWithLineBreaks(['Bouncy Castle'], await rootBundle.loadString('assets/licenses/bouncycastle.txt'));
    yield LicenseEntryWithLineBreaks([
      'curve25519-elisabeth',
      'ed25519-elisabeth',
    ], await rootBundle.loadString('assets/licenses/elisabeth.txt'));
    yield const LicenseEntryWithLineBreaks([
      'spake2-java',
    ], 'Licensed under the GNU General Public License, version 3.\nhttps://www.gnu.org/licenses/gpl-3.0.txt');
  });
}
