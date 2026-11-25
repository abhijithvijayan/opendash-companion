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
const kOpenDashCertSha256 = '25f012a33b86ab2365b480b594998a131fa8e0edc3768c9e258440f98d4ba7ee';

/// The scooter's own software, never offered for removal. Most of it is
/// system apps that `pm list packages -3` leaves out anyway; this guards the
/// builds where one is installed as an ordinary app.
bool isStockPackage(String pkg) =>
    pkg == kStockPackage ||
    pkg == 'com.android.hmiserverapp' ||
    pkg.startsWith('com.olaelectric.') ||
    pkg.startsWith('com.ola.') ||
    pkg.startsWith('com.quectel.');
