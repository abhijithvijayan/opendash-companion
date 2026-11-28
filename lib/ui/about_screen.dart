import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../releases/update_schedule.dart';
import '../state/providers.dart';
import 'ack_screen.dart';
import 'report_actions.dart';
import 'widgets.dart';

const kAuthorUrl = 'https://abhijithvijayan.in';

/// 'v0.1.0 · build 42' on a release, 'Development build' otherwise.
String versionLabel({String version = kCompanionVersion, int build = kCompanionBuild}) {
  if (build == 0) return 'Development build';
  return version.isEmpty ? 'Build $build' : 'v$version · build $build';
}

class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final muted = t.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant);

    Widget link(IconData icon, String title, String subtitle, String url, {Key? key}) => ListTile(
      key: key,
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.open_in_new_rounded, size: 18),
      onTap: () => openUrl(context, ref, url),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text('S1 Dash Companion', style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(versionLabel(), key: const ValueKey('about-version'), style: muted),
          const SizedBox(height: 12),
          Text('Installs, updates and removes S1 Dash on an Ola S1 scooter, from your phone.', style: t.textTheme.bodyLarge),
          const SizedBox(height: 20),
          const Notice(
            icon: Icons.shield_outlined,
            title: 'Privacy',
            body: 'This app talks only to your scooter and to GitHub. It collects nothing.',
          ),
          const SectionLabel('Notifications'),
          Card(
            clipBehavior: Clip.antiAlias,
            child: _NotifyToggle(),
          ),
          const SectionLabel('Project'),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                link(
                  Icons.code_rounded,
                  'Source and releases',
                  'github.com/$kCompanionRepo',
                  'https://github.com/$kCompanionRepo',
                  key: const ValueKey('about-repo'),
                ),
                const Divider(indent: 56),
                link(
                  Icons.bug_report_outlined,
                  'Report a problem with this app',
                  'Installing, connecting, updating',
                  'https://github.com/$kCompanionRepo/issues',
                  key: const ValueKey('about-issues-companion'),
                ),
                const Divider(indent: 56),
                ListTile(
                  key: const ValueKey('about-share-logs'),
                  leading: const Icon(Icons.ios_share_rounded),
                  title: const Text('Share logs'),
                  subtitle: const Text("This app's log, and S1 Dash's when connected"),
                  onTap: () => shareLogs(context, ref),
                ),
              ],
            ),
          ),
          const SectionLabel('S1 Dash'),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                link(
                  Icons.speed_rounded,
                  'S1 Dash',
                  'The dashboard this app installs',
                  'https://github.com/$kOpenDashRepo',
                  key: const ValueKey('about-opendash'),
                ),
                const Divider(indent: 56),
                link(
                  Icons.bug_report_outlined,
                  'Report a problem with S1 Dash',
                  'Something wrong on the dashboard itself',
                  'https://github.com/$kOpenDashRepo/issues',
                  key: const ValueKey('about-issues-opendash'),
                ),
              ],
            ),
          ),
          const SectionLabel('Credits'),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                link(Icons.terminal_rounded, 'Kadb', 'adb in Kotlin, by flyfishxu. Apache 2.0', 'https://github.com/flyfishxu/Kadb'),
                const Divider(indent: 56),
                link(
                  Icons.text_fields_rounded,
                  'Archivo',
                  'The typeface, by Omnibus-Type. SIL Open Font License',
                  'https://fonts.google.com/specimen/Archivo',
                ),
                const Divider(indent: 56),
                link(Icons.widgets_outlined, 'Flutter', 'The UI toolkit, by Google. BSD 3-Clause', 'https://flutter.dev'),
              ],
            ),
          ),
          const SectionLabel('Legal'),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.fact_check_outlined),
                  title: const Text('Acknowledgement'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AckScreen(readOnly: true))),
                ),
                const Divider(indent: 56),
                ListTile(
                  key: const ValueKey('about-licenses'),
                  leading: const Icon(Icons.gavel_rounded),
                  title: const Text('Open source licences'),
                  subtitle: const Text('This app: GNU General Public License v3.0'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => showLicensePage(
                    context: context,
                    applicationName: 'S1 Dash Companion',
                    applicationVersion: versionLabel(),
                    applicationLegalese: 'Copyright © Abhijith Vijayan. Free software under the GNU GPL, version 3 or later.',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          Text(
            'Copyright © Abhijith Vijayan. Free software under the GNU GPL, version 3 or later, with no warranty. '
            'Not made by or affiliated with Ola Electric.',
            style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Center(
            child: InkWell(
              key: const ValueKey('about-author'),
              borderRadius: BorderRadius.circular(12),
              onTap: () => openUrl(context, ref, kAuthorUrl),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Built by ', style: muted),
                    Text('abhijithvijayan', style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(width: 6),
                    Icon(Icons.favorite_rounded, size: 16, color: cs.error),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NotifyToggle extends ConsumerStatefulWidget {
  @override
  ConsumerState<_NotifyToggle> createState() => _NotifyToggleState();
}

class _NotifyToggleState extends ConsumerState<_NotifyToggle> {
  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(prefsProvider);
    return SwitchListTile(
      key: const ValueKey('about-notify-updates'),
      secondary: const Icon(Icons.notifications_outlined),
      title: const Text('Notify me about updates'),
      subtitle: const Text('Checks GitHub a few times a day for new releases'),
      value: prefs.notifyUpdates,
      onChanged: (v) async {
        await prefs.setNotifyUpdates(v);
        if (!mounted) return;
        setState(() {});
        try {
          await (v ? scheduleUpdateCheck() : cancelUpdateCheck());
        } catch (_) {}
      },
    );
  }
}
