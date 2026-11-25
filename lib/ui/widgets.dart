import 'package:material_ui/material_ui.dart';

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 28, 4, 10),
      child: Row(children: [
        Expanded(
          child: Text(text.toUpperCase(),
              style: t.textTheme.labelMedium?.copyWith(color: t.colorScheme.onSurfaceVariant, letterSpacing: 1.4, fontWeight: FontWeight.w700)),
        ),
        ?trailing,
      ]),
    );
  }
}

class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key, this.valueColor});
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Expanded(child: Text(label, style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant))),
        Text(value, style: t.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600, color: valueColor)),
      ]),
    );
  }
}

/// A tinted card for one message: an update, a warning, an error.
class Notice extends StatelessWidget {
  const Notice({super.key, required this.icon, required this.title, this.body, this.color, this.actions = const []});
  final IconData icon;
  final String title;
  final String? body;
  final Color? color;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = color ?? t.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: 0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: c, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              if (body != null) ...[
                const SizedBox(height: 4),
                Text(body!, style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant)),
              ],
            ]),
          ),
        ]),
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.end, children: actions),
        ],
      ]),
    );
  }
}

/// Answers true only when the rider taps [confirm].
Future<bool> confirm(BuildContext context,
    {required String title, required String body, required String confirm, bool danger = false}) async {
  final t = Theme.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(child: Text(body)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(c, true),
          child: Text(confirm, style: TextStyle(color: danger ? t.colorScheme.error : t.colorScheme.primary, fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
  return ok ?? false;
}

const kParkedWarning = 'Do this only while the scooter is parked — the dashboard restarts.';
