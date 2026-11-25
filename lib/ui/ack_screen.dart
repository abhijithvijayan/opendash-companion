import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../state/providers.dart';

const _points = [
  (Icons.build_circle_outlined, 'This installs software on a scooter you own, over adb. It may affect your warranty.'),
  (Icons.local_parking_rounded, 'Install and uninstall only while the scooter is parked — the dashboard restarts.'),
  (Icons.info_outline_rounded, 'OpenDash and this app are not made by Ola.'),
  (Icons.verified_user_outlined,
      "This app checks every OpenDash download against its release key. It can't vouch for other apps on your scooter; you can remove them here."),
];

/// The one-time acknowledgement. With [readOnly] it is shown again from About.
class AckScreen extends ConsumerStatefulWidget {
  const AckScreen({super.key, this.readOnly = false});
  final bool readOnly;

  @override
  ConsumerState<AckScreen> createState() => _AckScreenState();
}

class _AckScreenState extends ConsumerState<AckScreen> {
  bool _owner = false;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: widget.readOnly ? AppBar(title: const Text('Acknowledgement')) : null,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 32, 20, 24),
          children: [
            if (!widget.readOnly) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(color: t.colorScheme.primary.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(16)),
                child: Icon(Icons.speed_rounded, color: t.colorScheme.primary, size: 30),
              ),
              ),
              const SizedBox(height: 20),
              Text('OpenDash Companion', style: t.textTheme.labelLarge?.copyWith(color: t.colorScheme.primary, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
            ],
            Text('Before you start', style: t.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5)),
            const SizedBox(height: 24),
            for (final (icon, text) in _points)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(icon, color: t.colorScheme.primary),
                      const SizedBox(width: 14),
                      Expanded(child: Text(text, style: t.textTheme.bodyLarge?.copyWith(height: 1.4))),
                    ]),
                  ),
                ),
              ),
            if (!widget.readOnly) ...[
              const SizedBox(height: 8),
              CheckboxListTile(
                value: _owner,
                onChanged: (v) => setState(() => _owner = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                title: const Text('I own this scooter and accept the above.'),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _owner ? () => ref.read(ackProvider.notifier).accept() : null,
                child: const Text('I understand'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
