import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../adb/adb.dart';
import '../state/providers.dart';
import 'actions.dart';
import 'widgets.dart';

final publicKeyProvider = FutureProvider<String>((ref) => ref.read(hostApiProvider).publicKey());

/// The scooter answered on adb but doesn't accept this phone's key yet.
class ManualKeyScreen extends ConsumerWidget {
  const ManualKeyScreen({super.key, required this.host});
  final String host;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conn = ref.watch(connectionProvider);
    final key = ref.watch(publicKeyProvider);
    final t = Theme.of(context);
    final cs = t.colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Set up access')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Notice(
            icon: Icons.key_off_rounded,
            color: cs.tertiary,
            title: "$host doesn't accept this phone yet",
            body: 'The scooter answered on adb, but this phone is new to it. Add the key below to the scooter the same way '
                'you set up adb access from your computer, then try again.',
          ),
          const SectionLabel("This phone's adb key"),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: key.when(
                data: (k) => SelectableText(k, style: const TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.4)),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Text("Couldn't read the key: $e"),
              ),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: key.value == null
                ? null
                : () async {
                    await Clipboard.setData(ClipboardData(text: key.value!));
                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Key copied')));
                  },
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Copy key'),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: conn.busy ? null : () => ref.read(connectionProvider.notifier).connect(host),
            child: Text(conn.busy ? 'Trying…' : 'Try again'),
          ),
          if (!conn.busy && conn.outcome == ConnectOutcome.unauthorized) ...[
            const SizedBox(height: 16),
            Text('Getting adb access to a scooter for the first time is described in the OpenDash README, under "Before You Install".',
                style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }
}
