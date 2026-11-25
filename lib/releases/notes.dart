/// Release notes are GitHub markdown. This reads the part of it release notes
/// use (headings, paragraphs, lists, code, bold, italics, links) into blocks
/// the sheet can lay out, so a rider sees "Fixed:" in bold, not "**Fixed:**".
/// Anything else stays as written.
library;

class NoteSpan {
  const NoteSpan(this.text, {this.bold = false, this.italic = false, this.code = false});
  final String text;
  final bool bold;
  final bool italic;
  final bool code;
}

sealed class NoteBlock {
  const NoteBlock(this.spans);
  final List<NoteSpan> spans;
}

class NoteHeading extends NoteBlock {
  const NoteHeading(this.level, super.spans);
  final int level;
}

class NoteParagraph extends NoteBlock {
  const NoteParagraph(super.spans);
}

class NoteBullet extends NoteBlock {
  const NoteBullet(this.marker, super.spans);

  /// '•' for an unordered item, '1.' and so on for a numbered one.
  final String marker;
}

class NoteCode extends NoteBlock {
  NoteCode(this.text) : super([NoteSpan(text, code: true)]);
  final String text;
}

final _heading = RegExp(r'^(#{1,6})\s+(.*?)\s*#*\s*$');
final _bullet = RegExp(r'^\s{0,3}[-*+]\s+(.*)$');
final _numbered = RegExp(r'^\s{0,3}(\d{1,3})[.)]\s+(.*)$');
final _rule = RegExp(r'^\s{0,3}([-*_])(\s*\1){2,}\s*$');
final _fence = RegExp(r'^\s{0,3}(```|~~~)');
final _comment = RegExp(r'<!--.*?-->', dotAll: true);

List<NoteBlock> parseNotes(String md) {
  final lines = md.replaceAll(_comment, '').replaceAll('\r\n', '\n').split('\n');
  final out = <NoteBlock>[];
  final para = <String>[];
  String? itemMarker;
  final item = <String>[];

  void flush() {
    if (para.isNotEmpty) out.add(NoteParagraph(parseInline(para.join(' '))));
    if (itemMarker != null) out.add(NoteBullet(itemMarker!, parseInline(item.join(' '))));
    para.clear();
    item.clear();
    itemMarker = null;
  }

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final fence = _fence.firstMatch(line);
    if (fence != null) {
      flush();
      final code = <String>[];
      for (i++; i < lines.length && !lines[i].trimLeft().startsWith(fence.group(1)!); i++) {
        code.add(lines[i]);
      }
      out.add(NoteCode(code.join('\n')));
      continue;
    }
    if (line.trim().isEmpty || _rule.hasMatch(line)) {
      flush();
      continue;
    }
    final h = _heading.firstMatch(line);
    if (h != null) {
      flush();
      out.add(NoteHeading(h.group(1)!.length, parseInline(h.group(2)!)));
      continue;
    }
    final b = _bullet.firstMatch(line);
    final n = b == null ? _numbered.firstMatch(line) : null;
    if (b != null || n != null) {
      flush();
      itemMarker = b != null ? '•' : '${n!.group(1)}.';
      item.add((b?.group(1) ?? n!.group(2))!.trim());
      continue;
    }
    final text = line.trim().replaceFirst(RegExp(r'^>\s?'), '');
    if (itemMarker != null) {
      item.add(text);
    } else {
      para.add(text);
    }
  }
  flush();
  return out;
}

// `code`, **bold** / __bold__, *italic*, [text](url). An underscore inside a
// word (screen_off_timeout) and a lone asterisk (5 * 60) are left alone.
final _inline = RegExp(r'`([^`]+)`|\*\*(.+?)\*\*|__(.+?)__|(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])|\[([^\]]+)\]\(([^)\s]+)\)');

List<NoteSpan> parseInline(String s) {
  final out = <NoteSpan>[];
  var at = 0;
  for (final m in _inline.allMatches(s)) {
    if (m.start > at) out.add(NoteSpan(s.substring(at, m.start)));
    if (m.group(1) != null) {
      out.add(NoteSpan(m.group(1)!, code: true));
    } else if (m.group(2) != null || m.group(3) != null) {
      out.add(NoteSpan(m.group(2) ?? m.group(3)!, bold: true));
    } else if (m.group(4) != null) {
      out.add(NoteSpan(m.group(4)!, italic: true));
    } else {
      out.add(NoteSpan(m.group(5)!));
    }
    at = m.end;
  }
  if (at < s.length) out.add(NoteSpan(s.substring(at)));
  return out;
}
