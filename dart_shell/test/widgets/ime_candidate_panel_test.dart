import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:denial_dart_shell/src/models/ime_frame.dart';
import 'package:denial_dart_shell/src/theme/shell_theme.dart';
import 'package:denial_dart_shell/src/widgets/ime/ime_candidate_panel.dart';
import 'package:denial_dart_shell/src/widgets/ime/ime_panel_placement.dart';

Widget _panelHost(
  DenialImeFrame frame, {
  ImePanelLayout layout = ImePanelLayout.vertical,
  ValueChanged<int>? onCandidateSelected,
}) {
  return ProviderScope(
    child: MaterialApp(
      home: ShellTheme(
        data: const ShellThemeData(),
        child: Scaffold(
          body: Center(
            child: ImeCandidatePanel(
              frame: frame,
              layout: layout,
              onCandidateSelected: onCandidateSelected,
            ),
          ),
        ),
      ),
    ),
  );
}

const _candidates = <DenialImeCandidate>[
  DenialImeCandidate(text: '你好', annotation: 'hello'),
  DenialImeCandidate(text: '尼号'),
  DenialImeCandidate(text: '泥嚎', annotation: 'typo of 你好'),
];

void _collectSpans(InlineSpan span, List<TextSpan> out) {
  if (span is TextSpan) {
    out.add(span);
    span.children?.forEach((child) => _collectSpans(child, out));
  }
}

