import 'package:flutter_test/flutter_test.dart';
import 'package:denial_dart_shell/src/models/ime_frame.dart';

void main() {
  group('imePreeditCaretCodeUnitIndex', () {
    const spans = <DenialImePreeditSpan>[
      DenialImePreeditSpan(text: '你好'),
      DenialImePreeditSpan(text: '世界'),
    ];

    test('returns null for the contract -1 (no explicit caret)', () {
      expect(imePreeditCaretCodeUnitIndex(spans, -1), isNull);
    });

    test('maps a UTF-8 byte offset onto the right code unit', () {
      // '你' is 3 UTF-8 bytes: offset 3 sits before '好' at index 1.
      expect(imePreeditCaretCodeUnitIndex(spans, 3), 1);
      // Offset 6 lands on the span boundary — before '世' at index 2.
      expect(imePreeditCaretCodeUnitIndex(spans, 6), 2);
      // Past the last character.
      expect(imePreeditCaretCodeUnitIndex(spans, 12), 4);
      expect(imePreeditCaretCodeUnitIndex(spans, 0), 0);
    });

    test('snaps a mid-sequence offset back to the code-point boundary', () {
      // Offset 4 is inside '好' (bytes 3..5) — snaps back to before it.
      expect(imePreeditCaretCodeUnitIndex(spans, 4), 1);
      expect(imePreeditCaretCodeUnitIndex(spans, 5), 1);
    });

    test('clamps an over-long offset to the end', () {
      expect(imePreeditCaretCodeUnitIndex(spans, 4096), 4);
    });

    test('handles ASCII and surrogate pairs', () {
      const ascii = <DenialImePreeditSpan>[DenialImePreeditSpan(text: 'abc')];
      expect(imePreeditCaretCodeUnitIndex(ascii, 2), 2);

      // Emoji are surrogate pairs in UTF-16: '🙂' is 4 UTF-8 bytes and two
      // code units. A byte offset of 4 lands after it at index 2.
      const emoji = <DenialImePreeditSpan>[DenialImePreeditSpan(text: '🙂a')];
      expect(imePreeditCaretCodeUnitIndex(emoji, 4), 2);
      // Inside the emoji's byte sequence snaps to before it.
      expect(imePreeditCaretCodeUnitIndex(emoji, 2), 0);
    });
  });

  group('DenialImeFrame', () {
    test('empty frames collapse the panel', () {
      expect(const DenialImeFrame(serial: 1).isEmpty, isTrue);
      expect(
        const DenialImeFrame(
          serial: 1,
          preedit: <DenialImePreeditSpan>[DenialImePreeditSpan(text: '')],
        ).isEmpty,
        isTrue,
      );
      expect(const DenialImeFrame(serial: 1, notice: 'n').isEmpty, isFalse);
      expect(
        const DenialImeFrame(
          serial: 1,
          candidates: <DenialImeCandidate>[DenialImeCandidate(text: 'a')],
        ).isEmpty,
        isFalse,
      );
    });

    test('highlightedCandidate stays in range', () {
      const frame = DenialImeFrame(
        serial: 1,
        candidates: <DenialImeCandidate>[DenialImeCandidate(text: 'a')],
        highlighted: 0,
      );
      expect(frame.highlightedCandidate?.text, 'a');
      expect(
        const DenialImeFrame(
          serial: 1,
          candidates: <DenialImeCandidate>[DenialImeCandidate(text: 'a')],
          highlighted: -1,
        ).highlightedCandidate,
        isNull,
      );
    });

    test('preeditCaretCodeUnitIndex proxies the byte offset', () {
      const frame = DenialImeFrame(
        serial: 1,
        preedit: <DenialImePreeditSpan>[DenialImePreeditSpan(text: '你好')],
        preeditCursor: 3,
      );
      expect(frame.preeditCaretCodeUnitIndex, 1);
      expect(frame.preeditText, '你好');
    });
  });
}
