import 'package:denial_dart_shell/src/theme/shell_theme.dart';
import 'package:denial_dart_shell/src/theme/tokens.dart';
import 'package:denial_dart_shell/src/widgets/shell_backdrop_blur.dart';
import 'package:denial_dart_shell/src/widgets/shell_surface_host.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'managed surface keeps its backdrop blur fully opaque on the first frame',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: ShellTheme(
              data: const ShellThemeData(),
              child: const ShellSurfaceHost(child: SizedBox.expand()),
            ),
          ),
        ),
      );
      await tester.pump();

      container
          .read(shellSurfaceControllerProvider.notifier)
          .show(
            debugLabel: 'probe',
            builder: (context, handle) => Center(
              child: SizedBox(
                width: 200,
                height: 200,
                child: ShellBackdropBlur(
                  borderRadius: context.shellTheme.borderRadius(
                    ShellShapeScale.large,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          );

      // One frame into the open transition: the blur is already active and
      // the surface itself is not mid-fade — only the scrim fades.
      await tester.pump(const Duration(milliseconds: 16));

      final filter = tester.widget<BackdropFilter>(
        find.byType(BackdropFilter),
      );
      expect(filter.enabled, isTrue);

      final surfaceFades = tester.widgetList<FadeTransition>(
        find.ancestor(
          of: find.byType(BackdropFilter),
          matching: find.byType(FadeTransition),
        ),
      );
      for (final fade in surfaceFades) {
        expect(
          fade.opacity.value,
          1.0,
          reason: 'fading a blurred surface composites it as transparent '
              'glass before the blur becomes visible',
        );
      }
    },
  );

  testWidgets(
    'closing surface shares a single opacity layer with its scrim',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: ShellTheme(
              data: const ShellThemeData(),
              child: const ShellSurfaceHost(child: SizedBox.expand()),
            ),
          ),
        ),
      );
      await tester.pump();

      final controller = container.read(
        shellSurfaceControllerProvider.notifier,
      );
      final handle = controller.show(
        debugLabel: 'probe',
        builder: (context, handle) => Center(
          child: SizedBox(
            width: 200,
            height: 200,
            child: ShellBackdropBlur(
              borderRadius: context.shellTheme.borderRadius(
                ShellShapeScale.large,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      handle.close();
      // Mid-close frame: the panel must not sit in its own opacity layer —
      // a separate fade composites the blurred glass against the dimming
      // scrim and reads as a black flash.
      await tester.pump(const Duration(milliseconds: 80));

      final fades = tester.widgetList<FadeTransition>(
        find.ancestor(
          of: find.byType(BackdropFilter),
          matching: find.byType(FadeTransition),
        ),
      );
      expect(
        fades.length,
        1,
        reason: 'the closing panel must fade in the same layer as the scrim',
      );
    },
  );
}
