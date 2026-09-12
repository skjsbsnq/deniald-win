import 'package:denial_dart_shell/src/local_apps/local_flutter_application.dart';
import 'package:denial_dart_shell/src/models/denial_window.dart';
import 'package:denial_dart_shell/src/theme/shell_theme.dart';
import 'package:denial_dart_shell/src/widgets/shell_backdrop_blur.dart';
import 'package:denial_dart_shell/src/widgets/window_content_rect.dart';
import 'package:denial_dart_shell/src/widgets/window_texture_rect.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

DenialSurfaceLayer _layer({
  required int surfaceId,
  int popupRootSurfaceId = 0,
}) {
  return DenialSurfaceLayer(
    surfaceId: surfaceId,
    parentSurfaceId: 0,
    popupRootSurfaceId: popupRootSurfaceId,
    role: popupRootSurfaceId > 0
        ? DenialSurfaceRole.popup
        : DenialSurfaceRole.root,
    textureId: surfaceId + 100,
    width: 400,
    height: 300,
    surfaceX: 0,
    surfaceY: 0,
    surfaceWidth: 400,
    surfaceHeight: 300,
    textureSourceX: 0,
    textureSourceY: 0,
    textureSourceWidth: 400,
    textureSourceHeight: 300,
    transform: 0,
    scale120: 120,
    compositionOrder: surfaceId,
  );
}

DenialWindow _window({
  String appId = 'denia-home',
  DenialWindowContentKind contentKind = DenialWindowContentKind.surfaceTree,
  DenialWindowOpacityClass opacityClass =
      DenialWindowOpacityClass.contentTranslucent,
  List<DenialSurfaceLayer> surfaceLayers = const <DenialSurfaceLayer>[],
}) {
  return DenialWindow(
    objectId: 7,
    objectKind: 'xdg',
    surfaceId: 17,
    windowId: 27,
    textureId: 37,
    title: 'Window',
    appId: appId,
    width: 400,
    height: 300,
    surfaceX: 0,
    surfaceY: 0,
    surfaceWidth: 400,
    surfaceHeight: 300,
    textureSourceX: 0,
    textureSourceY: 0,
    textureSourceWidth: 400,
    textureSourceHeight: 300,
    geometryX: 0,
    geometryY: 0,
    geometryWidth: 400,
    geometryHeight: 300,
    monitorId: 0,
    transform: 0,
    scale120: 120,
    surfaceLayers: surfaceLayers,
    contentKind: contentKind,
    opacityClass: opacityClass,
  );
}

Widget _host(Widget child, {ShellThemeData theme = const ShellThemeData()}) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: MediaQuery(
      data: const MediaQueryData(),
      child: ShellTheme(
        data: theme,
        child: Center(child: SizedBox(width: 400, height: 300, child: child)),
      ),
    ),
  );
}

