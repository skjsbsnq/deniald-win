import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:denial_dart_shell/src/input/shell_interaction_registry.dart';
import 'package:denial_dart_shell/src/models/display_layout.dart';
import 'package:denial_dart_shell/src/models/ime_frame.dart';
import 'package:denial_dart_shell/src/platform/denial_bridge.dart';
import 'package:denial_dart_shell/src/state/display_layout.dart';
import 'package:denial_dart_shell/src/state/ime_panel.dart';
import 'package:denial_dart_shell/src/state/shell_controller.dart';
import 'package:denial_dart_shell/src/state/shell_state.dart';
import 'package:denial_dart_shell/src/theme/shell_theme.dart';
import 'package:denial_dart_shell/src/theme/tokens.dart';
import 'package:denial_dart_shell/src/widgets/ime/ime_candidate_panel.dart';
import 'package:denial_dart_shell/src/widgets/ime/ime_panel_layer.dart';

class _ImeTestBridge extends DenialBridge {
  _ImeTestBridge({this.pointer});

  final Offset? pointer;

  @override
  Stream<Offset> get cursorPositions => pointer == null
      ? const Stream<Offset>.empty()
      : Stream<Offset>.value(pointer!);
}

class _FixedImePanel extends ImePanelController {
  _FixedImePanel(this._initial);

  final ImePanelState _initial;

  @override
  ImePanelState build() => _initial;

  /// Pushes a new panel state the way wire updates do — ProviderScope
  /// `overrideWith` swaps are a no-op on an already-created notifier
  /// element, so hide/show transitions must go through [state] itself.
  void emit(ImePanelState next) => state = next;
}

class _FixedDisplayLayout extends DisplayLayoutController {
  _FixedDisplayLayout(this._layout);

  final DisplayLayout? _layout;

  @override
  DisplayLayout? build() => _layout;
}

class _EmptyShellController extends ShellController {
  // The real build() kicks off a window-list refresh whose reply timeout
  // leaves a pending timer in tests; a fixed empty state is enough for the
  // placement fallback lookups.
  @override
  ShellState build() => ShellState.initial();
}

const _engine = DenialImeState(
  serial: 3,
  engine: DenialImeEngineStatus.ready,
  endpoint: DenialImeEndpointKind.waylandTextInput,
  mode: DenialImeInputMode.chinese,
);

const _candidates = <DenialImeCandidate>[
  DenialImeCandidate(text: '你好', annotation: 'hello'),
  DenialImeCandidate(text: '尼号'),
];

const _frame = DenialImeFrame(
  serial: 3,
  candidates: _candidates,
  highlighted: 0,
  pageCount: 1,
);

/// A short output (800x160) that cannot fit a tall candidate list; the
/// caret anchor sits inside it.
const _shortOutputLayout = DisplayLayout(
  epoch: 1,
  globalOrigin: Offset.zero,
  logicalSize: Size(800, 600),
  pixelSize: Size(800, 600),
  engineScale: 1,
  tickerMonitorId: 0,
  systemBarMonitorId: 0,
  systemBarSide: SystemBarSide.hidden,
  outputs: <DisplayOutput>[
    DisplayOutput(
      monitorId: 0,
      name: 'short-output',
      logicalRect: Rect.fromLTWH(0, 0, 800, 160),
      pixelSize: Size(800, 160),
      scale: 1,
      refreshRate: 60,
    ),
  ],
);

Widget _layerHost(
  ImePanelState panelState, {
  Offset? pointer,
  DisplayLayout? layout,
}) {
  return ProviderScope(
    overrides: [
      denialBridgeProvider.overrideWithValue(_ImeTestBridge(pointer: pointer)),
      imePanelProvider.overrideWith(() => _FixedImePanel(panelState)),
      displayLayoutProvider.overrideWith(() => _FixedDisplayLayout(layout)),
      shellControllerProvider.overrideWith(_EmptyShellController.new),
    ],
    child: ShellTheme(
      data: const ShellThemeData(),
      child: const Directionality(
        textDirection: TextDirection.ltr,
        child: ImeCandidatePanelLayer(),
      ),
    ),
  );
}

