import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'widgets.dart';

/// The scooter refused to be set up over the network; copying a key can't help either.
class SealedScreen extends ConsumerWidget {
  const SealedScreen({super.key, required this.host});
  final String host;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Set up access')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Notice(
            icon: Icons.lock_outline_rounded,
            color: cs.error,
            title: "$host can't be set up from here",
            body:
                "This scooter's diagnostics service doesn't allow this phone to be set up over the network, "
                'so OpenDash Companion cannot grant itself access.',
          ),
          const SizedBox(height: 16),
          Text(
            'OpenDash has to be side-loaded onto this scooter instead. The OpenDash README describes how, under "Before You Install".',
            style: t.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
