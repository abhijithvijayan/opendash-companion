import 'package:http/http.dart' as http;

import '../state/prefs.dart';
import '../scooter/ids.dart';
import 'notify.dart';
import 'release.dart';

/// Headless update check: fetch both channels, notify about anything new, and
/// remember what was announced. Plugins and the client are injected.
Future<bool> runUpdateCheck({
  required Prefs prefs,
  required http.Client client,
  required Future<void> Function(String title, String body) notify,
}) async {
  try {
    if (!prefs.notifyUpdates) return true;

    final builds = [for (final r in prefs.recents) r.build ?? 0];
    final installedOpenDash = builds.isEmpty ? 0 : builds.reduce((a, b) => a > b ? a : b);

    final od = await fetchLatest(client, repo: kOpenDashRepo, jsonAsset: 'opendash-release.json');
    final odNotice = decideNotice(
      latest: od is ReleaseFound ? od.release : null,
      installedBuild: installedOpenDash,
      skippedBuild: prefs.skippedOpenDash,
      lastNotifiedBuild: prefs.lastNotifiedOpenDash,
    );
    if (odNotice != null) {
      await notify('S1 Dash ${odNotice.version} is available', 'Open the companion to update your scooter.');
      await prefs.setLastNotifiedOpenDash(odNotice.build);
    }

    // A dev build (build 0) never offers itself an update.
    if (kCompanionBuild == 0) return true;

    final co = await fetchLatest(client, repo: kCompanionRepo, jsonAsset: 'companion-release.json');
    final coNotice = decideNotice(
      latest: co is ReleaseFound ? co.release : null,
      installedBuild: kCompanionBuild,
      skippedBuild: prefs.skippedCompanion,
      lastNotifiedBuild: prefs.lastNotifiedCompanion,
    );
    if (coNotice != null) {
      await notify('S1 Dash Companion ${coNotice.version} is available', 'Open the companion to update it.');
      await prefs.setLastNotifiedCompanion(coNotice.build);
    }
    return true;
  } catch (_) {
    return false;
  }
}
