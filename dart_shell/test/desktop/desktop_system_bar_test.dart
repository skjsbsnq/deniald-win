import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:denial_dart_shell/src/desktop/desktop_start_button.dart';
import 'package:denial_dart_shell/src/desktop/desktop_status_cluster.dart';
import 'package:denial_dart_shell/src/desktop/desktop_system_bar.dart';
import 'package:denial_dart_shell/src/desktop/desktop_system_bar_layout.dart';
import 'package:denial_dart_shell/src/desktop/desktop_taskbar.dart';
import 'package:denial_dart_shell/src/desktop/desktop_taskbar_button.dart';
import 'package:denial_dart_shell/src/localization/denial_localizations.dart';
import 'package:denial_dart_shell/src/models/denial_window.dart';
import 'package:denial_dart_shell/src/models/battery_status.dart';
import 'package:denial_dart_shell/src/models/display_layout.dart';
import 'package:denial_dart_shell/src/services/media_player_service.dart';
import 'package:denial_dart_shell/src/settings/settings_controller.dart';
import 'package:denial_dart_shell/src/settings/shell_settings.dart';
import 'package:denial_dart_shell/src/state/network_connectivity.dart';
import 'package:denial_dart_shell/src/state/quick_settings.dart';
import 'package:denial_dart_shell/src/state/shell_controller.dart';
import 'package:denial_dart_shell/src/state/shell_state.dart';
import 'package:denial_dart_shell/src/state/system_status.dart';
import 'package:denial_dart_shell/src/wallpaper/state/wallpaper_accent.dart';
import 'package:denial_dart_shell/src/widgets/shell_backdrop_blur.dart';

