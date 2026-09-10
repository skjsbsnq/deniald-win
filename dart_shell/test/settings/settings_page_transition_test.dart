import 'package:denial_dart_shell/src/settings/widgets/settings_page_header.dart';
import 'package:denial_dart_shell/src/theme/motion.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the spec durations and travel are pinned', () {
    expect(
      SettingsPageTransition.enterDuration,
      const Duration(milliseconds: 300),
    );
    expect(
      SettingsPageTransition.exitDuration,
      const Duration(milliseconds: 120),
    );
    expect(SettingsPageTransition.enterOffset, 8);
  });

  testWidgets('entering fades in over 300ms while rising 8dp', (tester) async {
    final page = ValueNotifier<String>('a');
    addTearDown(page.dispose);
    await tester.pumpWidget(_host(page));
    await tester.pump();

    page.value = 'b';
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 0));

    final startDy = tester.getTopLeft(find.text('b')).dy;
    await tester.pumpAndSettle();
    final settledDy = tester.getTopLeft(find.text('b')).dy;

    expect(settledDy - startDy, closeTo(-SettingsPageTransition.enterOffset, 0.01));
  });

  testWidgets('a reverse transition enters from above', (tester) async {
    final page = ValueNotifier<String>('a');
    addTearDown(page.dispose);
    await tester.pumpWidget(_host(page, reverse: true));
    await tester.pump();

    page.value = 'b';
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 0));

    final startDy = tester.getTopLeft(find.text('b')).dy;
    await tester.pumpAndSettle();
    final settledDy = tester.getTopLeft(find.text('b')).dy;

    expect(settledDy - startDy, closeTo(SettingsPageTransition.enterOffset, 0.01));
  });

  testWidgets('the outgoing page fades out in 120ms, before the 300ms enter', (
    tester,
  ) async {
    final page = ValueNotifier<String>('a');
    addTearDown(page.dispose);
    await tester.pumpWidget(_host(page));
    await tester.pump();

    page.value = 'b';
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 130));
    await tester.pump();

    expect(find.text('a'), findsNothing);
    expect(find.text('b'), findsOneWidget);
  });

  testWidgets('the durations follow animationDurationScale', (tester) async {
    final page = ValueNotifier<String>('a');
    addTearDown(page.dispose);
    await tester.pumpWidget(_host(page, durationScale: 0.5));
    await tester.pump();

    final switcher = _switcher(tester);
    expect(switcher.duration, const Duration(milliseconds: 150));
    expect(switcher.reverseDuration, const Duration(milliseconds: 60));
  });

  testWidgets('reduced motion collapses both durations to zero', (tester) async {
    final page = ValueNotifier<String>('a');
    addTearDown(page.dispose);
    await tester.pumpWidget(_host(page, disableAnimations: true));
    await tester.pump();

    final switcher = _switcher(tester);
    expect(switcher.duration, Duration.zero);
    expect(switcher.reverseDuration, Duration.zero);
  });

  testWidgets('the transition uses the M3 emphasised curves', (tester) async {
    final page = ValueNotifier<String>('a');
    addTearDown(page.dispose);
    await tester.pumpWidget(_host(page));
    await tester.pump();

    final switcher = _switcher(tester);
    expect(switcher.switchInCurve, Motion.md3EmphasizedDecelerate);
    expect(switcher.switchOutCurve, Motion.md3EmphasizedAccelerate);
  });
}

AnimatedSwitcher _switcher(WidgetTester tester) =>
    tester.widget<AnimatedSwitcher>(find.byType(AnimatedSwitcher));

Widget _host(
  ValueListenable<String> page, {
  double durationScale = 1,
  bool reverse = false,
  bool disableAnimations = false,
}) {
  return MediaQuery(
    data: MediaQueryData(disableAnimations: disableAnimations),
    child: ShellTestFrame(
      child: ValueListenableBuilder<String>(
        valueListenable: page,
        builder: (context, value, _) => SettingsPageTransition(
          durationScale: durationScale,
          reverse: reverse,
          child: KeyedSubtree(
            key: ValueKey<String>(value),
            child: Center(child: Text(value)),
          ),
        ),
      ),
    ),
  );
}

/// Minimal bounded frame so the transition's expand-filling [Stack] has a size.
class ShellTestFrame extends StatelessWidget {
  const ShellTestFrame({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: SizedBox(width: 320, height: 320, child: child)),
    );
  }
}
