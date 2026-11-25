import 'release.dart';

/// What a background update notification needs to say.
class UpdateNotice {
  const UpdateNotice({required this.version, required this.build});

  final String version;
  final int build;
}

/// A notice only for a build worth offering that we have not already
/// notified about, so a release alerts once.
UpdateNotice? decideNotice({
  required Release? latest,
  required int installedBuild,
  required int skippedBuild,
  required int lastNotifiedBuild,
}) {
  if (latest == null) return null;
  if (!offerUpdate(latest, installedBuild: installedBuild, skippedBuild: skippedBuild)) return null;
  if (latest.build == lastNotifiedBuild) return null;
  return UpdateNotice(version: latest.version, build: latest.build);
}
