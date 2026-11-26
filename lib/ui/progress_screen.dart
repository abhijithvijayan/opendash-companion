import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' hide StepState;
import 'package:url_launcher/url_launcher.dart';

import '../scooter/operations.dart';
import '../state/providers.dart';

class ProgressScreen extends ConsumerWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final op = ref.watch(operationProvider);
    final t = Theme.of(context);
    if (op == null) return const Scaffold();
    final running = op.running;
    final warned = op.steps.any((s) => s.state == StepState.warning);
    return PopScope(
      canPop: !running,
      child: Scaffold(
        appBar: AppBar(title: Text(op.title), automaticallyImplyLeading: !running),
        body: SafeArea(
          child: Column(children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                children: [
                  _Headline(running: running, failed: op.failed, warned: warned),
                  const SizedBox(height: 20),
                  Card(
                    child: Column(children: [
                      for (final (i, s) in op.steps.indexed) ...[
                        if (i > 0) const Divider(indent: 56),
                        _StepRow(s),
                      ],
                    ]),
                  ),
                  if (running) ...[
                    const SizedBox(height: 16),
                    Text('Keep the phone and the scooter on the same network until this finishes.',
                        style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant), textAlign: TextAlign.center),
                  ],
                  if (!running && op.failed && op.manual != null) ...[
                    const SizedBox(height: 16),
                    Text(op.manual!.hint,
                        style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant), textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.open_in_new_rounded),
                      label: const Text('Download from GitHub'),
                      onPressed: () => launchUrl(Uri.parse(op.manual!.url), mode: LaunchMode.externalApplication).catchError((_) => false),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: FilledButton(
                onPressed: running
                    ? null
                    : () {
                        ref.read(operationProvider.notifier).clear();
                        Navigator.of(context).pop();
                      },
                child: Text(running ? 'Working…' : 'Done'),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Headline extends StatelessWidget {
  const _Headline({required this.running, required this.failed, required this.warned});
  final bool running, failed, warned;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final (icon, color, text) = running
        ? (Icons.sync_rounded, t.colorScheme.primary, 'Working on your scooter')
        : failed
            ? (Icons.error_outline_rounded, t.colorScheme.error, "That didn't finish")
            : warned
                ? (Icons.check_circle_outline_rounded, t.colorScheme.tertiary, 'Done, with a note')
                : (Icons.check_circle_rounded, t.colorScheme.primary, 'All done');
    return Row(children: [
      Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.14), shape: BoxShape.circle),
        child: running ? Padding(padding: const EdgeInsets.all(13), child: CircularProgressIndicator(strokeWidth: 2.5, color: color)) : Icon(icon, color: color),
      ),
      const SizedBox(width: 14),
      Expanded(child: Text(text, style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700))),
    ]);
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow(this.step);
  final OpStep step;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final Widget lead = switch (step.state) {
      StepState.waiting => Icon(Icons.radio_button_unchecked_rounded, color: cs.outline),
      StepState.running => SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: cs.primary)),
      StepState.done => Icon(Icons.check_circle_rounded, color: cs.primary),
      StepState.warning => Icon(Icons.warning_amber_rounded, color: cs.tertiary),
      StepState.failed => Icon(Icons.cancel_rounded, color: cs.error),
    };
    final detailColor = step.state == StepState.failed ? cs.error : cs.tertiary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 24, child: Center(child: lead)),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(step.label,
                style: t.textTheme.bodyLarge?.copyWith(
                    fontWeight: step.state == StepState.running ? FontWeight.w700 : FontWeight.w500,
                    color: step.state == StepState.waiting ? cs.onSurfaceVariant : cs.onSurface)),
            if (step.progress != null) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: step.progress, minHeight: 6, backgroundColor: cs.surfaceContainerHigh),
              ),
              const SizedBox(height: 4),
              Text('${(step.progress! * 100).round()}%', style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ],
            if (step.detail != null) ...[
              const SizedBox(height: 4),
              Text(step.detail!, style: t.textTheme.bodyMedium?.copyWith(color: detailColor)),
            ],
          ]),
        ),
      ]),
    );
  }
}