void main() {
  const theme = ShellThemeData();

  testWidgets(
    'a lone texture surface resolves the one-pass alpha-threshold config',
    (tester) async {
      // A system-owned window draws no shell status bar, so with a single
      // visible surface the blur child provably contains exactly one external
      // surface and may promise the engine's fused composite.
      await tester.pumpWidget(
        _host(
          WindowTextureRect(
            window: _window(
              surfaceLayers: <DenialSurfaceLayer>[_layer(surfaceId: 1)],
            ),
          ),
        ),
      );

      final blur = tester.widget<ShellBackdropBlur>(
        find.byType(ShellBackdropBlur),
      );
      expect(blur.blur, isTrue);
      expect(blur.useWindowAlphaThreshold, isTrue);
      expect(blur.singleWindowSurface, isTrue);
      final backdrop = tester.widget<BackdropFilter>(
        find.byType(BackdropFilter),
      );
      expect(backdrop.enabled, isTrue);
      expect(
        backdrop.filterConfig,
        same(theme.singleSurfaceWindowBackdropBlurFilterConfig),
      );
    },
  );

  testWidgets('a shell status bar keeps the two-pass config', (tester) async {
    // User applications get a shell-drawn status bar prepended inside the
    // blur child, so the single-surface promise no longer holds even though
    // the window itself carries exactly one texture.
    await tester.pumpWidget(
      _host(
        WindowTextureRect(
          window: _window(
            appId: 'org.example.app',
            surfaceLayers: <DenialSurfaceLayer>[_layer(surfaceId: 1)],
          ),
        ),
      ),
    );

    final blur = tester.widget<ShellBackdropBlur>(
      find.byType(ShellBackdropBlur),
    );
    expect(blur.singleWindowSurface, isFalse);
    final backdrop = tester.widget<BackdropFilter>(find.byType(BackdropFilter));
    expect(backdrop.filterConfig, same(theme.windowBackdropBlurFilterConfig));
  });

  testWidgets('a second visible surface keeps the two-pass config', (
    tester,
  ) async {
    // Popup layers share this blur child, so a root plus a popup is already
    // two external surfaces.
    await tester.pumpWidget(
      _host(
        WindowTextureRect(
          window: _window(
            surfaceLayers: <DenialSurfaceLayer>[
              _layer(surfaceId: 1),
              _layer(surfaceId: 2, popupRootSurfaceId: 1),
            ],
          ),
        ),
      ),
    );

    final blur = tester.widget<ShellBackdropBlur>(
      find.byType(ShellBackdropBlur),
    );
    expect(blur.singleWindowSurface, isFalse);
    final backdrop = tester.widget<BackdropFilter>(find.byType(BackdropFilter));
    expect(backdrop.filterConfig, same(theme.windowBackdropBlurFilterConfig));
  });

  testWidgets('a fully opaque window keeps the filter unmounted', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        WindowTextureRect(
          window: _window(
            opacityClass: DenialWindowOpacityClass.fullyOpaque,
            surfaceLayers: <DenialSurfaceLayer>[_layer(surfaceId: 1)],
          ),
        ),
      ),
    );

    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('a saturated alpha threshold disables the window filter', (
    tester,
  ) async {
    // A threshold of 1.0 is the designed off position: no child alpha can
    // exceed it, so the filter is not mounted at all.
    await tester.pumpWidget(
      _host(
        WindowTextureRect(
          window: _window(
            surfaceLayers: <DenialSurfaceLayer>[_layer(surfaceId: 1)],
          ),
        ),
        theme: const ShellThemeData(backdropBlurOpacityThreshold: 1.0),
      ),
    );

    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('a translucent local app resolves the two-pass window config', (
    tester,
  ) async {
    // Local Flutter content contains no external surface, so it always takes
    // the general alpha-threshold path which resolves the child alpha in a
    // native layer.
    const app = LocalFlutterApplication(
      id: 'org.example.local',
      title: 'Local',
      translucent: true,
      builder: _localAppBuilder,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localFlutterApplicationsProvider.overrideWithValue(
            const <LocalFlutterApplication>[app],
          ),
        ],
        child: _host(
          WindowContentRect(
            window: _window(
              appId: 'org.example.local',
              contentKind: DenialWindowContentKind.localFlutter,
            ),
          ),
        ),
      ),
    );

    final blur = tester.widget<ShellBackdropBlur>(
      find.byType(ShellBackdropBlur),
    );
    expect(blur.blur, isTrue);
    expect(blur.useWindowAlphaThreshold, isTrue);
    expect(blur.singleWindowSurface, isFalse);
    final backdrop = tester.widget<BackdropFilter>(find.byType(BackdropFilter));
    expect(backdrop.enabled, isTrue);
    expect(backdrop.filterConfig, same(theme.windowBackdropBlurFilterConfig));
  });

  testWidgets('an opaque local app keeps the filter unmounted', (tester) async {
    const app = LocalFlutterApplication(
      id: 'org.example.local',
      title: 'Local',
      builder: _localAppBuilder,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localFlutterApplicationsProvider.overrideWithValue(
            const <LocalFlutterApplication>[app],
          ),
        ],
        child: _host(
          WindowContentRect(
            window: _window(
              appId: 'org.example.local',
              contentKind: DenialWindowContentKind.localFlutter,
            ),
          ),
        ),
      ),
    );

    expect(
      tester.widget<ShellBackdropBlur>(find.byType(ShellBackdropBlur)).blur,
      isFalse,
    );
    expect(find.byType(BackdropFilter), findsNothing);
  });
}

Widget _localAppBuilder(BuildContext context, LocalFlutterWindowHandle window) {
  return const SizedBox.expand();
}
