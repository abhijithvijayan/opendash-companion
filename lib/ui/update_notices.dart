import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../releases/release.dart';
import '../state/providers.dart';
import 'actions.dart';
import 'release_notes_sheet.dart';
import 'widgets.dart';

/// An OpenDash release newer than [installedBuild]. With [onUpdate] null the
/// notice only tells (not connected yet).
class OpenDashUpdateNotice extends ConsumerWidget {
  const OpenDashUpdateNotice({super.key, required this.installedBuild, this.onUpdate});
  final int installedBuild;
  final void Function(Release r)? onUpdate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final check = ref.watch(openDashReleaseProvider).value;
    final skipped = ref.watch(skippedOpenDashProvider);
    if (check is! ReleaseFound) return const SizedBox.shrink();
    final r = check.release;
    if (!offerUpdate(r, installedBuild: installedBuild, skippedBuild: skipped)) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Notice(
        icon: Icons.system_update_rounded,
        title: 'OpenDash ${r.version} is out',
        body: onUpdate == null
            ? 'Connect to your scooter to update.${r.published.isEmpty ? '' : ' Released ${r.published}.'}'
            : r.published.isEmpty
                ? null
                : 'Released ${r.published}.',
        actions: [
          TextButton(onPressed: () => ref.read(skippedOpenDashProvider.notifier).skip(r.build), child: const Text('Skip this version')),
          TextButton(onPressed: () => showReleaseNotes(context, r), child: const Text("What's new")),
          if (onUpdate != null) FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(0, 40)), onPressed: () => onUpdate!(r), child: const Text('Update')),
        ],
      ),
    );
  }
}

class CompanionUpdateNotice extends ConsumerWidget {
  const CompanionUpdateNotice({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (kCompanionBuild == 0 || kCompanionCertSha256.isEmpty) return const SizedBox.shrink();
    final check = ref.watch(companionReleaseProvider).value;
    final skipped = ref.watch(skippedCompanionProvider);
    if (check is! ReleaseFound) return const SizedBox.shrink();
    final r = check.release;
    if (!offerUpdate(r, installedBuild: kCompanionBuild, skippedBuild: skipped)) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Notice(
        icon: Icons.phone_android_rounded,
        title: 'This app has an update: ${r.version}',
        actions: [
          TextButton(onPressed: () => ref.read(skippedCompanionProvider.notifier).skip(r.build), child: const Text('Skip')),
          TextButton(onPressed: () => showReleaseNotes(context, r, name: 'OpenDash Companion'), child: const Text("What's new")),
          FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 40)), onPressed: () => updateCompanion(context, ref, r), child: const Text('Update')),
        ],
      ),
    );
  }
}
