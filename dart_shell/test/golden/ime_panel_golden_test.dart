import 'package:denial_dart_shell/src/models/display_layout.dart';
import 'package:denial_dart_shell/src/models/ime_frame.dart';
import 'package:denial_dart_shell/src/platform/denial_bridge.dart';
import 'package:denial_dart_shell/src/state/display_layout.dart';
import 'package:denial_dart_shell/src/state/ime_panel.dart';
import 'package:denial_dart_shell/src/state/shell_controller.dart';
import 'package:denial_dart_shell/src/state/shell_state.dart';
import 'package:denial_dart_shell/src/theme/shell_theme.dart';
import 'package:denial_dart_shell/src/widgets/ime/ime_candidate_panel.dart';
import 'package:denial_dart_shell/src/widgets/ime/ime_panel_layer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _ImeGoldenBridge extends DenialBridge {}

class _FixedImePanel extends ImePanelController {
  _FixedImePanel(this._initial);

  final ImePanelState _initial;

  @override
  ImePanelState build() => _initial;
}

class _FixedDisplayLayout extends DisplayLayoutController {
  @override
  DisplayLayout? build() => null;
}

class _GoldenShellController extends ShellController {
  // A fixed empty state keeps the real build()'s window-list refresh (and
  // its reply timeout timer) out of golden tests.
  @override
  ShellState build() => ShellState.initial();
}

const _engine = DenialImeState(
  serial: 3,
  engine: DenialImeEngineStatus.ready,
  endpoint: DenialImeEndpointKind.waylandTextInput,
  mode: DenialImeInputMode.chinese,
);

Widget _panelHost(
  DenialImeFrame frame, {
  ImePanelLayout layout = ImePanelLayout.vertical,
}) {
  return ProviderScope(
    child: MaterialApp(
      home: Scaffold(
        backgroundColor: const Color(0xff121212),
        body: Center(
          child: ShellTheme(
            data: const ShellThemeData(),
            child: ImeCandidatePanel(frame: frame, layout: layout),
          ),
        ),
      ),
    ),
  );
}

/// Candidates exercising every row affordance: tone mark (fixed semantic
/// orange), cloud badge, long annotation truncation, plain rows.
const _candidates = <DenialImeCandidate>[
  DenialImeCandidate(text: '你好', annotation: 'hello', toneMark: true),
  DenialImeCandidate(text: '尼号', annotation: 'from cloud', fromCloud: true),
  DenialImeCandidate(text: '泥嚎'),
  DenialImeCandidate(
    text: '逆转',
    annotation:
        'an extremely long annotation that must ellipsize instead of '
        'pushing the panel wider than its output bound',
  ),
];

void main() {
  testWidgets('vertical layout: preedit, caret, badges, highlight, paging', (
    tester,
  ) async {
    await tester.pumpWidget(
      _panelHost(
        const DenialImeFrame(
          serial: 3,
          preedit: <DenialImePreeditSpan>[
            DenialImePreeditSpan(
              text: 'ni',
              style: DenialImePreeditStyle.underline,
            ),
            DenialImePreeditSpan(
              text: 'hao',
              style: DenialImePreeditStyle.prediction,
            ),
          ],
          preeditCursor: 2,
          candidates: _candidates,
          highlighted: 0,
          pageIndex: 1,
          pageCount: 5,
        ),
      ),
    );

    await expectLater(
      find.byType(ImeCandidatePanel),
      matchesGoldenFile('goldens/ime_panel_vertical.png'),
    );
  });

  testWidgets('horizontal layout: chip row, annotation line, page tail', (
    tester,
  ) async {
    await tester.pumpWidget(
      _panelHost(
        const DenialImeFrame(
          serial: 3,
          preedit: <DenialImePreeditSpan>[
            DenialImePreeditSpan(
              text: 'nihao',
              style: DenialImePreeditStyle.underline,
            ),
          ],
          candidates: _candidates,
          highlighted: 1,
          pageIndex: 0,
          pageCount: 3,
        ),
        layout: ImePanelLayout.horizontal,
      ),
    );

    await expectLater(
      find.byType(ImeCandidatePanel),
      matchesGoldenFile('goldens/ime_panel_horizontal.png'),
    );
  });

  testWidgets('preedit correction strikethrough, completion ghost, notice', (
    tester,
  ) async {
    await tester.pumpWidget(
      _panelHost(
        const DenialImeFrame(
          serial: 3,
          preedit: <DenialImePreeditSpan>[
            DenialImePreeditSpan(
              text: 'shi',
              style: DenialImePreeditStyle.underline,
            ),
            // Corrected segment keeps its deletion line.
            DenialImePreeditSpan(
              text: 'de',
              style: DenialImePreeditStyle.correction,
            ),
            DenialImePreeditSpan(
              text: 'ji',
              style: DenialImePreeditStyle.prediction,
            ),
          ],
          preeditCursor: 3,
          candidates: _candidates,
          highlighted: 2,
          pageCount: 1,
          completion: '是的设计',
          notice: 'cloud suggestions offline',
        ),
      ),
    );

    await expectLater(
      find.byType(ImeCandidatePanel),
      matchesGoldenFile('goldens/ime_panel_preedit_features.png'),
    );
  });

  testWidgets('edge-flip: panel anchors above a caret near the output edge', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          denialBridgeProvider.overrideWithValue(_ImeGoldenBridge()),
          imePanelProvider.overrideWith(
            () => _FixedImePanel(
              const ImePanelState(
                frame: DenialImeFrame(
                  serial: 3,
                  candidates: _candidates,
                  highlighted: 0,
                  pageCount: 1,
                  // Caret hugs the bottom edge of the 800x600 test canvas.
                  caret: Rect.fromLTWH(120, 560, 1, 20),
                ),
                engine: _engine,
              ),
            ),
          ),
          displayLayoutProvider.overrideWith(_FixedDisplayLayout.new),
          shellControllerProvider.overrideWith(_GoldenShellController.new),
        ],
        child: const ShellTheme(
          data: ShellThemeData(),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: ImeCandidatePanelLayer(),
          ),
        ),
      ),
    );
    // First pump measures, second applies the resolved placement.
    await tester.pump();
    await tester.pump();

    await expectLater(
      find.byType(ImeCandidatePanelLayer),
      matchesGoldenFile('goldens/ime_panel_edge_flip.png'),
    );
  });
}
