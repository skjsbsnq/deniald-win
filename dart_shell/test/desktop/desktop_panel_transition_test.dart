import 'package:denial_dart_shell/src/desktop/desktop_panel_transition.dart';
import 'package:denial_dart_shell/src/input/shell_interaction_registry.dart';
import 'package:denial_dart_shell/src/theme/shell_theme.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('closed panels retain state while staying inert and offstage', (
    tester,
  ) async {
    final counters = _ProbeCounters();

    Future<void> pump({required bool visible}) {
      return tester.pumpWidget(
        ProviderScope(
          child: ShellTheme(
            data: const ShellThemeData(),
            child: MediaQuery(
              data: const MediaQueryData(),
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: SizedBox(
                  width: 320,
                  height: 240,
                  child: DesktopPanelTransition(
                    inputDebugLabel: 'test panel',
                    visible: visible,
                    durationScale: 0,
                    child: _StateProbe(counters: counters),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    await pump(visible: false);
    expect(counters.initialized, 1);
    expect(counters.disposed, 0);
    expect(tester.widget<Offstage>(find.byType(Offstage)).offstage, isTrue);
    expect(
      tester.widget<IgnorePointer>(find.byType(IgnorePointer)).ignoring,
      isTrue,
    );
    expect(
      tester.widget<ExcludeSemantics>(find.byType(ExcludeSemantics)).excluding,
      isTrue,
    );
    expect(
      tester.widget<ShellInputRegion>(find.byType(ShellInputRegion)).active,
      isFalse,
    );
    expect(
      tester.widget<ExcludeFocus>(find.byType(ExcludeFocus)).excluding,
      isTrue,
    );

    await pump(visible: true);
    await tester.pumpAndSettle();
    expect(counters.initialized, 1);
    expect(tester.widget<Offstage>(find.byType(Offstage)).offstage, isFalse);
    expect(
      tester.widget<ShellInputRegion>(find.byType(ShellInputRegion)).active,
      isTrue,
    );
    expect(
      tester.widget<ExcludeFocus>(find.byType(ExcludeFocus)).excluding,
      isFalse,
    );

    await pump(visible: false);
    await tester.pumpAndSettle();
    expect(counters.initialized, 1);
    expect(counters.disposed, 0);
    expect(tester.widget<Offstage>(find.byType(Offstage)).offstage, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(counters.disposed, 1);
  });
}

class _ProbeCounters {
  int initialized = 0;
  int disposed = 0;
}

class _StateProbe extends StatefulWidget {
  const _StateProbe({required this.counters});

  final _ProbeCounters counters;

  @override
  State<_StateProbe> createState() => _StateProbeState();
}

class _StateProbeState extends State<_StateProbe> {
  @override
  void initState() {
    super.initState();
    widget.counters.initialized += 1;
  }

  @override
  void dispose() {
    widget.counters.disposed += 1;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
