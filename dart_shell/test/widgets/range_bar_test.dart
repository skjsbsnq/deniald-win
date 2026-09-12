import 'package:denial_dart_shell/src/theme/shell_theme.dart';
import 'package:denial_dart_shell/src/widgets/shade/range_bar.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('trackpad pan changes the range without snapping to the cursor', (
    tester,
  ) async {
    final changes = <double>[];
    final ended = <double>[];

    await tester.pumpWidget(
      _RangeBarTestHost(onChanged: changes.add, onChangeEnd: ended.add),
    );

    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.trackpad,
    );
    final position =
        tester.getTopLeft(find.byType(RangeBar)) + const Offset(270, 19);
    await gesture.panZoomStart(position);
    await gesture.panZoomUpdate(position, pan: const Offset(80, 0));
    await gesture.panZoomEnd();
    await tester.pump();

    expect(changes, isNotEmpty);
    expect(changes.last, closeTo(0.25 + 80 / 300, 0.001));
    expect(ended, hasLength(1));
    expect(ended.single, changes.last);
  });

  testWidgets('direct touch drag still changes the range', (tester) async {
    final changes = <double>[];
    final ended = <double>[];

    await tester.pumpWidget(
      _RangeBarTestHost(onChanged: changes.add, onChangeEnd: ended.add),
    );

    await tester.drag(find.byType(RangeBar), const Offset(80, 0));

    expect(changes, isNotEmpty);
    expect(ended, hasLength(1));
  });

  testWidgets('mouse wheel changes the range by one fixed step', (
    tester,
  ) async {
    final starts = <Object?>[];
    final changes = <double>[];
    final ended = <double>[];

    await tester.pumpWidget(
      _RangeBarTestHost(
        onChangeStart: () => starts.add(null),
        onChanged: changes.add,
        onChangeEnd: ended.add,
      ),
    );

    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    final position = tester.getCenter(find.byType(RangeBar));
    await tester.sendEventToBinding(mouse.hover(position));
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, -120)));
    await tester.pump();

    expect(starts, hasLength(1));
    expect(changes, <double>[0.30]);
    expect(ended, <double>[0.30]);
  });

  testWidgets('non-gesture value changes animate the fill', (tester) async {
    var value = 0.25;
    late StateSetter setValue;
    await tester.pumpWidget(
      _MutableRangeBarHost(
        value: () => value,
        register: (setter) => setValue = setter,
      ),
    );

    final startWidth = _fillWidth(tester);
    expect(startWidth, closeTo(_fillFor(0.25, 300), 0.5));

    setValue(() => value = 0.75);
    await tester.pump();
    // The first pump runs didUpdateWidget and arms the spring; advancing one
    // more frame shows the fill mid-flight.
    await tester.pump(const Duration(milliseconds: 50));

    final early = _fillWidth(tester);
    expect(early, greaterThan(startWidth));
    expect(early, lessThan(_fillFor(0.75, 300)));

    await tester.pumpAndSettle();
    expect(_fillWidth(tester), closeTo(_fillFor(0.75, 300), 0.5));
  });

  testWidgets('reduce motion applies non-gesture changes instantly', (
    tester,
  ) async {
    var value = 0.25;
    late StateSetter setValue;
    await tester.pumpWidget(
      _MutableRangeBarHost(
        value: () => value,
        register: (setter) => setValue = setter,
        disableAnimations: true,
      ),
    );

    setValue(() => value = 0.75);
    await tester.pump();
    expect(_fillWidth(tester), closeTo(_fillFor(0.75, 300), 0.5));
  });

  testWidgets('gesture drags stay glued to the finger with no lag', (
    tester,
  ) async {
    final changes = <double>[];
    await tester.pumpWidget(
      _MutableRangeBarHost(
        value: () => 0.25,
        register: (_) {},
        onChanged: changes.add,
      ),
    );

    final gesture = await tester.startGesture(
      tester.getTopLeft(find.byType(RangeBar)) + const Offset(75, 19),
    );
    await gesture.moveBy(const Offset(80, 0));
    await tester.pump();

    // Immediately after the drag frame the fill must sit at the finger —
    // not still catching up from the committed value.
    final expectedFraction = (75 + 80) / 300;
    expect(_fillWidth(tester), closeTo(_fillFor(expectedFraction, 300), 0.6));

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets(
    'leadingIcon renders a detached circle and hides the in-track icon',
    (tester) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ShellTheme(
            data: const ShellThemeData(),
            child: Center(
              child: SizedBox(
                width: 340,
                child: RangeBar(
                  icon: Icons.volume_up_rounded,
                  leadingIcon: Icons.music_note_rounded,
                  value: 0.5,
                  activeColor: const Color(0xff80cbc4),
                  inactiveColor: const Color(0xff263238),
                  onChanged: (_) {},
                  onChangeEnd: (_) {},
                  height: 48,
                ),
              ),
            ),
          ),
        ),
      );

      // Detached Ø40 segment is present and the in-track icon is gone.
      expect(find.byIcon(Icons.music_note_rounded), findsOneWidget);
      expect(find.byIcon(Icons.volume_up_rounded), findsNothing);

      final circle = tester.widget<DecoratedBox>(
        find.ancestor(
          of: find.byIcon(Icons.music_note_rounded),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is DecoratedBox &&
                (widget.decoration as BoxDecoration).shape == BoxShape.circle,
          ),
        ),
      );
      expect(
        (circle.decoration as BoxDecoration).color,
        const ShellThemeData().colors.surfaceContainerHigh,
      );

      // The detached segment measures Ø40.
      final circleBox = find.ancestor(
        of: find.byIcon(Icons.music_note_rounded),
        matching: find.byWidgetPredicate(
          (widget) => widget is SizedBox && widget.width == 40.0,
        ),
      );
      expect(tester.getSize(circleBox), const Size(40.0, 40.0));
    },
  );
}

