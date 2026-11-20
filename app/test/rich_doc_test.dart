import 'package:flutter_test/flutter_test.dart';

import 'package:dreamtx/widgets/rich_doc.dart';

/// The rich-doc model's edit transforms — the contract the Text Box flow
/// is built on: marks move the way a text editor moves them.
void main() {
  group('json round-trip', () {
    test('empty doc serializes lean', () {
      final j = RichDoc().toJson();
      expect(j['text'], '');
      expect(j.containsKey('runs'), isFalse);
      expect(j.containsKey('paras'), isFalse);
      expect(j.containsKey('valign'), isFalse);
      expect(j.containsKey('autofit'), isFalse);
    });

    test('full doc survives a round trip', () {
      final doc = RichDoc(text: 'Hello\nworld');
      doc.toggleFlag(0, 5, 'bold');
      doc.setAttr(6, 11, 'color', 'FF0099');
      doc.setAttr(6, 11, 'highlight', 'FFE08A');
      doc.setParagraphAttr(0, 0, 'align', 'center');
      doc.setParagraphAttr(0, 0, 'list', 'bullet');
      doc.setParagraphAttr(0, 0, 'line_spacing', 1.5);
      doc.valign = 'middle';
      doc.autofit = 'shrink';
      final back = RichDoc.fromJson(doc.toJson());
      expect(back.text, 'Hello\nworld');
      expect(back.runs, hasLength(2));
      expect(back.runs[0].bold, isTrue);
      expect(back.runs[1].color, 'FF0099');
      expect(back.runs[1].highlight, 'FFE08A');
      expect(back.paras, hasLength(1));
      expect(back.paras[0].align, 'center');
      expect(back.paras[0].list, 'bullet');
      expect(back.paras[0].lineSpacing, 1.5);
      expect(back.valign, 'middle');
      expect(back.autofit, 'shrink');
    });
  });

  group('typing edits move the marks', () {
    test('typing inside a bold run extends it', () {
      final doc = RichDoc(text: 'hello');
      doc.toggleFlag(0, 5, 'bold');
      // type 'X' at offset 2 -> 'heXllo'
      doc.edit('heXllo');
      expect(doc.runs, hasLength(1));
      expect(doc.runs[0].start, 0);
      expect(doc.runs[0].end, 6);
      expect(doc.runs[0].bold, isTrue);
    });

    test('typing after an unformatted region stays unformatted', () {
      final doc = RichDoc(text: 'ab');
      doc.toggleFlag(0, 2, 'bold');
      // type at offset 0 — before the run — text is plain, run shifts
      doc.edit('Xab');
      expect(doc.runs, hasLength(1));
      expect(doc.runs[0].start, 1);
      expect(doc.runs[0].end, 3);
    });

    test('a pending caret mark formats what I type next', () {
      final doc = RichDoc(text: 'ab');
      // caret at 2, tap Bold (collapsed) — a pending zero-width mark
      doc.toggleFlag(2, 2, 'bold');
      expect(doc.runs.where((r) => r.end > r.start), isEmpty);
      // now type 'cd' at the caret
      doc.edit('abcd');
      expect(doc.runs, hasLength(1));
      final typed = doc.runs[0];
      expect(typed.start, 2);
      expect(typed.end, 4);
      expect(typed.bold, isTrue);
    });

    test('toggling bold off at the caret turns typing off', () {
      final doc = RichDoc(text: 'ab');
      doc.toggleFlag(0, 2, 'bold');
      // caret at 2 (end of the bold run): toolbar shows bold ACTIVE
      expect(doc.isFlagActive(2, 2, 'bold'), isTrue);
      doc.toggleFlag(2, 2, 'bold'); // toggle off
      doc.edit('abc'); // type 'c'
      expect(doc.text, 'abc');
      expect(doc.runs, hasLength(2));
      expect(doc.runs[0].start, 0);
      expect(doc.runs[0].end, 2);
      expect(doc.runs[0].bold, isTrue);
      expect(doc.runs[1].start, 2);
      expect(doc.runs[1].end, 3);
      expect(doc.runs[1].bold, isFalse, reason: 'the typed char is NOT bold');
    });

    test('replacing a formatted selection inherits the formatting', () {
      final doc = RichDoc(text: 'abcdefgh');
      doc.toggleFlag(2, 6, 'italic');
      // select [2,6), type 'XY'
      doc.edit('abXYgh');
      expect(doc.runs, hasLength(1));
      expect(doc.runs[0].start, 2);
      expect(doc.runs[0].end, 4);
      expect(doc.runs[0].italic, isTrue);
    });

    test('deleting a run\'s text deletes the run', () {
      final doc = RichDoc(text: 'abcdefgh');
      doc.toggleFlag(2, 6, 'bold');
      doc.edit('abgh'); // delete [2,6)
      expect(doc.runs, isEmpty);
    });

    test('deleting part of a run trims it', () {
      final doc = RichDoc(text: 'abcdefgh');
      doc.toggleFlag(2, 6, 'bold');
      doc.edit('abcfgh'); // delete [3,5) — 'de'
      expect(doc.text, 'abcfgh');
      expect(doc.runs, hasLength(1));
      expect(doc.runs[0].start, 2);
      expect(doc.runs[0].end, 4);
    });

    test('zero-width pending marks never serialize', () {
      final doc = RichDoc(text: 'ab');
      doc.toggleFlag(1, 1, 'bold');
      expect(doc.toJson().containsKey('runs'), isFalse);
    });
  });

  group('paragraph edits', () {
    test('splitting a styled paragraph inherits the anchor', () {
      final doc = RichDoc(text: 'one two');
      doc.setParagraphAttr(0, 0, 'align', 'center');
      // press Enter at offset 4 -> 'one \ntwo'
      doc.edit('one \ntwo');
      expect(doc.text, 'one \ntwo');
      expect(doc.paragraphStarts, [0, 5]);
      // The original anchor stays; the NEW paragraph inherits its style.
      expect(doc.paras, hasLength(2));
      expect(doc.paras[0].start, 0);
      expect(doc.paras[0].align, 'center');
      expect(doc.paras[1].start, 5);
      expect(doc.paras[1].align, 'center');
    });

    test('deleting the newline merges paragraphs, earlier style wins',
        () {
      final doc = RichDoc(text: 'one\ntwo');
      doc.setParagraphAttr(0, 0, 'align', 'center');
      // set the second paragraph right-aligned via its own anchor at 4
      doc.paras.add(RichPara(start: 4)..setAttribute('align', 'right'));
      // delete the newline at 3
      doc.edit('onetwo');
      expect(doc.paras, hasLength(1));
      expect(doc.paras[0].start, 0);
      expect(doc.paras[0].align, 'center', reason: 'the earlier paragraph wins');
    });

    test('toggleList applies to the caret\'s paragraph', () {
      final doc = RichDoc(text: 'one\ntwo');
      doc.toggleList(0, 0, 'bullet');
      expect(doc.paras[0].list, 'bullet');
      // the second paragraph is untouched
      expect(doc.effectiveParaAt(4)?.list, anyOf(isNull, 'none'));
      // toggling again turns it off
      doc.toggleList(0, 0, 'bullet');
      expect(doc.effectiveParaAt(0)?.list ?? 'none', 'none');
    });

    test('indent and outdent clamp at zero', () {
      final doc = RichDoc(text: 'one');
      doc.indentBy(0, 0, -1);
      expect(doc.effectiveParaAt(0)?.indent ?? 0, 0);
      doc.indentBy(0, 0, 1);
      expect(doc.effectiveParaAt(0)?.indent, 1);
    });
  });

  group('range formatting', () {
    test('formatting a sub-range splits the run', () {
      final doc = RichDoc(text: 'abcdefgh');
      doc.toggleFlag(0, 8, 'bold');
      doc.setAttr(3, 5, 'color', 'FF0099');
      expect(doc.runs, hasLength(3));
      expect(doc.runs[1].color, 'FF0099');
      expect(doc.runs[0].bold, isTrue);
      expect(doc.runs[1].bold, isTrue);
    });

    test('clearRange strips marks back to the theme', () {
      final doc = RichDoc(text: 'abcdefgh');
      doc.toggleFlag(0, 8, 'bold');
      doc.setAttr(0, 8, 'color', 'FF0099');
      doc.clearRange(2, 6);
      expect(doc.runs, hasLength(2));
      expect(doc.runs[0].end, 2);
      expect(doc.runs[1].start, 6);
    });

    test('isFlagActive requires full coverage', () {
      final doc = RichDoc(text: 'abcdefgh');
      doc.toggleFlag(0, 4, 'bold');
      expect(doc.isFlagActive(0, 4, 'bold'), isTrue);
      expect(doc.isFlagActive(0, 8, 'bold'), isFalse);
      expect(doc.isFlagActive(4, 4, 'bold'), isTrue);
      expect(doc.isFlagActive(6, 6, 'bold'), isFalse);
    });
  });
}
