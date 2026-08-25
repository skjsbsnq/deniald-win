import 'package:denial_dart_shell/src/theme/shell_theme.dart';
import 'package:denial_dart_shell/src/widgets/shell_backdrop_blur.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'uses a full-backdrop, tightly clipped blur at the configured sigma',
    (tester) async {
      await tester.pumpWidget(
        _BlurHarness(
          theme: const ShellThemeData(backdropBlurSigma: 24),
          child: ShellBackdropBlur(
            borderRadius: BorderRadius.circular(18),
            child: const SizedBox(width: 160, height: 90),
          ),
        ),
      );

      final filter = tester.widget<BackdropFilter>(find.byType(BackdropFilter));
      expect(
        filter.filterConfig.toString(),
        'ImageFilterConfig.blur(24.0, 24.0, clamp, unbounded)',
      );
      // Never `src`: it replaces the destination, so a backdrop the engine
      // cannot reproduce is painted as an opaque black rectangle.
      expect(filter.blendMode, BlendMode.srcOver);
      expect(find.byType(ClipRRect), findsOneWidget);
    },
  );

  testWidgets('an ungrouped blur retains its own layer', (tester) async {
    await tester.pumpWidget(
      _BlurHarness(
        theme: const ShellThemeData(),
        child: ShellBackdropBlur(
          borderRadius: BorderRadius.circular(18),
          child: const SizedBox(width: 160, height: 90),
        ),
      ),
    );

    expect(
      find.ancestor(
        of: find.byType(BackdropFilter),
        matching: find.byType(RepaintBoundary),
      ),
      findsOneWidget,
    );
  });

  testWidgets('disabled blur avoids creating a backdrop filter', (
    tester,
  ) async {
    await tester.pumpWidget(
      const _BlurHarness(
        theme: ShellThemeData(backdropBlurEnabled: false),
        child: ShellBackdropBlur(child: SizedBox(width: 160, height: 90)),
      ),
    );

    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.byType(ClipRect), findsNothing);
  });

  testWidgets('known opaque content takes the same zero-cost path', (
    tester,
  ) async {
    await tester.pumpWidget(
      const _BlurHarness(
        theme: ShellThemeData(),
        child: ShellBackdropBlur(
          blur: false,
          child: SizedBox(width: 160, height: 90),
        ),
      ),
    );

    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('known opaque content with borderRadius avoids ClipRRect', (
    tester,
  ) async {
    await tester.pumpWidget(
      _BlurHarness(
        theme: const ShellThemeData(),
        child: ShellBackdropBlur(
          blur: false,
          borderRadius: BorderRadius.circular(18),
          child: const SizedBox(width: 160, height: 90),
        ),
      ),
    );

    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.byType(ClipRRect), findsNothing);
    expect(find.byType(ClipRect), findsNothing);
    expect(find.byType(RepaintBoundary), findsNothing);
  });

  testWidgets('grouped blur shares the nearest backdrop input', (tester) async {
    await tester.pumpWidget(
      _BlurHarness(
        theme: const ShellThemeData(),
        child: BackdropGroup(
          child: const Row(
            children: [
              ShellBackdropBlur(
                grouped: true,
                child: SizedBox(width: 80, height: 90),
              ),
              ShellBackdropBlur(
                grouped: true,
                child: SizedBox(width: 80, height: 90),
              ),
            ],
          ),
        ),
      ),
    );

    final filters = tester.renderObjectList<RenderBackdropFilter>(
      find.byType(BackdropFilter),
    );
    expect(filters.length, 2);
    expect(filters.first.backdropKey, isNotNull);
    expect(filters.last.backdropKey, equals(filters.first.backdropKey));
    expect(
      find.ancestor(
        of: find.byType(BackdropFilter),
        matching: find.byType(RepaintBoundary),
      ),
      findsNothing,
      reason: 'a retained layer would split the shared engine blur',
    );
  });
}

class _BlurHarness extends StatelessWidget {
  const _BlurHarness({required this.theme, required this.child});

  final ShellThemeData theme;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ShellTheme(
        data: theme,
        child: Center(
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              const ColoredBox(
                color: Color(0xff336699),
                child: SizedBox(width: 240, height: 160),
              ),
              child,
            ],
          ),
        ),
      ),
    );
  }
}