/// Fill-segment width for a fraction in a [width]-wide track: the active pill
/// stops half a split-gap short of the fill point.
double _fillFor(double fraction, double width) =>
    (width * fraction - 4.0).clamp(0.0, width);

double _fillWidth(WidgetTester tester) {
  const active = Color(0xff80cbc4);
  final boxes = tester
      .widgetList<DecoratedBox>(
        find.descendant(
          of: find.byType(RangeBar),
          matching: find.byType(DecoratedBox),
        ),
      )
      .where((box) => (box.decoration as BoxDecoration).color == active);
  var width = 0.0;
  for (final box in boxes) {
    final size = tester.getSize(find.byWidget(box));
    if (size.width > width) {
      width = size.width;
    }
  }
  return width;
}

class _MutableRangeBarHost extends StatelessWidget {
  const _MutableRangeBarHost({
    required this.value,
    required this.register,
    this.onChanged,
    this.disableAnimations = false,
  });

  final double Function() value;
  final void Function(StateSetter setter) register;
  final ValueChanged<double>? onChanged;
  final bool disableAnimations;

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: ShellTheme(
          data: const ShellThemeData(),
          child: Center(
            child: SizedBox(
              width: 300,
              child: StatefulBuilder(
                builder: (context, setState) {
                  register(setState);
                  return RangeBar(
                    icon: Icons.volume_up_rounded,
                    value: value(),
                    activeColor: const Color(0xff80cbc4),
                    inactiveColor: const Color(0xff263238),
                    onChanged: onChanged ?? (_) {},
                    onChangeEnd: (_) {},
                    height: 38,
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RangeBarTestHost extends StatelessWidget {
  const _RangeBarTestHost({
    required this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
  });

  final ValueChanged<double> onChanged;
  final VoidCallback? onChangeStart;
  final ValueChanged<double>? onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final child = SizedBox(
      width: 300,
      child: RangeBar(
        icon: Icons.volume_up_rounded,
        value: 0.25,
        activeColor: const Color(0xff80cbc4),
        inactiveColor: const Color(0xff263238),
        onChanged: onChanged,
        onChangeStart: onChangeStart,
        onChangeEnd: onChangeEnd ?? (_) {},
        height: 38,
      ),
    );
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ShellTheme(
        data: const ShellThemeData(),
        child: Center(child: child),
      ),
    );
  }
}
