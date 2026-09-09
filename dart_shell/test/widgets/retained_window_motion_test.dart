import 'package:denial_dart_shell/src/localization/denial_localizations.dart';
import 'package:denial_dart_shell/src/models/app_launch_request.dart';
import 'package:denial_dart_shell/src/models/denial_window.dart';
import 'package:denial_dart_shell/src/theme/shell_theme.dart';
import 'package:denial_dart_shell/src/widgets/launch_transition_layer.dart';
import 'package:denial_dart_shell/src/widgets/retained_scale.dart';
import 'package:denial_dart_shell/src/widgets/retained_window_motion.dart';
import 'package:denial_dart_shell/src/widgets/window_hero.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'retained scale keeps build, layout and paint and rebinds its listener',
    (tester) async {
      final scale = ValueNotifier(1.0);
      final replacement = ValueNotifier(0.8);
      addTearDown(scale.dispose);
      addTearDown(replacement.dispose);
      final probe = _Probe();
      Widget scene(ValueNotifier<double> source) => Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox.square(
            dimension: 100,
            child: RetainedScale(
              scale: source,
              child: RepaintBoundary(child: probe),
            ),
          ),
        ),
      );
      await tester.pumpWidget(scene(scale));
      final render = tester.renderObject<_RenderProbe>(find.byType(_Probe));
      final initial = (render.layouts, render.paints);
      final original = tester.getRect(find.byType(_Probe));
      for (var frame = 1; frame <= 60; frame++) {
        scale.value = 1 - frame / 100;
        await tester.pump();
        final visual = MatrixUtils.transformRect(
          render.getTransformTo(null),
          Offset.zero & render.size,
        );
        expect(
          visual,
          rectMoreOrLessEquals(
            Rect.fromCenter(
              center: original.center,
              width: 100 * scale.value,
              height: 100 * scale.value,
            ),
          ),
        );
      }
      expect((render.layouts, render.paints), initial);
      await tester.pumpWidget(scene(replacement));
      final before = render.getTransformTo(null);
      scale.value = 0.1;
      await tester.pump();
      expect(render.getTransformTo(null), before);
      await tester.pumpWidget(const SizedBox.shrink());
      replacement.value = 0.6;
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('unscaled motion keeps overlay geometry and clips hit testing', (
    tester,
  ) async {
    final progress = AnimationController(vsync: tester);
    addTearDown(progress.dispose);
    final probe = _Probe();
    var taps = 0;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox.square(
            dimension: 200,
            child: RetainedWindowMotion(
              progress: progress,
              begin: const Rect.fromLTWH(50, 50, 100, 100),
              end: const Rect.fromLTWH(0, 0, 200, 200),
              beginRadius: 20,
              transformChild: false,
              child: RepaintBoundary(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => taps++,
                  child: probe,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final render = tester.renderObject<_RenderProbe>(find.byType(_Probe));
    final initial = (render.layouts, render.paints);
    await tester.tapAt(const Offset(10, 10));
    await tester.tapAt(const Offset(51, 51));
    expect(taps, 0);
    await tester.tapAt(const Offset(100, 100));
    expect(taps, 1);
    for (var frame = 1; frame <= 60; frame++) {
      progress.value = frame / 60;
      await tester.pump();
      expect(render.getTransformTo(null), Matrix4.identity());
    }
    expect((render.layouts, render.paints), initial);
    await tester.tapAt(const Offset(10, 10));
    expect(taps, 2);
  });

  testWidgets('60 motion frames retain app build, layout and paint', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final progress = AnimationController(vsync: tester);
    addTearDown(progress.dispose);
    var builds = 0;
    final probe = _Probe();
    const start = Rect.fromLTWH(0, 0, 400, 800);
    const end = Rect.fromLTWH(60, 98, 280, 560);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 400,
            height: 800,
            child: RetainedWindowMotion(
              progress: progress,
              begin: start,
              end: end,
              endRadius: 24,
              child: RepaintBoundary(
                child: Builder(
                  builder: (_) {
                    builds++;
                    return probe;
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final render = tester.renderObject<_RenderProbe>(find.byType(_Probe));
    final initial = (builds, render.layouts, render.paints);
    for (var frame = 1; frame <= 60; frame++) {
      progress.value = frame / 60;
      await tester.pump();
      final matrix = render.getTransformTo(
        tester.renderObject(find.byType(RetainedWindowMotion)),
      );
      final visual = MatrixUtils.transformRect(
        matrix,
        Offset.zero & render.size,
      );
      expect(visual, rectMoreOrLessEquals(Rect.lerp(start, end, frame / 60)!));
    }
    expect((builds, render.layouts, render.paints), initial);
    expect(render.size, const Size(400, 800));
  });

  testWidgets(
    'launch transition layer builds RetainedWindowMotion and retains layout across frames',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final request = AppLaunchRequest(
        requestId: 42,
        appName: 'Test App',
        iconPath: null,
        expectedAppIds: ['test.app'],
        existingObjectIds: const [],
      );
      final completed = <(int, int)>[];
      Widget buildScene({DenialWindow? window}) => DenialLocalizationScope(
        locale: const Locale('en'),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: ShellTheme(
            data: const ShellThemeData(),
            child: Stack(
              children: [
                LaunchTransitionLayer(
                  request: request,
                  window: window,
                  onCompleted: (reqId, objId) => completed.add((reqId, objId)),
                ),
              ],
            ),
          ),
        ),
      );

      await tester.pumpWidget(buildScene());
      expect(find.byType(RetainedWindowMotion), findsNWidgets(2));
      expect(find.byType(RetainedScale), findsOneWidget);

      // Pump several frames of zoom animation
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(find.byType(RetainedWindowMotion), findsNWidgets(2));
      }
      expect(completed, isEmpty);

      // Supply matching window
      const window = DenialWindow(
        objectId: 100,
        objectKind: 'xdg_toplevel',
        surfaceId: 1,
        windowId: 1,
        textureId: 1,
        title: 'Test App',
        appId: 'test.app',
        width: 400,
        height: 800,
        surfaceX: 0,
        surfaceY: 0,
        surfaceWidth: 400,
        surfaceHeight: 800,
        textureSourceX: 0,
        textureSourceY: 0,
        textureSourceWidth: 400,
        textureSourceHeight: 800,
        geometryX: 0,
        geometryY: 0,
        geometryWidth: 400,
        geometryHeight: 800,
        monitorId: 1,
        transform: 0,
        scale120: 120,
      );

      await tester.pumpWidget(buildScene(window: window));
      await tester.pumpAndSettle();
      expect(completed, equals([(42, 100)]));
    },
  );

  testWidgets(
    'existing window launch fast-paths to single RetainedWindowMotion and completes',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const window = DenialWindow(
        objectId: 200,
        objectKind: 'xdg_toplevel',
        surfaceId: 2,
        windowId: 2,
        textureId: 2,
        title: 'Running App',
        appId: 'running.app',
        width: 400,
        height: 800,
        surfaceX: 0,
        surfaceY: 0,
        surfaceWidth: 400,
        surfaceHeight: 800,
        textureSourceX: 0,
        textureSourceY: 0,
        textureSourceWidth: 400,
        textureSourceHeight: 800,
        geometryX: 0,
        geometryY: 0,
        geometryWidth: 400,
        geometryHeight: 800,
        monitorId: 1,
        transform: 0,
        scale120: 120,
      );
      final request = AppLaunchRequest(
        requestId: 43,
        appName: 'Running App',
        iconPath: null,
        expectedAppIds: ['running.app'],
        existingObjectIds: const [200],
        targetObjectId: 200,
      );
      final completed = <(int, int)>[];
      await tester.pumpWidget(
        DenialLocalizationScope(
          locale: const Locale('en'),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: ShellTheme(
              data: const ShellThemeData(),
              child: Stack(
                children: [
                  LaunchTransitionLayer(
                    request: request,
                    window: window,
                    onCompleted: (reqId, objId) => completed.add((reqId, objId)),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.byType(RetainedWindowMotion), findsOneWidget);
      expect(find.byType(WindowSurface), findsOneWidget);

      await tester.pumpAndSettle();
      expect(completed, equals([(43, 200)]));
    },
  );
}

class _Probe extends LeafRenderObjectWidget {
  @override
  RenderObject createRenderObject(BuildContext context) => _RenderProbe();
}

class _RenderProbe extends RenderBox {
  int layouts = 0;
  int paints = 0;
  @override
  void performLayout() {
    layouts++;
    size = constraints.biggest;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    paints++;
    context.canvas.drawRect(
      offset & size,
      Paint()..color = const Color(0xffabcdef),
    );
  }
}