void main() {
  testWidgets('vertical layout renders number, word, annotation', (
    tester,
  ) async {
    await tester.pumpWidget(
      _panelHost(
        const DenialImeFrame(
          serial: 1,
          candidates: _candidates,
          highlighted: 0,
          pageCount: 1,
        ),
      ),
    );

    expect(find.byKey(imeCandidatePanelKey), findsOneWidget);
    for (var index = 0; index < _candidates.length; index += 1) {
      final row = find.byKey(imeCandidateRowKey(index));
      expect(row, findsOneWidget);
      expect(
        find.descendant(of: row, matching: find.text('${index + 1}')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.text(_candidates[index].text)),
        findsOneWidget,
      );
      final annotation = _candidates[index].annotation;
      expect(
        find.descendant(of: row, matching: find.text(annotation ?? '∅')),
        annotation == null ? findsNothing : findsOneWidget,
      );
    }
    // No page indicator for a single page, and empty annotations leave no
    // placeholder row or spacer behind.
    expect(find.byKey(imePageIndicatorKey), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(imeCandidateRowKey(1)),
        matching: find.byType(Spacer),
      ),
      findsNothing,
    );
  });

  testWidgets('highlighted candidate paints the accent pill', (tester) async {
    const theme = ShellThemeData();
    await tester.pumpWidget(
      _panelHost(
        const DenialImeFrame(
          serial: 1,
          candidates: _candidates,
          highlighted: 1,
          pageCount: 1,
        ),
      ),
    );

    final highlighted = tester.widget<Container>(
      find.descendant(
        of: find.byKey(imeCandidateRowKey(1)),
        matching: find.byType(Container),
      ),
    );
    final decoration = highlighted.decoration! as BoxDecoration;
    expect(decoration.color, theme.accentPalette.subtle);

    final plain = tester.widget<Container>(
      find.descendant(
        of: find.byKey(imeCandidateRowKey(0)),
        matching: find.byType(Container),
      ),
    );
    expect((plain.decoration as BoxDecoration?)?.color, isNull);
  });

  testWidgets('tone=fresh candidate gets the fixed orange teaching dot', (
    tester,
  ) async {
    await tester.pumpWidget(
      _panelHost(
        const DenialImeFrame(
          serial: 1,
          candidates: <DenialImeCandidate>[
            DenialImeCandidate(text: '生词', toneMark: true),
            DenialImeCandidate(text: '熟词'),
          ],
          pageCount: 1,
        ),
      ),
    );

    final dot = tester.widget<Container>(find.byKey(imeToneMarkKey(0)));
    expect((dot.decoration! as BoxDecoration).color, imeFreshToneColor);
    expect(find.byKey(imeToneMarkKey(1)), findsNothing);
  });

  testWidgets('cloud-sourced candidate carries the cloud badge', (
    tester,
  ) async {
    await tester.pumpWidget(
      _panelHost(
        const DenialImeFrame(
          serial: 1,
          candidates: <DenialImeCandidate>[
            DenialImeCandidate(text: '本地'),
            DenialImeCandidate(text: '云端', fromCloud: true),
          ],
          pageCount: 1,
        ),
      ),
    );

    final icon = tester.widget<Icon>(find.byKey(imeCloudBadgeKey(1)));
    expect(icon.icon, Icons.cloud_outlined);
    expect(find.byKey(imeCloudBadgeKey(0)), findsNothing);
  });

  testWidgets('preedit renders styled spans and the byte-offset caret', (
    tester,
  ) async {
    await tester.pumpWidget(
      _panelHost(
        const DenialImeFrame(
          serial: 1,
          preedit: <DenialImePreeditSpan>[
            DenialImePreeditSpan(
              text: 'ni',
              style: DenialImePreeditStyle.underline,
            ),
            // Correction segment: deleted/replaced text keeps a deletion
            // line instead of vanishing silently.
            DenialImePreeditSpan(
              text: 'hao',
              style: DenialImePreeditStyle.correction,
            ),
            DenialImePreeditSpan(
              text: 'ma',
              style: DenialImePreeditStyle.prediction,
            ),
          ],
          // Byte offset 2 sits between 'ni' and 'hao'.
          preeditCursor: 2,
          candidates: _candidates,
          pageCount: 1,
        ),
      ),
    );

    final preedit = tester.widget<Text>(find.byKey(imePreeditKey));
    final spans = <TextSpan>[];
    _collectSpans(preedit.textSpan!, spans);

    final underline = spans.firstWhere((span) => span.text == 'ni');
    expect(underline.style?.decoration, TextDecoration.underline);
    final correction = spans.firstWhere((span) => span.text == 'hao');
    expect(correction.style?.decoration, TextDecoration.lineThrough);
    final prediction = spans.firstWhere((span) => span.text == 'ma');
    expect(prediction.style?.decoration, TextDecoration.none);
    // The caret renders inline at the byte-offset position.
    expect(find.byKey(imePreeditCaretKey), findsOneWidget);
  });

  testWidgets('preedit caret is absent when the frame reports none', (
    tester,
  ) async {
    await tester.pumpWidget(
      _panelHost(
        const DenialImeFrame(
          serial: 1,
          preedit: <DenialImePreeditSpan>[DenialImePreeditSpan(text: 'ni')],
          preeditCursor: -1,
          candidates: _candidates,
          pageCount: 1,
        ),
      ),
    );
    expect(find.byKey(imePreeditKey), findsOneWidget);
    expect(find.byKey(imePreeditCaretKey), findsNothing);
  });

  testWidgets('completion preview and notice render in order', (tester) async {
    await tester.pumpWidget(
      _panelHost(
        const DenialImeFrame(
          serial: 1,
          preedit: <DenialImePreeditSpan>[
            DenialImePreeditSpan(
              text: 'ni',
              style: DenialImePreeditStyle.underline,
            ),
          ],
          candidates: _candidates,
          pageCount: 1,
          completion: '你好世界',
          notice: 'cloud suggestions offline',
        ),
      ),
    );

    expect(find.byKey(imeCompletionKey), findsOneWidget);
    expect(find.text('你好世界'), findsOneWidget);
    expect(find.byKey(imeNoticeKey), findsOneWidget);
    expect(find.text('cloud suggestions offline'), findsOneWidget);
  });

  testWidgets('an empty frame collapses the panel', (tester) async {
    await tester.pumpWidget(_panelHost(const DenialImeFrame(serial: 1)));
    expect(find.byKey(imeCandidatePanelKey), findsNothing);
    expect(find.byKey(imePreeditKey), findsNothing);
  });

  testWidgets('page indicator shows only when paging', (tester) async {
    await tester.pumpWidget(
      _panelHost(
        const DenialImeFrame(
          serial: 1,
          candidates: _candidates,
          pageIndex: 1,
          pageCount: 3,
        ),
      ),
    );
    expect(find.byKey(imePageIndicatorKey), findsOneWidget);
    expect(find.text('2/3'), findsOneWidget);
  });

  testWidgets('long annotations ellipsize instead of overflowing', (
    tester,
  ) async {
    await tester.pumpWidget(
      _panelHost(
        const DenialImeFrame(
          serial: 1,
          candidates: <DenialImeCandidate>[
            DenialImeCandidate(
              text: '词',
              annotation: 'a very long annotation that must truncate',
            ),
          ],
          pageCount: 1,
        ),
      ),
    );
    final annotation = tester.widget<Text>(
      find.text('a very long annotation that must truncate'),
    );
    expect(annotation.maxLines, 1);
    expect(annotation.overflow, TextOverflow.ellipsis);
  });

  testWidgets('horizontal layout keeps annotations on their own line', (
    tester,
  ) async {
    await tester.pumpWidget(
      _panelHost(
        const DenialImeFrame(
          serial: 1,
          candidates: _candidates,
          highlighted: 0,
          pageIndex: 0,
          pageCount: 2,
        ),
        layout: ImePanelLayout.horizontal,
      ),
    );

    for (var index = 0; index < _candidates.length; index += 1) {
      expect(find.byKey(imeCandidateRowKey(index)), findsOneWidget);
    }
    // The highlighted item's annotation lives on a separate line, not
    // inside the chip row.
    expect(find.byKey(imeHighlightedAnnotationKey), findsOneWidget);
    expect(find.text('hello'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(imeCandidateRowKey(0)),
        matching: find.text('hello'),
      ),
      findsNothing,
    );
    // Page number sits at the end of the chip row.
    expect(find.byKey(imePageIndicatorKey), findsOneWidget);
  });

  testWidgets('tapping a row reports its selection index', (tester) async {
    var selected = -1;
    await tester.pumpWidget(
      _panelHost(
        const DenialImeFrame(serial: 1, candidates: _candidates, pageCount: 1),
        onCandidateSelected: (index) => selected = index,
      ),
    );
    await tester.tap(find.byKey(imeCandidateRowKey(2)));
    expect(selected, 2);
  });

  group('resolveImePanelPlacement', () {
    const bounds = Rect.fromLTWH(0, 0, 800, 600);
    const panel = Size(240, 120);
    const caret = Rect.fromLTWH(100, 100, 1, 20);

    test('prefers below-caret placement', () {
      final placement = resolveImePanelPlacement(
        caret: caret,
        panelSize: panel,
        bounds: bounds,
        gap: 4,
      );
      expect(placement.aboveCaret, isFalse);
      expect(placement.rect.top, caret.bottom + 4);
      expect(placement.rect.left, caret.left);
    });

    test('flips above the caret when the space below does not fit', () {
      final placement = resolveImePanelPlacement(
        caret: const Rect.fromLTWH(100, 560, 1, 20),
        panelSize: panel,
        bounds: bounds,
        gap: 4,
      );
      expect(placement.aboveCaret, isTrue);
      expect(placement.rect.bottom, 560 - 4);
    });

    test('clamps horizontally at the output edge', () {
      final placement = resolveImePanelPlacement(
        caret: const Rect.fromLTWH(760, 100, 1, 20),
        panelSize: panel,
        bounds: bounds,
      );
      expect(placement.rect.right, bounds.right);
    });

    test('clamps vertically when neither side fits fully', () {
      // 500px-tall panel under a caret at y=500 can only fit clamped.
      final placement = resolveImePanelPlacement(
        caret: const Rect.fromLTWH(100, 500, 1, 20),
        panelSize: const Size(200, 500),
        bounds: bounds,
      );
      expect(placement.rect.top, greaterThanOrEqualTo(bounds.top));
      expect(placement.rect.bottom, lessThanOrEqualTo(bounds.bottom));
      expect(placement.rect.height, 500);
    });

    test('an oversized panel is constrained to the bounds', () {
      final placement = resolveImePanelPlacement(
        caret: caret,
        panelSize: const Size(2000, 2000),
        bounds: bounds,
      );
      expect(placement.rect, bounds);
    });

    test('respects a non-zero output origin', () {
      const shifted = Rect.fromLTWH(1920, 0, 800, 600);
      final placement = resolveImePanelPlacement(
        caret: const Rect.fromLTWH(2650, 100, 1, 20),
        panelSize: panel,
        bounds: shifted,
      );
      expect(placement.rect.right, shifted.right);
      expect(placement.rect.left, greaterThanOrEqualTo(shifted.left));
    });
  });
}
