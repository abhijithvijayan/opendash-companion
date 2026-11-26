/// The OpenDash this app installs, and the key its releases must be signed
/// with ([kOpenDashCertSha256]). They go together: a fork of both apps sets
/// both (repository variables OPENDASH_REPO and OPENDASH_CERT_SHA256);
/// otherwise this project's OpenDash.
const kOpenDashRepo = String.fromEnvironment('OPENDASH_REPO', defaultValue: 'abhijithvijayan/opendash');
/// This app's own releases, which it updates itself from and links to. The
/// release workflow passes the repository it runs in (`COMPANION_REPO`), so
/// a fork's app follows the fork's releases; any other build follows these.
const kCompanionRepo = String.fromEnvironment('COMPANION_REPO', defaultValue: 'abhijithvijayan/opendash-companion');

/// Set by scripts/release.sh. 0 on a dev build, which never offers itself an update.
const kCompanionBuild = int.fromEnvironment('COMPANION_BUILD');
const kCompanionVersion = String.fromEnvironment('COMPANION_VERSION');

const kOpenDashPackage = 'in.abhijithvijayan.opendash';
const kOpenDashActivity = 'in.abhijithvijayan.opendash/.MainActivity';
const kStockPackage = 'com.olaelectric.hmiclient';
const kStockActivity = 'com.olaelectric.hmiclient/.MainActivity';
const kCompanionPackage = 'in.abhijithvijayan.opendash.companion';
const kAdbPort = 5555;

/// The folder OpenDash shares with this app: its answer in `accepts.json`,
/// updates sent to it in `incoming/`.
const kOpenDashInbox = '/sdcard/Android/data/in.abhijithvijayan.opendash/files/companion';
const kDiagnosticsPort = 50005;

/// OpenDash's own log. It masks VIN, serials, phone and network names before
/// writing, so it can be shared.
const kOpenDashLogDir = '/sdcard/Android/data/$kOpenDashPackage/files/analytics';

/// SHA-256 of the certificate every official OpenDash release is signed with.
const kOpenDashCertSha256 =
    String.fromEnvironment('OPENDASH_CERT_SHA256', defaultValue: '25f012a33b86ab2365b480b594998a131fa8e0edc3768c9e258440f98d4ba7ee');

/// The scooter's own software, never offered for removal. Most of it is
/// system apps that `pm list packages -3` leaves out anyway; this guards the
/// builds where one is installed as an ordinary app.
bool isStockPackage(String pkg) =>
    pkg == kStockPackage ||
    pkg == 'com.android.hmiserverapp' ||
    pkg.startsWith('com.olaelectric.') ||
    pkg.startsWith('com.ola.') ||
    pkg.startsWith('com.quectel.');
