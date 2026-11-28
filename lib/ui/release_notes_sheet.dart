import 'package:material_ui/material_ui.dart';

import '../releases/notes.dart';
import '../releases/release.dart';

Future<void> showReleaseNotes(BuildContext context, Release r, {String name = 'S1 Dash'}) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) {
        final t = Theme.of(c);
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          maxChildSize: 0.92,
          builder: (c, scroll) => ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
            children: [
              Text("What's new in $name ${r.version}", style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              if (r.published.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('Released ${r.published}', style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant)),
              ],
              const SizedBox(height: 20),
              NotesView(r.notes),
              if (r.url.isNotEmpty) ...[
                const SizedBox(height: 20),
                SelectableText(r.url, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
              ],
            ],
          ),
        );
      },
    );

/// Release notes, laid out from their markdown.
class NotesView extends StatelessWidget {
  const NotesView(this.notes, {super.key});
  final String notes;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final body = t.textTheme.bodyLarge?.copyWith(height: 1.5);
    final blocks = parseNotes(notes);
    if (blocks.isEmpty) return Text('No notes for this release.', style: body);

    final codeBg = t.colorScheme.surfaceContainerHighest;
    TextSpan rich(List<NoteSpan> spans, TextStyle? base) => TextSpan(
      style: base,
      children: [
        for (final s in spans)
          TextSpan(
            text: s.text,
            style: TextStyle(
              fontWeight: s.bold ? FontWeight.w700 : null,
              fontStyle: s.italic ? FontStyle.italic : null,
              fontFamily: s.code ? 'monospace' : null,
              backgroundColor: s.code ? codeBg : null,
            ),
          ),
      ],
    );

    Widget block(NoteBlock b) => switch (b) {
      NoteHeading(:final level, :final spans) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text.rich(
          rich(spans, (level <= 2 ? t.textTheme.titleLarge : t.textTheme.titleMedium)?.copyWith(fontWeight: FontWeight.w700)),
        ),
      ),
      NoteParagraph(:final spans) => Text.rich(rich(spans, body)),
      NoteBullet(:final marker, :final spans) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 28, child: Text(marker, style: body)),
          Expanded(child: Text.rich(rich(spans, body))),
        ],
      ),
      NoteCode(:final text) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: codeBg, borderRadius: BorderRadius.circular(8)),
        child: Text(text, style: t.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace')),
      ),
    };

    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < blocks.length; i++) ...[
            if (i > 0) SizedBox(height: blocks[i] is NoteBullet && blocks[i - 1] is NoteBullet ? 6 : 14),
            block(blocks[i]),
          ],
        ],
      ),
    );
  }
}
