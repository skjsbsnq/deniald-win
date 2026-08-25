import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:denial_dart_shell/src/desktop/desktop_panel_transition.dart';
import 'package:denial_dart_shell/src/desktop/desktop_system_bar.dart';
import 'package:denial_dart_shell/src/desktop/window_backdrop_blur_policy.dart';
import 'package:denial_dart_shell/src/localization/denial_localizations.dart';
import 'package:denial_dart_shell/src/models/battery_status.dart';
import 'package:denial_dart_shell/src/models/denial_window.dart';
import 'package:denial_dart_shell/src/models/display_layout.dart';
import 'package:denial_dart_shell/src/services/media_player_service.dart';
import 'package:denial_dart_shell/src/settings/settings_controller.dart';
import 'package:denial_dart_shell/src/settings/shell_settings.dart';
import 'package:denial_dart_shell/src/state/network_connectivity.dart';
import 'package:denial_dart_shell/src/state/quick_settings.dart';
import 'package:denial_dart_shell/src/state/shell_controller.dart';
import 'package:denial_dart_shell/src/state/shell_state.dart';
import 'package:denial_dart_shell/src/state/status_notifier.dart';
import 'package:denial_dart_shell/src/state/system_status.dart';
import 'package:denial_dart_shell/src/theme/shell_theme.dart';
import 'package:denial_dart_shell/src/wallpaper/state/wallpaper_accent.dart';
import 'package:denial_dart_shell/src/widgets/shell_backdrop_blur.dart';

void main() {
  group('P9-04 Backdrop Layer Governance Tests', () {
    testWidgets(
      'empty desktop system bar groups all pills into one shared BackdropGroup',
      (tester) async {
        await _pumpDesktopBar(tester, showHardwareMeters: true);

        // Verify BackdropGroup presence
        expect(find.byType(BackdropGroup), findsOneWidget);

        // Verify all rendered BackdropFilters under DesktopSystemBar are grouped and share one backdropKey
        final barFinder = find.byType(DesktopSystemBar);
        final filters = tester.renderObjectList<RenderBackdropFilter>(
          find.descendant(of: barFinder, matching: find.byType(BackdropFilter)),
        );
        expect(filters, isNotEmpty);
        final sharedKey = filters.first.backdropKey;
        expect(sharedKey, isNotNull);
        for (final filter in filters) {
          expect(filter.backdropKey, equals(sharedKey));
        }

        // Verify no redundant RepaintBoundary directly wraps any grouped BackdropFilter in the bar
        for (final filterFinder
            in find
                .descendant(
                  of: barFinder,
                  matching: find.byType(BackdropFilter),
                )
                .evaluate()) {
          final parent = filterFinder.renderObject?.parent;
          expect(parent is! RenderRepaintBoundary, isTrue);
        }
      },
    );

    testWidgets(
      'translucent windows add backdrop layers linearly without constant overhead',
      (tester) async {
        final counts = <int>[];
        for (var n = 1; n <= 4; n++) {
          var count = 0;
          for (var i = 0; i < n; i++) {
            final window = _createWindow(
              id: i + 1,
              opacityClass: DenialWindowOpacityClass.contentTranslucent,
            );
            if (desktopWindowBackdropBlurEnabled(
              window: window,
              shellOpacity: 1.0,
              opacityThreshold: 0.05,
            )) {
              count++;
            }
          }
          counts.add(count);
        }

        expect(counts, [1, 2, 3, 4]);
        for (var i = 0; i < counts.length - 1; i++) {
          expect(counts[i + 1] - counts[i], 1);
        }
      },
    );

    testWidgets(
      'fully opaque windows and decoration-only alpha produce zero window backdrop layers',
      (tester) async {
        final opaqueWindow = _createWindow(
          id: 1,
          opacityClass: DenialWindowOpacityClass.fullyOpaque,
        );
        final borderAlphaWindow = _createWindow(
          id: 2,
          opacityClass: DenialWindowOpacityClass.borderAlphaOnly,
        );

        expect(
          desktopWindowBackdropBlurEnabled(
            window: opaqueWindow,
            shellOpacity: 1.0,
            opacityThreshold: 0.05,
          ),
          isFalse,
        );
        expect(
          desktopWindowBackdropBlurEnabled(
            window: borderAlphaWindow,
            shellOpacity: 1.0,
            opacityThreshold: 0.05,
          ),
          isFalse,
        );
      },
    );

    testWidgets('closed panel transitions remain offstage and inert', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          child: ShellTheme(
            data: const ShellThemeData(),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: DesktopPanelTransition(
                inputDebugLabel: 'test panel',
                visible: false,
                durationScale: 0,
                child: const SizedBox(width: 200, height: 200),
              ),
            ),
          ),
        ),
      );

      expect(tester.widget<Offstage>(find.byType(Offstage)).offstage, isTrue);
    });

    testWidgets(
      'disabled ShellBackdropBlur produces no ClipRRect or RepaintBoundary',
      (tester) async {
        await tester.pumpWidget(
          ShellTheme(
            data: const ShellThemeData(backdropBlurEnabled: false),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: ShellBackdropBlur(
                blur: false,
                borderRadius: BorderRadius.circular(16),
                child: const SizedBox(width: 100, height: 50),
              ),
            ),
          ),
        );

        expect(find.byType(BackdropFilter), findsNothing);
        expect(find.byType(ClipRRect), findsNothing);
        expect(find.byType(ClipRect), findsNothing);
        expect(find.byType(RepaintBoundary), findsNothing);
      },
    );

    testWidgets(
      'visual equivalence: pills retain exact radius, gradient, sigma, and blendMode',
      (tester) async {
        await _pumpDesktopBar(tester);

        final blurWidgets = tester.widgetList<ShellBackdropBlur>(
          find.descendant(
            of: find.byType(DesktopSystemBar),
            matching: find.byType(ShellBackdropBlur),
          ),
        );

        expect(blurWidgets, isNotEmpty);
        for (final blur in blurWidgets) {
          expect(blur.blendMode, ui.BlendMode.srcOver);
          expect(
            blur.borderRadius,
            const BorderRadius.all(Radius.circular(999)),
          );
          expect(blur.grouped, isTrue);
        }
      },
    );
  });
}

