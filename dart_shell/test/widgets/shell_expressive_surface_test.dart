import 'package:denial_dart_shell/src/theme/shell_theme.dart';
import 'package:denial_dart_shell/src/theme/tokens.dart';
import 'package:denial_dart_shell/src/widgets/shell_expressive_surface.dart';
import 'package:denial_dart_shell/src/widgets/shell_hover_pill.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('hover lerps the surface toward hoverColor', (tester) async {
    const rest = Color(0xff202020);
    const hover = Color(0xff404040);
    await tester.pumpWidget(
      _SurfaceHost(
        surface: const ShellExpressiveSurface(
          onPressed: _noop,
          color: rest,
          hoverColor: hover,
          width: 80,
          height: 40,
          child: SizedBox.expand(),
        ),
      ),
    );

    expect(_decoration(tester).color, rest);

    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(
      mouse.hover(tester.getCenter(find.byType(ShellExpressiveSurface))),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));

    final mid = _decoration(tester).color!;
    expect(mid, isNot(rest));
    expect(mid, isNot(hover));

    await tester.pumpAndSettle();
    _expectColorClose(_decoration(tester).color!, hover);

    await tester.sendEventToBinding(mouse.hover(const Offset(10, 10)));
    await tester.pumpAndSettle();
    _expectColorClose(_decoration(tester).color!, rest);
  });

  testWidgets('press drives scale and tint springs, release restores', (
    tester,
  ) async {
    const rest = Color(0xff202020);
    const pressed = Color(0xff606060);
    await tester.pumpWidget(
      _SurfaceHost(
        surface: const ShellExpressiveSurface(
          onPressed: _noop,
          color: rest,
          pressedColor: pressed,
          width: 80,
          height: 40,
          child: SizedBox.expand(),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ShellExpressiveSurface)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    final scaleMid = _pressScale(tester);
    final colorMid = _decoration(tester).color!;

    await tester.pumpAndSettle();
    final scaleSettled = _pressScale(tester);
    final colorSettled = _decoration(tester).color!;

    await gesture.up();
    await tester.pumpAndSettle();
    final scaleReleased = _pressScale(tester);
    final colorReleased = _decoration(tester).color!;

    expect(scaleMid, lessThan(1.0));
    expect(scaleMid, greaterThan(0.94));
    expect(colorMid, isNot(rest));
    expect(scaleSettled, closeTo(0.94, 1e-3));
    _expectColorClose(colorSettled, pressed);
    expect(scaleReleased, closeTo(1.0, 1e-3));
    _expectColorClose(colorReleased, rest);
  });

  testWidgets('pressedShape morphs the corner radius while pressed', (
    tester,
  ) async {
    await tester.pumpWidget(
      _SurfaceHost(
        surface: const ShellExpressiveSurface(
          onPressed: _noop,
          shape: ShellShapeScale.extraLarge,
          pressedShape: ShellShapeScale.small,
          width: 80,
          height: 40,
          child: SizedBox.expand(),
        ),
      ),
    );

    expect(_radius(tester), closeTo(28.0, 1e-3));

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ShellExpressiveSurface)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    final mid = _radius(tester);

    await tester.pumpAndSettle();
    final settled = _radius(tester);

    await gesture.up();
    await tester.pumpAndSettle();
    final released = _radius(tester);

    expect(mid, lessThan(28.0));
    expect(mid, greaterThan(8.0));
    expect(settled, closeTo(8.0, 1e-2));
    expect(released, closeTo(28.0, 1e-2));
  });

  testWidgets('disableAnimations snaps press state instantly', (tester) async {
    await tester.pumpWidget(
      _SurfaceHost(
        disableAnimations: true,
        surface: const ShellExpressiveSurface(
          onPressed: _noop,
          shape: ShellShapeScale.extraLarge,
          pressedShape: ShellShapeScale.small,
          width: 80,
          height: 40,
          child: SizedBox.expand(),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ShellExpressiveSurface)),
    );
    await tester.pump();

    final scaleDown = _pressScale(tester);
    final radiusDown = _radius(tester);

    await gesture.up();
    await tester.pump();

    expect(scaleDown, 0.94);
    expect(radiusDown, 8.0);
    expect(_pressScale(tester), 1.0);
    expect(_radius(tester), 28.0);
  });

  testWidgets('Enter and Space activate; taps fire onPressed/onLongPress', (
    tester,
  ) async {
    var pressed = 0;
    var longPressed = 0;
    await tester.pumpWidget(
      _SurfaceHost(
        surface: ShellExpressiveSurface(
          onPressed: () => pressed++,
          onLongPress: () => longPressed++,
          autofocus: true,
          width: 80,
          height: 40,
          child: const SizedBox.expand(),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byType(ShellExpressiveSurface));
    expect(pressed, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(pressed, 2);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(pressed, 3);

    await tester.longPress(find.byType(ShellExpressiveSurface));
    expect(longPressed, 1);
  });

  testWidgets('disabled surface is inert', (tester) async {
    var pressed = 0;
    await tester.pumpWidget(
      _SurfaceHost(
        surface: ShellExpressiveSurface(
          onPressed: () => pressed++,
          enabled: false,
          width: 80,
          height: 40,
          child: const SizedBox.expand(),
        ),
      ),
    );

    await tester.tap(find.byType(ShellExpressiveSurface), warnIfMissed: false);
    expect(pressed, 0);
  });

  testWidgets('ShellHoverPill keeps hover color swap and activation', (
    tester,
  ) async {
    var tapped = 0;
    const rest = Color(0xff202020);
    const hover = Color(0xff505050);
    await tester.pumpWidget(
      _SurfaceHost(
        surface: ShellHoverPill(
          onTap: () => tapped++,
          color: rest,
          hoverColor: hover,
          width: 80,
          height: 40,
          child: const SizedBox.expand(),
        ),
      ),
    );

    expect(_pillDecoration(tester).color, rest);

    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(
      mouse.hover(tester.getCenter(find.byType(ShellHoverPill))),
    );
    await tester.pumpAndSettle();
    _expectColorClose(_pillDecoration(tester).color!, hover);

    await tester.tap(find.byType(ShellHoverPill));
    expect(tapped, 1);
  });

  testWidgets('ShellHoverPill.builder receives live hover/focus flags', (
    tester,
  ) async {
    var hoveredSeen = false;
    await tester.pumpWidget(
      _SurfaceHost(
        surface: ShellHoverPill.builder(
          onTap: _noop,
          width: 80,
          height: 40,
          childBuilder: (context, hovered, focused) {
            hoveredSeen = hovered;
            return const SizedBox.expand();
          },
        ),
      ),
    );

    expect(hoveredSeen, isFalse);

    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(
      mouse.hover(tester.getCenter(find.byType(ShellHoverPill))),
    );
    await tester.pump();
    expect(hoveredSeen, isTrue);
  });
}

void _noop() {}

BoxDecoration _decoration(WidgetTester tester) {
  final container = tester.widget<Container>(
    find.descendant(
      of: find.byType(ShellExpressiveSurface),
      matching: find.byType(Container),
    ),
  );
  return container.decoration! as BoxDecoration;
}

BoxDecoration _pillDecoration(WidgetTester tester) {
  final container = tester.widget<Container>(
    find.descendant(
      of: find.byType(ShellHoverPill),
      matching: find.byType(Container),
    ),
  );
  return container.decoration! as BoxDecoration;
}

double _pressScale(WidgetTester tester) {
  final transform = tester.widget<Transform>(
    find.descendant(
      of: find.byType(ShellExpressiveSurface),
      matching: find.byType(Transform),
    ),
  );
  // getMaxScaleOnAxis includes the untouched z axis (always 1.0), so read the
  // x scale directly.
  return transform.transform.entry(0, 0);
}

double _radius(WidgetTester tester) {
  final borderRadius = _decoration(tester).borderRadius! as BorderRadius;
  return borderRadius.topLeft.x;
}

void _expectColorClose(Color actual, Color expected) {
  expect(actual.a, closeTo(expected.a, 0.02));
  expect(actual.r, closeTo(expected.r, 0.02));
  expect(actual.g, closeTo(expected.g, 0.02));
  expect(actual.b, closeTo(expected.b, 0.02));
}

class _SurfaceHost extends StatelessWidget {
  const _SurfaceHost({required this.surface, this.disableAnimations = false});

  final Widget surface;
  final bool disableAnimations;

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: ShellTheme(
          data: const ShellThemeData(),
          child: Center(child: surface),
        ),
      ),
    );
  }
}