void main() {
  testWidgets('hidden until a frame and an active endpoint arrive', (
    tester,
  ) async {
    await tester.pumpWidget(_layerHost(const ImePanelState()));
    await tester.pump();
    expect(find.byKey(imeCandidatePanelKey), findsNothing);

    // A frame without an active endpoint stays hidden.
    await tester.pumpWidget(_layerHost(const ImePanelState(frame: _frame)));
    await tester.pump();
    expect(find.byKey(imeCandidatePanelKey), findsNothing);

    // Endpoint none also hides.
    await tester.pumpWidget(
      _layerHost(
        const ImePanelState(
          frame: _frame,
          engine: DenialImeState(
            serial: 3,
            engine: DenialImeEngineStatus.ready,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(imeCandidatePanelKey), findsNothing);
  });

  testWidgets('anchors below the delivered caret rect', (tester) async {
    await tester.pumpWidget(
      _layerHost(
        const ImePanelState(
          frame: DenialImeFrame(
            serial: 3,
            candidates: _candidates,
            pageCount: 1,
            caret: Rect.fromLTWH(100, 100, 1, 20),
          ),
          engine: _engine,
        ),
      ),
    );
    // First pump measures the panel; the second applies the resolved
    // placement. The panel widget's rect is the positioned surface; the
    // inner column key sits inside the panel's own padding.
    await tester.pump();
    await tester.pump();

    final rect = tester.getRect(find.byType(ImeCandidatePanel));
    expect(rect.top, 120 + ShellSpacing.xs);
    expect(rect.left, 100);
  });

  testWidgets('flips above the caret near the output edge', (tester) async {
    await tester.pumpWidget(
      _layerHost(
        const ImePanelState(
          frame: DenialImeFrame(
            serial: 3,
            candidates: _candidates,
            pageCount: 1,
            caret: Rect.fromLTWH(100, 560, 1, 20),
          ),
          engine: _engine,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final rect = tester.getRect(find.byType(ImeCandidatePanel));
    expect(rect.bottom, lessThanOrEqualTo(560));
    expect(rect.top, greaterThanOrEqualTo(0));
  });

  testWidgets('clamps inside the output horizontally', (tester) async {
    await tester.pumpWidget(
      _layerHost(
        const ImePanelState(
          frame: DenialImeFrame(
            serial: 3,
            candidates: _candidates,
            pageCount: 1,
            caret: Rect.fromLTWH(790, 100, 1, 20),
          ),
          engine: _engine,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final rect = tester.getRect(find.byType(ImeCandidatePanel));
    expect(rect.right, lessThanOrEqualTo(800));
    expect(rect.left, greaterThanOrEqualTo(0));
  });

  testWidgets('zero-extent caret rect still anchors at its position', (
    tester,
  ) async {
    // text-input-v3 cursor rectangles may legally carry a zero width or
    // height; the panel must trust the delivered position instead of
    // degrading to the pointer/canvas fallback.
    await tester.pumpWidget(
      _layerHost(
        const ImePanelState(
          frame: DenialImeFrame(
            serial: 3,
            candidates: _candidates,
            pageCount: 1,
            caret: Rect.fromLTWH(100, 100, 0, 20),
          ),
          engine: _engine,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final rect = tester.getRect(find.byType(ImeCandidatePanel));
    expect(rect.left, 100);
    expect(rect.top, 120 + ShellSpacing.xs);
  });

  testWidgets('a 64-candidate frame scrolls inside a short output', (
    tester,
  ) async {
    await tester.pumpWidget(
      _layerHost(
        ImePanelState(
          frame: DenialImeFrame(
            serial: 3,
            candidates: List<DenialImeCandidate>.generate(
              64,
              (index) => DenialImeCandidate(text: 'c$index'),
            ),
            highlighted: 0,
            pageCount: 1,
            caret: const Rect.fromLTWH(100, 60, 1, 20),
          ),
          engine: _engine,
        ),
        layout: _shortOutputLayout,
      ),
    );
    await tester.pump();
    await tester.pump();

    // No RenderFlex overflow, and the bounds-clamped panel never grows
    // past the output it was clamped to.
    final rect = tester.getRect(find.byType(ImeCandidatePanel));
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.bottom, lessThanOrEqualTo(160));
    expect(rect.height, lessThanOrEqualTo(160));
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    // Every row stays in the tree — the list scrolls rather than
    // truncating candidates.
    expect(find.byKey(imeCandidateRowKey(0)), findsOneWidget);
    expect(find.byKey(imeCandidateRowKey(63)), findsOneWidget);
  });

  testWidgets('input region claims nothing until the panel is measured', (
    tester,
  ) async {
    await tester.pumpWidget(
      _layerHost(
        const ImePanelState(
          frame: DenialImeFrame(
            serial: 3,
            candidates: _candidates,
            pageCount: 1,
            caret: Rect.fromLTWH(100, 100, 1, 20),
          ),
          engine: _engine,
        ),
      ),
    );
    // The first frame lays the panel out at a bounds-sized guess while it
    // is still transparent; that guess must not claim input.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ImeCandidatePanelLayer)),
    );
    expect(container.read(shellInteractionRegistryProvider).surfaces, isEmpty);

    await tester.pump();
    await tester.pump();
    expect(
      container.read(shellInteractionRegistryProvider).surfaces,
      isNotEmpty,
    );
  });

  testWidgets('hiding the panel drops the measured size', (tester) async {
    const visible = ImePanelState(
      frame: _frame,
      engine: DenialImeState(
        serial: 3,
        engine: DenialImeEngineStatus.ready,
        endpoint: DenialImeEndpointKind.legacy,
      ),
    );
    await tester.pumpWidget(_layerHost(visible));
    await tester.pump();
    await tester.pump();
    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 1.0);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ImeCandidatePanelLayer)),
    );

    // Collapse, then show again: the next show must re-measure (invisible
    // first frame) rather than reusing the stale extents for placement.
    // The transition goes through the notifier's state, matching how the
    // real controller emits wire updates on the same element.
    final panel = container.read(imePanelProvider.notifier) as _FixedImePanel;
    panel.emit(const ImePanelState(engine: _engine));
    await tester.pump();
    expect(find.byType(ImeCandidatePanel), findsNothing);

    panel.emit(visible);
    await tester.pump();
    // The frame that first re-renders the panel was built before the
    // post-frame measurement could land.
    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 0.0);
    await tester.pump();
    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 1.0);
  });

  testWidgets('legacy endpoint falls back to the last pointer position', (
    tester,
  ) async {
    const state = ImePanelState(
      frame: _frame,
      engine: DenialImeState(
        serial: 3,
        engine: DenialImeEngineStatus.ready,
        endpoint: DenialImeEndpointKind.legacy,
      ),
    );
    await tester.pumpWidget(_layerHost(state, pointer: const Offset(300, 200)));
    // The pointer event is delivered asynchronously; a rebuild then lets
    // placement see it before the panel is measured and positioned.
    await tester.pump();
    await tester.pumpWidget(_layerHost(state, pointer: const Offset(300, 200)));
    await tester.pump();
    await tester.pump();

    final rect = tester.getRect(find.byType(ImeCandidatePanel));
    // The canvas-bottom fallback would park the panel near x=400; the
    // pointer anchor places it at the pointer's x instead.
    expect(rect.left, 300);
    expect(rect.top, greaterThan(200));
  });

  testWidgets('registers pointer region without keyboard capture', (
    tester,
  ) async {
    await tester.pumpWidget(
      _layerHost(
        const ImePanelState(
          frame: DenialImeFrame(
            serial: 3,
            candidates: _candidates,
            pageCount: 1,
            caret: Rect.fromLTWH(100, 100, 1, 20),
          ),
          engine: _engine,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final region = tester.widget<ShellInputRegion>(
      find.byType(ShellInputRegion),
    );
    expect(region.pointerPolicy, ShellPointerPolicy.childBounds);
    expect(region.keyboardPolicy, ShellKeyboardPolicy.none);
  });
}