void main() {
  testWidgets('cards cluster with tripartite layout over a bare strip', (
    tester,
  ) async {
    await _pumpBar(tester, cpuUsage: 0.23);

    // Transparent canvas: nothing paints a full-strip decoration;
    // start button, status cluster and clock module cards are decorated.
    expect(find.text('21:47'), findsOneWidget);
    expect(find.text('Sun 19 Jul'), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
    expect(find.byType(DesktopStartButton), findsOneWidget);
    expect(find.byType(DesktopStatusCluster), findsOneWidget);
    expect(find.byType(DesktopSystemBarLayout), findsOneWidget);

    final clockRect = tester.getRect(find.text('21:47'));
    expect(clockRect.right, closeTo(1280 - 8 - 12, 1.0));

    // Centered is the Windows 11 default: the Start card sits nowhere near the
    // bar's leading edge.
    expect(
      tester.getRect(find.byType(DesktopStartButton)).left,
      greaterThan(200.0),
    );
  });

  testWidgets('left alignment moves only the cluster, not the trailing zone', (
    tester,
  ) async {
    await _pumpBar(tester, cpuUsage: 0.23);
    final centeredClock = tester.getRect(find.text('21:47'));
    final centeredCluster = tester.getRect(find.byType(DesktopStatusCluster));

    await _pumpBar(
      tester,
      cpuUsage: 0.23,
      alignment: SystemBarAlignment.leading,
    );

    // Every module survives, the trailing zone does not budge, and the Start
    // card lands on the bar's own padding.
    expect(find.byType(DesktopStartButton), findsOneWidget);
    expect(find.byType(DesktopStatusCluster), findsOneWidget);
    expect(find.byType(DesktopSystemBarLayout), findsOneWidget);
    expect(find.text('Sun 19 Jul'), findsOneWidget);
    expect(tester.getRect(find.text('21:47')), centeredClock);
    expect(tester.getRect(find.byType(DesktopStatusCluster)), centeredCluster);
    expect(
      _cardRect(tester, 'system-bar-start-button').left,
      closeTo(8.0, 0.01),
      reason: 'flush against the bar edge padding',
    );
  });

  testWidgets('shows hardware meters when showHardwareMeters is true', (
    tester,
  ) async {
    await _pumpBar(tester, cpuUsage: 0.23, showHardwareMeters: true);

    expect(find.text('21:47'), findsOneWidget);
    expect(find.text('Sun 19 Jul'), findsOneWidget);
    expect(find.text('23%'), findsOneWidget);
    expect(find.byType(DesktopStartButton), findsOneWidget);
    expect(find.byType(DesktopStatusCluster), findsOneWidget);

    final clockRect = tester.getRect(find.text('21:47'));
    final cpuRect = tester.getRect(find.text('23%'));
    expect(clockRect.right, greaterThan(cpuRect.right));
  });

  testWidgets('passes onToggleLauncher callback to DesktopStartButton', (
    tester,
  ) async {
    var launcherToggled = 0;
    await _pumpBar(
      tester,
      cpuUsage: null,
      onToggleLauncher: () => launcherToggled++,
    );

    expect(launcherToggled, 0);
    await tester.tap(find.byType(DesktopStartButton));
    expect(launcherToggled, 1);
  });

  testWidgets('passes onToggleDashboard callback to DesktopStatusCluster', (
    tester,
  ) async {
    var toggled = 0;
    await _pumpBar(tester, cpuUsage: null, onToggleDashboard: () => toggled++);

    expect(toggled, 0);
    await tester.tap(find.byType(DesktopStatusCluster));
    expect(toggled, 1);
  });

  testWidgets(
    'passes onToggleCalendar callback and triggers on tapping clock',
    (tester) async {
      var calendarToggled = 0;
      await _pumpBar(
        tester,
        cpuUsage: null,
        onToggleCalendar: () => calendarToggled++,
      );

      expect(calendarToggled, 0);
      await tester.tap(find.text('21:47'));
      expect(calendarToggled, 1);
    },
  );

  testWidgets('renders properly across all four orientations and hidden mode', (
    tester,
  ) async {
    for (final alignment in SystemBarAlignment.values) {
      // Bottom orientation
      await _pumpBar(
        tester,
        cpuUsage: null,
        side: SystemBarSide.bottom,
        alignment: alignment,
      );
      expect(find.byType(DesktopStartButton), findsOneWidget);
      expect(find.byType(DesktopStatusCluster), findsOneWidget);

      // Left orientation
      await _pumpBar(
        tester,
        cpuUsage: null,
        side: SystemBarSide.left,
        alignment: alignment,
      );
      expect(find.byType(DesktopStartButton), findsOneWidget);
      expect(find.byType(DesktopStatusCluster), findsOneWidget);

      // Right orientation
      await _pumpBar(
        tester,
        cpuUsage: null,
        side: SystemBarSide.right,
        alignment: alignment,
      );
      expect(find.byType(DesktopStartButton), findsOneWidget);
      expect(find.byType(DesktopStatusCluster), findsOneWidget);

      // Top orientation
      await _pumpBar(
        tester,
        cpuUsage: null,
        side: SystemBarSide.top,
        alignment: alignment,
      );
      expect(find.byType(DesktopStartButton), findsOneWidget);
      expect(find.byType(DesktopStatusCluster), findsOneWidget);

      // Hidden orientation yields nothing
      await _pumpBar(
        tester,
        cpuUsage: null,
        side: SystemBarSide.hidden,
        alignment: alignment,
      );
      expect(find.byType(DesktopStartButton), findsNothing);
      expect(find.byType(DesktopStatusCluster), findsNothing);
    }
  });

  testWidgets('a left aligned bar seats window buttons beside the Start card', (
    tester,
  ) async {
    await _pumpBar(
      tester,
      cpuUsage: null,
      side: SystemBarSide.bottom,
      alignment: SystemBarAlignment.leading,
      windows: <DenialWindow>[_testWindow(1), _testWindow(2)],
    );

    final start = _cardRect(tester, 'system-bar-start-button');
    final taskbar = tester.getRect(find.byType(DesktopTaskbar));
    expect(start.left, closeTo(8.0, 0.01), reason: 'flush against the bar');
    expect(
      taskbar.left - start.right,
      closeTo(8.0, 0.01),
      reason: 'window buttons follow one card gap behind the Start card',
    );
  });

  testWidgets('a vertical bar reads left alignment as top alignment', (
    tester,
  ) async {
    await _pumpBar(
      tester,
      cpuUsage: null,
      side: SystemBarSide.left,
      alignment: SystemBarAlignment.leading,
    );
    final leading = _cardRect(tester, 'system-bar-start-button');

    await _pumpBar(
      tester,
      cpuUsage: null,
      side: SystemBarSide.left,
      alignment: SystemBarAlignment.center,
    );
    final centered = _cardRect(tester, 'system-bar-start-button');

    expect(leading.top, closeTo(8.0, 0.01));
    expect(leading.top, lessThan(centered.top));
  });

  testWidgets('fifteen window buttons stay clear of the trailing cluster', (
    tester,
  ) async {
    await _pumpBar(
      tester,
      cpuUsage: null,
      side: SystemBarSide.bottom,
      alignment: SystemBarAlignment.leading,
      windows: <DenialWindow>[for (int i = 1; i <= 15; i += 1) _testWindow(i)],
    );

    expect(find.byType(DesktopTaskbarWindowButton), findsNWidgets(15));
    expect(
      tester.getRect(find.byType(DesktopTaskbar)).right,
      lessThanOrEqualTo(tester.getRect(find.byType(DesktopStatusCluster)).left),
    );
  });

  testWidgets('changing the setting alone moves the cluster', (tester) async {
    await _pumpBar(tester, cpuUsage: null, side: SystemBarSide.bottom);
    final centered = _cardRect(tester, 'system-bar-start-button');

    final container = ProviderScope.containerOf(
      tester.element(find.byType(DesktopSystemBar)),
      listen: false,
    );
    (container.read(shellSettingsProvider.notifier)
            as _StaticSettingsController)
        .applyAlignment(SystemBarAlignment.leading);
    await tester.pumpAndSettle();

    // No re-pump of the tree: the bar watches the preference, so writing it is
    // enough. Moving between the layout's zones does rebuild the cluster, which
    // replays its entrance — visible only when the setting is changed by hand.
    expect(centered.left, greaterThan(8.0));
    expect(
      _cardRect(tester, 'system-bar-start-button').left,
      closeTo(8.0, 0.01),
    );
  });

  testWidgets('the Start card opens the entrance sweep when it leads the bar', (
    tester,
  ) async {
    await _pumpBar(
      tester,
      cpuUsage: null,
      side: SystemBarSide.bottom,
      alignment: SystemBarAlignment.leading,
      settle: false,
    );
    // One frame to let the zero-delay beat fire and start its ticker, then a
    // stretch shorter than the 60 ms stagger so only that beat has moved.
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 40));

    expect(_entranceOpacity(tester, 'system-bar-start-button'), greaterThan(0));
    expect(_entranceOpacity(tester, 'system-bar-clock'), 0);
    await tester.pumpAndSettle();

    // Centered, the sweep runs the other way: the clock leads it and the Start
    // card closes it.
    await _pumpBar(
      tester,
      cpuUsage: null,
      side: SystemBarSide.bottom,
      alignment: SystemBarAlignment.center,
      settle: false,
    );
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 40));

    expect(_entranceOpacity(tester, 'system-bar-clock'), greaterThan(0));
    expect(_entranceOpacity(tester, 'system-bar-start-button'), 0);
    await tester.pumpAndSettle();
  });

  testWidgets('cards use the shared frosted-surface opacity', (tester) async {
    await _pumpBar(tester, cpuUsage: 0.23, showHardwareMeters: true);

    final clock = tester.widget<Text>(find.text('21:47'));
    final dateStyle = tester.widget<AnimatedDefaultTextStyle>(
      find.ancestor(
        of: find.text('Sun 19 Jul'),
        matching: find.byType(AnimatedDefaultTextStyle),
      ),
    );
    expect(clock.style?.leadingDistribution, TextLeadingDistribution.even);
    expect(dateStyle.style.leadingDistribution, TextLeadingDistribution.even);

    final cards = tester
        .widgetList<AnimatedContainer>(
          find.descendant(
            of: find.byType(ShellBackdropBlur),
            matching: find.byType(AnimatedContainer),
          ),
        )
        // Pills nested inside a card — hover circles, icon buttons — paint a
        // flat colour. The frosted card surface is the one with the gradient.
        .where((card) => (card.decoration as BoxDecoration?)?.gradient != null)
        .toList();
    expect(cards, isNotEmpty);
    for (final card in cards) {
      final decoration = card.decoration! as BoxDecoration;
      final gradient = decoration.gradient! as LinearGradient;
      for (final color in gradient.colors) {
        expect(color.a, closeTo(0.75, 1e-6));
      }
    }
  });

  testWidgets('the CPU card waits for a real sample', (tester) async {
    await _pumpBar(tester, cpuUsage: null, showHardwareMeters: true);

    expect(find.text('21:47'), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
  });

  testWidgets('the CPU card hosts the load sparkline', (tester) async {
    await _pumpBar(tester, cpuUsage: 0.23, showHardwareMeters: true);

    expect(_sparklineFinder, findsOneWidget);
    expect(find.text('CPU'), findsOneWidget);
  });

  testWidgets('every autodetected GPU gets a labelled sparkline card', (
    tester,
  ) async {
    await _pumpBar(
      tester,
      cpuUsage: 0.23,
      showHardwareMeters: true,
      gpus: const [
        GpuLoad(
          id: 'card2',
          label: 'AMD',
          series: LoadSeries(current: 0.42, history: [0.3, 0.42]),
        ),
        GpuLoad(
          id: 'nvml0',
          label: 'NV',
          series: LoadSeries(current: 0.87, history: [0.9, 0.87]),
        ),
      ],
    );

    expect(_sparklineFinder, findsNWidgets(3));
    expect(find.text('AMD'), findsOneWidget);
    expect(find.text('NV'), findsOneWidget);
    expect(find.text('42%'), findsOneWidget);
    expect(find.text('87%'), findsOneWidget);

    // GPU cards sit left of the CPU card, which sits left of the clock.
    final amdRect = tester.getRect(find.text('AMD'));
    final nvRect = tester.getRect(find.text('NV'));
    final cpuRect = tester.getRect(find.text('CPU'));
    final clockRect = tester.getRect(find.text('21:47'));
    expect(amdRect.right, lessThan(nvRect.left));
    expect(nvRect.right, lessThan(cpuRect.left));
    expect(cpuRect.right, lessThan(clockRect.left));
  });

  testWidgets('CPU and GPU temperatures appear only when sensors report them', (
    tester,
  ) async {
    await _pumpBar(
      tester,
      cpuUsage: 0.23,
      cpuTemperatureC: 54.4,
      showHardwareMeters: true,
      gpus: const [
        GpuLoad(
          id: 'card2',
          label: 'AMD',
          series: LoadSeries(
            current: 0.42,
            history: [0.3, 0.42],
            temperatureC: 62.5,
          ),
        ),
        GpuLoad(
          id: 'nvml0',
          label: 'NV',
          series: LoadSeries(current: 0.87, history: [0.9, 0.87]),
        ),
      ],
    );

    expect(find.text('54°C', findRichText: true), findsOneWidget);
    expect(find.text('63°C', findRichText: true), findsOneWidget);
    expect(find.textContaining('°C', findRichText: true), findsNWidgets(2));
  });

  group('sparklinePoints', () {
    const size = Size(44, 14);

    test('is empty without history or space', () {
      expect(sparklinePoints(const [], size), isEmpty);
      expect(sparklinePoints(const [0.5], Size.zero), isEmpty);
    });

    test('right-aligns the newest sample', () {
      final points = sparklinePoints(const [0.25, 0.5], size);
      expect(points, hasLength(2));
      expect(points.last.dx, size.width);
      expect(
        points.first.dx,
        size.width - size.width / (LoadSeries.capacity - 1),
      );
    });

    test('maps load onto the vertical axis and clamps wild values', () {
      final points = sparklinePoints(const [0.0, -1.0, 2.0, 1.0], size);
      expect(points[0].dy, size.height);
      expect(points[1].dy, size.height);
      expect(points[2].dy, 0.0);
      expect(points[3].dy, 0.0);
    });

    test('a full history spans the whole width', () {
      final history = List<double>.filled(LoadSeries.capacity, 0.5);
      final points = sparklinePoints(history, size);
      expect(points.first.dx, closeTo(0.0, 1e-9));
      expect(points.last.dx, size.width);
    });
  });

  testWidgets('preview renders a PNG when DENIAL_BAR_PREVIEW_DIR is set', (
    tester,
  ) async {
    final previewDir = Platform.environment['DENIAL_BAR_PREVIEW_DIR'];
    if (previewDir == null || previewDir.isEmpty) {
      return;
    }

    // Load the real bar font so the preview shows glyphs instead of the
    // test-default block font.
    await tester.runAsync(() async {
      for (final weight in ['Regular', 'Medium', 'Bold']) {
        final bytes = await File(
          'assets/fonts/JetBrainsMono-$weight.ttf',
        ).readAsBytes();
        final loader = FontLoader('JetBrainsMono')
          ..addFont(Future.value(ByteData.sublistView(bytes)));
        await loader.load();
      }
    });

    final wave = List<double>.generate(
      LoadSeries.capacity,
      (i) =>
          0.18 +
          0.55 * (0.5 + 0.5 * math.sin(i / 4.0)) * (i % 7 == 0 ? 1.0 : 0.6),
    );
    List<double> shifted(double phase, double scale) => [
      for (final value in wave) (value * scale + phase).clamp(0.0, 1.0),
    ];
    await _pumpBar(
      tester,
      cpuUsage: 0.23,
      cpuTemperatureC: 54,
      history: wave,
      gpus: [
        GpuLoad(
          id: 'card2',
          label: 'AMD',
          series: LoadSeries(
            current: 0.42,
            history: shifted(0.25, 0.8),
            temperatureC: 63,
          ),
        ),
        GpuLoad(
          id: 'nvml0',
          label: 'NV',
          series: LoadSeries(
            current: 0.87,
            history: shifted(0.05, 1.2),
            temperatureC: 71,
          ),
        ),
      ],
      withWallpaper: true,
      showHardwareMeters: true,
    );
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_previewBoundaryKey),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2.0);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final file = File('$previewDir/system_bar_preview.png');
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    });
  });
}

