import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:opendash_companion/ui/release_notes_sheet.dart';
import 'package:opendash_companion/releases/notes.dart';

String plain(List<NoteSpan> s) => s.map((x) => x.text).join();

void main() {
  test('headings, paragraphs and bullets', () {
    final b = parseNotes('# OpenDash 0.3.1\n\n**Fixed:** The lock screen\nno longer sticks.\n\n- one\n- two\n  continued\n');
    expect(b, hasLength(4));
    expect(b[0], isA<NoteHeading>().having((h) => h.level, 'level', 1));
    expect(plain(b[0].spans), 'OpenDash 0.3.1');
    expect(b[1], isA<NoteParagraph>());
    expect(plain(b[1].spans), 'Fixed: The lock screen no longer sticks.');
    expect(b[1].spans.first, isA<NoteSpan>().having((s) => s.bold, 'bold', true));
    expect(b[2], isA<NoteBullet>());
    expect(plain(b[3].spans), 'two continued');
  });

  test('numbered items keep their number', () {
    final b = parseNotes('1. first\n2. second');
    expect(b.map((x) => (x as NoteBullet).marker), ['1.', '2.']);
  });

  test('inline code, italics and links', () {
    final s = parseNotes('Run `adb` *now*, see [the guide](https://x.y) or https://a.b')[0].spans;
    expect(plain(s), 'Run adb now, see the guide or https://a.b');
    expect(s.firstWhere((x) => x.text == 'adb').code, isTrue);
    expect(s.firstWhere((x) => x.text == 'now').italic, isTrue);
  });

  test('snake_case and lone asterisks stay as written', () {
    expect(plain(parseNotes('set screen_off_timeout to 5 * 60')[0].spans), 'set screen_off_timeout to 5 * 60');
  });

  test('code fences, comments and rules', () {
    final b = parseNotes('<!-- generated -->\n```\nadb shell\n  x\n```\n---\n> quoted');
    expect(b, hasLength(2));
    expect((b[0] as NoteCode).text, 'adb shell\n  x');
    expect(plain(b[1].spans), 'quoted');
  });

  test('a GitHub generated-notes body', () {
    final b = parseNotes("## What's Changed\r\n* fix: x by @a in https://g/1\r\n\r\n**Full Changelog**: https://g/c");
    expect(plain(b[0].spans), "What's Changed");
    expect(b[1], isA<NoteBullet>());
    expect(plain(b[2].spans), 'Full Changelog: https://g/c');
  });

  test('empty notes give no blocks', () {
    expect(parseNotes('  \n\n'), isEmpty);
  });

  testWidgets('the sheet shows the notes without their markdown', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: NotesView('# OpenDash 0.3.1\n\n**Fixed:** stuck keypad\n\n- one'))));
    expect(find.textContaining('#'), findsNothing);
    expect(find.textContaining('**'), findsNothing);
    expect(find.text('OpenDash 0.3.1'), findsOneWidget);
    expect(find.text('Fixed: stuck keypad'), findsOneWidget);
    expect(find.text('•'), findsOneWidget);
  });

  testWidgets('empty notes say so', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: NotesView(''))));
    expect(find.text('No notes for this release.'), findsOneWidget);
  });
}