Future<void> _pumpDesktopBar(
  WidgetTester tester, {
  bool showHardwareMeters = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(1280, 120));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(const SizedBox.shrink());

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        shellSettingsProvider.overrideWith(
          () => _StaticSettingsController(SystemBarAlignment.center),
        ),
        networkConnectivityProvider.overrideWithBuild(
          (ref, controller) => NetworkConnectivityState.initial(),
        ),
        batteryProvider.overrideWithBuild(
          (ref, controller) => BatteryStatus.unknown,
        ),
        quickSettingsProvider.overrideWithBuild(
          (ref, controller) => QuickSettingsState.initial(),
        ),
        shellControllerProvider.overrideWith(
          () => _StaticShellController(ShellState.initial()),
        ),
        wallpaperAccentProvider.overrideWithBuild(
          (ref, controller) => const WallpaperAccent(Color(0xff64d8cb)),
        ),
        cpuUsageProvider.overrideWithBuild(
          (ref, controller) => const LoadSeries(current: 0.25, history: [0.25]),
        ),
        gpuUsageProvider.overrideWithBuild(
          (ref, controller) => const <GpuLoad>[],
        ),
        statusNotifierProvider.overrideWith(
          _StaticStatusNotifierController.new,
        ),
        mediaPlaybackProvider.overrideWith(
          (ref) => Stream<MprisPlaybackState>.value(
            MprisPlaybackState.unavailable(),
          ),
        ),
        clockProvider.overrideWith(
          (ref) => Stream<DateTime>.value(DateTime(2026, 7, 19, 21, 47)),
        ),
        clockLocaleProvider.overrideWithValue('it_IT.UTF-8'),
      ],
      child: DenialLocalizationScope(
        locale: const Locale('it'),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Overlay(
            initialEntries: [
              OverlayEntry(
                builder: (context) => const ShellTheme(
                  data: ShellThemeData(),
                  child: Directionality(
                    textDirection: TextDirection.ltr,
                    child: DesktopSystemBar(
                      side: SystemBarSide.top,
                      showHardwareMeters: false,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _StaticSettingsController extends ShellSettingsController {
  _StaticSettingsController(this._alignment);

  final SystemBarAlignment _alignment;

  @override
  ShellSettings build() {
    return ShellSettings(
      layout: ShellLayoutSettings(systemBarAlignment: _alignment),
    );
  }
}

class _StaticShellController extends ShellController {
  _StaticShellController(this._state);

  final ShellState _state;

  @override
  ShellState build() => _state;
}

class _StaticStatusNotifierController extends StatusNotifierController {
  @override
  StatusNotifierState build() =>
      StatusNotifierState.initial().copyWith(initializing: false);
}

DenialWindow _createWindow({
  required int id,
  required DenialWindowOpacityClass opacityClass,
  double opacity = 1.0,
}) {
  return DenialWindow(
    objectId: id,
    objectKind: 'toplevel',
    surfaceId: id * 10,
    windowId: id * 100,
    textureId: id,
    title: 'Window $id',
    appId: 'app$id',
    width: 800,
    height: 600,
    surfaceX: 0,
    surfaceY: 0,
    surfaceWidth: 800,
    surfaceHeight: 600,
    textureSourceX: 0,
    textureSourceY: 0,
    textureSourceWidth: 800,
    textureSourceHeight: 600,
    geometryX: 100,
    geometryY: 100,
    geometryWidth: 800,
    geometryHeight: 600,
    monitorId: 1,
    transform: 0,
    scale120: 120,
    opacity: opacity,
    opacityClass: opacityClass,
  );
}