const _previewBoundaryKey = Key('system-bar-preview');

final Finder _sparklineFinder = find.byWidgetPredicate(
  (widget) =>
      widget is CustomPaint &&
      '${widget.painter.runtimeType}' == '_SparklinePainter',
);

Future<void> _pumpBar(
  WidgetTester tester, {
  required double? cpuUsage,
  double? cpuTemperatureC,
  List<double>? history,
  List<GpuLoad> gpus = const <GpuLoad>[],
  bool withWallpaper = false,
  bool showHardwareMeters = false,
  SystemBarSide side = SystemBarSide.top,
  SystemBarAlignment alignment = SystemBarAlignment.center,
  List<DenialWindow> windows = const <DenialWindow>[],
  bool settle = true,
  VoidCallback? onToggleLauncher,
  VoidCallback? onToggleDashboard,
  VoidCallback? onToggleCalendar,
}) async {
  // A vertical bar needs a tall strip; horizontal keeps the wide one the pixel
  // assertions are measured against. The vertical strip is deliberately wider
  // than a real bar: the clock module has no vertical layout and overflows a
  // realistic thickness, which is an upstream gap this task does not touch.
  final verticalStrip = !side.isHorizontal && side != SystemBarSide.hidden;
  await tester.binding.setSurfaceSize(
    verticalStrip ? const Size(320, 900) : const Size(1280, 120),
  );
  addTearDown(() => tester.binding.setSurfaceSize(null));
  // Overlay entries build once and keep their child, so a second _pumpBar in the
  // same test would silently keep the first one's bar. Tear the tree down first.
  await tester.pumpWidget(const SizedBox.shrink());
  final cpuLoad = cpuUsage == null
      ? LoadSeries.empty
      : LoadSeries(
          current: cpuUsage,
          history: history ?? <double>[0.1, 0.4, 0.2, cpuUsage],
          temperatureC: cpuTemperatureC,
        );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        shellSettingsProvider.overrideWith(
          () => _StaticSettingsController(alignment),
        ),
        // The status cluster reads three live services. Serving them statically
        // keeps NetworkManager, UPower and PipeWire — and the retry timers they
        // leave pending — out of a layout test.
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
          () => _StaticShellController(
            ShellState.initial().copyWith(windows: windows),
          ),
        ),
        wallpaperAccentProvider.overrideWithBuild(
          (ref, controller) => const WallpaperAccent(Color(0xff64d8cb)),
        ),
        cpuUsageProvider.overrideWithBuild((ref, controller) => cpuLoad),
        gpuUsageProvider.overrideWithBuild((ref, controller) => gpus),
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
          // The Start card and the status cluster carry Tooltips, which need an
          // Overlay to float in.
          child: Overlay(
            initialEntries: [
              OverlayEntry(
                builder: (context) => RepaintBoundary(
                  key: _previewBoundaryKey,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: withWallpaper
                              ? const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color(0xff0f2350),
                                    Color(0xff3b1f5e),
                                    Color(0xffb0326a),
                                  ],
                                )
                              : null,
                          color: withWallpaper ? null : const Color(0xff101318),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        top: 0,
                        right: verticalStrip ? null : 0,
                        bottom: verticalStrip ? 0 : null,
                        width: verticalStrip ? 260 : null,
                        height: verticalStrip ? null : 32,
                        child: DesktopSystemBar(
                          side: side,
                          showHardwareMeters: showHardwareMeters,
                          onToggleLauncher: onToggleLauncher,
                          onToggleDashboard: onToggleDashboard,
                          onToggleCalendar: onToggleCalendar,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  // Let the entrance stagger, springs and value tweens settle.
  if (settle) {
    await tester.pumpAndSettle();
  }
}

/// Serves a fixed shell state so the taskbar sees a known window list.
class _StaticShellController extends ShellController {
  _StaticShellController(this._state);

  final ShellState _state;

  @override
  ShellState build() => _state;
}

/// Serves a fixed settings projection. Overriding [build] also keeps the real
/// controller's settings store and its debounced write out of the test.
class _StaticSettingsController extends ShellSettingsController {
  _StaticSettingsController(this._alignment);

  final SystemBarAlignment _alignment;

  @override
  ShellSettings build() {
    return ShellSettings(
      layout: ShellLayoutSettings(systemBarAlignment: _alignment),
    );
  }

  void applyAlignment(SystemBarAlignment value) {
    state = state.copyWith(
      layout: state.layout.copyWith(systemBarAlignment: value),
    );
  }
}

/// Opacity of the entrance transition wrapping the card keyed [key], which is
/// zero until that card's beat arrives.
double _entranceOpacity(WidgetTester tester, String key) {
  return tester
      .widgetList<Opacity>(
        find.descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.byType(Opacity),
        ),
      )
      .first
      .opacity;
}

/// Frosted surface of the card keyed [key]. The card pads its content by 12px,
/// so the pill's own edge is what a screenshot measures against the bar.
Rect _cardRect(WidgetTester tester, String key) {
  return tester.getRect(
    find
        .descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.byType(ShellBackdropBlur),
        )
        .first,
  );
}

DenialWindow _testWindow(int objectId) {
  return DenialWindow(
    objectId: objectId,
    objectKind: 'toplevel',
    surfaceId: objectId * 10,
    windowId: objectId * 100,
    textureId: objectId,
    title: 'Window $objectId',
    appId: 'app$objectId',
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
  );
}
