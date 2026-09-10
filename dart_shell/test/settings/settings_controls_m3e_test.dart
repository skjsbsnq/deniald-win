import 'package:denial_dart_shell/src/settings/widgets/settings_buttons.dart';
import 'package:denial_dart_shell/src/settings/widgets/settings_controls.dart';
import 'package:denial_dart_shell/src/settings/widgets/settings_loading_indicator.dart';
import 'package:denial_dart_shell/src/theme/shell_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SettingsToggle (M3E switch)', () {
    testWidgets('renders the 52x32 track from spec §3.4', (tester) async {
      await tester.pumpWidget(
        _wrap(
          SettingsToggle(
            label: 'Dark mode',
            description: 'Preview dark surfaces',
            value: false,
            onChanged: (_) {},
          ),
        ),
      );

      expect(
        tester.getSize(find.byKey(settingsToggleTrackKey)),
        const Size(52, 32),
      );
    });

    testWidgets('thumb grows from 16 to 24 with the value', (tester) async {
      await tester.pumpWidget(
        _wrap(
          SettingsToggle(
            label: 'Dark mode',
            description: 'Preview dark surfaces',
            value: false,
            onChanged: (_) {},
          ),
        ),
      );
      final offThumb = _thumbSize(tester, Icons.close_rounded);
      expect(offThumb.width, 16);
      expect(offThumb.height, 16);

      await tester.pumpWidget(
        _wrap(
          SettingsToggle(
            label: 'Dark mode',
            description: 'Preview dark surfaces',
            value: true,
            onChanged: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final onThumb = _thumbSize(tester, Icons.check_rounded);
      expect(onThumb.width, closeTo(24, 0.05));
      expect(onThumb.height, closeTo(24, 0.05));
    });

    testWidgets('shows the 40dp pressed state layer while held', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          SettingsToggle(
            label: 'Dark mode',
            description: 'Preview dark surfaces',
            value: false,
            onChanged: (_) {},
          ),
        ),
      );
      expect(
        tester
            .widget<AnimatedOpacity>(find.byKey(settingsToggleStateLayerKey))
            .opacity,
        0,
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(settingsToggleTrackKey)),
      );
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        tester
            .widget<AnimatedOpacity>(find.byKey(settingsToggleStateLayerKey))
            .opacity,
        1,
      );
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('the spatial spring overshoot settles without throwing', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          SettingsToggle(
            label: 'Dark mode',
            description: 'Preview dark surfaces',
            value: false,
            onChanged: (_) {},
          ),
        ),
      );
      await tester.pumpWidget(
        _wrap(
          SettingsToggle(
            label: 'Dark mode',
            description: 'Preview dark surfaces',
            value: true,
            onChanged: (_) {},
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('SettingsSlider (M3E slider)', () {
    testWidgets('uses the 16dp track, 4x44 handle and 4dp ticks', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          SettingsSlider(
            label: 'Cursor size',
            value: 0.5,
            minimum: 0,
            maximum: 1,
            onChanged: (_) {},
          ),
        ),
      );

      final data = tester
          .widget<SliderTheme>(find.byKey(settingsSliderThemeKey))
          .data;
      expect(data.trackHeight, settingsSliderTrackHeight);
      expect(
        data.thumbShape!.getPreferredSize(true, false),
        const Size(
          settingsSliderHandleWidth,
          settingsSliderHandleHeight,
        ),
      );
      expect(
        data.tickMarkShape!.getPreferredSize(
          sliderTheme: data,
          isEnabled: true,
        ),
        const Size(
          settingsSliderTickDiameter,
          settingsSliderTickDiameter,
        ),
      );
    });

    testWidgets('stacks the heading above the slider below 430dp', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          SettingsSlider(
            label: 'Cursor size',
            value: 0.5,
            minimum: 0,
            maximum: 1,
            onChanged: (_) {},
          ),
          width: 400,
        ),
      );

      final labelBottom = tester.getBottomLeft(find.text('Cursor size')).dy;
      final sliderTop = tester.getTopLeft(find.byType(Slider)).dy;
      expect(sliderTop, greaterThan(labelBottom));
    });
  });

  group('SettingsSegmentedControl (M3E segments)', () {
    testWidgets('lays segments out as equal, 40-high, 12-spaced blocks', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          SettingsSegmentedControl<String>(
            value: 'a',
            choices: const <SettingsChoice<String>>[
              SettingsChoice<String>('a', 'Alpha'),
              SettingsChoice<String>('b', 'Beta'),
            ],
            onChanged: (_) {},
          ),
          width: 600,
        ),
      );

      final alpha = _segmentFinder('Alpha');
      final beta = _segmentFinder('Beta');
      expect(tester.getSize(alpha).height, settingsSegmentHeight);
      expect(tester.getSize(alpha).width, tester.getSize(beta).width);
      expect(
        tester.getTopLeft(beta).dx - tester.getBottomRight(alpha).dx,
        settingsSegmentSpacing,
      );
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    });

    testWidgets('stacks segments vertically below 430dp', (tester) async {
      await tester.pumpWidget(
        _wrap(
          SettingsSegmentedControl<String>(
            value: 'a',
            choices: const <SettingsChoice<String>>[
              SettingsChoice<String>('a', 'Alpha'),
              SettingsChoice<String>('b', 'Beta'),
            ],
            onChanged: (_) {},
          ),
          width: 400,
        ),
      );

      final alpha = _segmentFinder('Alpha');
      final beta = _segmentFinder('Beta');
      expect(
        tester.getTopLeft(beta).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(alpha).dy),
      );
    });

    testWidgets('arrow keys move focus and Enter selects the segment', (
      tester,
    ) async {
      String? changed;
      await tester.pumpWidget(
        _wrap(
          SettingsSegmentedControl<String>(
            value: 'a',
            choices: const <SettingsChoice<String>>[
              SettingsChoice<String>('a', 'Alpha'),
              SettingsChoice<String>('b', 'Beta'),
            ],
            onChanged: (value) => changed = value,
          ),
          width: 600,
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(changed, 'b');
    });
  });

  group('SettingsButton (M3E buttons)', () {
    testWidgets('small is 40 high and morphs its radius to 8 on press', (
      tester,
    ) async {
      const surfaceKey = ValueKey<String>('small-button-surface');
      await tester.pumpWidget(
        _wrap(
          Center(
            child: SettingsButton(
              label: 'Reset page',
              onPressed: () {},
              surfaceKey: surfaceKey,
            ),
          ),
        ),
      );

      expect(tester.getSize(find.byKey(surfaceKey)).height, 40);
      expect(_surfaceRadius(tester, surfaceKey), greaterThan(100));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(SettingsButton)),
      );
      await tester.pumpAndSettle();
      expect(_surfaceRadius(tester, surfaceKey), closeTo(8, 0.01));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(_surfaceRadius(tester, surfaceKey), greaterThan(100));
    });

    testWidgets('medium is 56 high and morphs its radius to 12 on press', (
      tester,
    ) async {
      const surfaceKey = ValueKey<String>('medium-button-surface');
      await tester.pumpWidget(
        _wrap(
          Center(
            child: SettingsButton(
              label: 'Apply',
              onPressed: () {},
              size: SettingsButtonSize.medium,
              surfaceKey: surfaceKey,
            ),
          ),
        ),
      );

      expect(tester.getSize(find.byKey(surfaceKey)).height, 56);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(SettingsButton)),
      );
      await tester.pumpAndSettle();
      expect(_surfaceRadius(tester, surfaceKey), closeTo(12, 0.01));
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('SettingsTextButton keeps its text-variant call site', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(Center(child: SettingsTextButton(label: 'Reset', onPressed: () {}))),
      );

      final button = tester.widget<SettingsButton>(find.byType(SettingsButton));
      expect(button.variant, SettingsButtonVariant.text);
      expect(button.label, 'Reset');
      expect(tester.getSize(find.byType(SettingsButton)).height, 40);
    });
  });

  group('SettingsLoadingIndicator (M3E loading)', () {
    testWidgets('is a 48dp container that keeps morphing', (tester) async {
      await tester.pumpWidget(_wrap(const SettingsLoadingIndicator(), width: null));

      expect(
        tester.getSize(find.byType(SettingsLoadingIndicator)),
        const Size(
          settingsLoadingIndicatorSize,
          settingsLoadingIndicatorSize,
        ),
      );

      final first = _loadingPainter(tester);
      await tester.pump(const Duration(milliseconds: 120));
      final second = _loadingPainter(tester);
      expect(identical(first, second), isFalse);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('freezes to a static ring when animations are disabled', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(const SettingsLoadingIndicator(), width: null, disableAnimations: true),
      );

      final first = _loadingPainter(tester);
      await tester.pump(const Duration(milliseconds: 120));
      final second = _loadingPainter(tester);
      expect(identical(first, second), isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('exposes the provided semantics label', (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          _wrap(const SettingsLoadingIndicator(semanticsLabel: 'Loading'), width: null),
        );
        expect(
          tester.getSemantics(find.byType(SettingsLoadingIndicator)),
          isSemantics(label: 'Loading'),
        );
      } finally {
        semantics.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    });
  });
}

Finder _segmentFinder(String label) => find
    .ancestor(
      of: find.text(label),
      matching: find.byType(SettingsInteractiveSurface),
    )
    .first;

Size _thumbSize(WidgetTester tester, IconData icon) {
  final thumb = find
      .ancestor(of: find.byIcon(icon), matching: find.byType(SizedBox))
      .first;
  return tester.getSize(thumb);
}

double _surfaceRadius(WidgetTester tester, Key surfaceKey) {
  final decoration =
      tester.widget<DecoratedBox>(find.byKey(surfaceKey)).decoration
          as BoxDecoration;
  return (decoration.borderRadius! as BorderRadius).topLeft.x;
}

CustomPainter _loadingPainter(WidgetTester tester) {
  final finder = find.descendant(
    of: find.byType(SettingsLoadingIndicator),
    matching: find.byType(CustomPaint),
  );
  return tester.widget<CustomPaint>(finder).painter!;
}

Widget _wrap(
  Widget child, {
  double? width = 800,
  bool disableAnimations = false,
}) {
  return MaterialApp(
    locale: const Locale('en'),
    home: Builder(
      builder: (context) {
        final content = width == null
            ? child
            : SizedBox(width: width, child: child);
        return ShellTheme(
          data: const ShellThemeData(),
          child: MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(disableAnimations: disableAnimations),
            child: Material(child: Center(child: content)),
          ),
        );
      },
    ),
  );
}
