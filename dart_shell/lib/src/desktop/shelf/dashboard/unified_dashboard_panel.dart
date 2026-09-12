import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../state/system_identity.dart';
import '../../../theme/motion.dart';
import '../../../theme/shell_theme.dart';
import '../../../theme/tokens.dart';
import '../../../wallpaper/state/wallpaper_controller.dart';
import '../../../widgets/shell_backdrop_blur.dart';
import 'dashboard_tab_bar.dart';
import 'info/profile_header_card.dart';
import 'views/info_view.dart';
import 'views/system_view.dart';
import 'views/weather_view.dart';

/// Whether the dashboard panel content is currently user-visible.
///
/// The closing spring keeps the page subtree mounted for a few hundred
/// milliseconds after the panel stops being visible, so descendants that
/// react to being "seen" — such as the notification list consuming unread
/// markers — must consult this instead of assuming mounted means visible.
class DashboardPanelVisibility extends InheritedWidget {
  const DashboardPanelVisibility({
    required this.visible,
    required super.child,
    super.key,
  });

  final bool visible;

  /// Defaults to visible: the panel is the only host today, and a future
  /// host without this scope should keep the legacy seen-means-read
  /// behavior rather than silently swallowing unread state.
  static bool of(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<DashboardPanelVisibility>()
            ?.visible ??
        true;
  }

  @override
  bool updateShouldNotify(DashboardPanelVisibility oldWidget) =>
      visible != oldWidget.visible;
}

/// The unified dashboard panel opened by the clock capsule on the shelf.
///
/// Replaces the single-purpose calendar bubble: a 420 dp docked panel with
/// Info / System / Weather pages behind one capsule tab bar. The panel docks
/// at a fixed height — the screen minus the shelf and margins — on every
/// tab, so it always opens fully expanded; each page keeps its own scroll
/// physics inside that frame instead of sizing the panel. (A content-sized
/// panel made short pages such as System and Weather open as stubs beside
/// the tall Info page — 2026-09-07 user ruling.) Only the Weather page
/// mounts on demand; Info and System build statically, so nothing polls
/// the network or hardware while the panel is closed (D8) and opening the
/// panel to a non-weather tab never starts a fetch.
class UnifiedDashboardPanel extends ConsumerStatefulWidget {
  const UnifiedDashboardPanel({
    required this.visible,
    this.onDismiss,
    this.shelfHeight = 56.0,
    this.outputRect,
    super.key,
  });

  final bool visible;
  final VoidCallback? onDismiss;
  final double shelfHeight;

  /// The logical rect of the output whose shelf anchors this panel. Null
  /// docks to the full canvas, which is the single-output behavior.
  final Rect? outputRect;

  @override
  ConsumerState<UnifiedDashboardPanel> createState() =>
      _UnifiedDashboardPanelState();
}

class _UnifiedDashboardPanelState extends ConsumerState<UnifiedDashboardPanel>
    with SingleTickerProviderStateMixin {
  static const double _panelWidth = 420;

  // One-shot idle warm-up delay: long enough to stay behind the startup
  // burst, short enough that the first clock click lands on an inflated tree.
  static const Duration _warmupDelay = Duration(seconds: 1);

  late final AnimationController _controller;
  late final FocusNode _contentFocus;
  DashboardTab _tab = DashboardTab.info;
  bool _hasInflated = false;
  Timer? _warmupTimer;

  @override
  void initState() {
    super.initState();
    _hasInflated = widget.visible;
    _controller = AnimationController.unbounded(
      vsync: this,
      value: widget.visible ? 1.0 : 0.0,
    );
    _contentFocus = FocusNode(debugLabel: 'unified-dashboard-panel');
    if (!_hasInflated) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_hasInflated) {
          _warmupTimer = Timer(_warmupDelay, _runWarmup);
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant UnifiedDashboardPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visible != widget.visible) {
      if (widget.visible) {
        _hasInflated = true;
        // An open before the idle delay makes the pending warm-up a no-op;
        // cancel it rather than leave a dead timer on the queue.
        _warmupTimer?.cancel();
        _warmupTimer = null;
        // Taking focus on open lets Escape dismiss the panel and Tab reach
        // the tab bar and page content with the keyboard.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && widget.visible && !_contentFocus.hasFocus) {
            _contentFocus.requestFocus();
          }
        });
      }
      // Reduce-motion users get the end state directly; the settle spring
      // is a purely decorative overshoot.
      if (MediaQuery.disableAnimationsOf(context)) {
        _controller.value = widget.visible ? 1.0 : 0.0;
      } else {
        springTo(
          _controller,
          widget.visible ? 1.0 : 0.0,
          spring: Motion.expressiveSpatialDefault,
          telemetryLabel: 'dashboard_panel_toggle',
        );
      }
    }
  }

  @override
  void dispose() {
    _warmupTimer?.cancel();
    _controller.dispose();
    _contentFocus.dispose();
    super.dispose();
  }

  /// The one-shot idle warm-up: flips the hidden builder branch from
  /// [SizedBox.shrink] to the parked [Offstage] shape so the content subtree
  /// inflates and lays out while the panel is still invisible. The subtree
  /// stays parked — [TickerMode] keeps it from ticking or rebuilding on
  /// provider changes — so this is a one-time cost, not a standing one.
  void _runWarmup() {
    _warmupTimer = null;
    if (!mounted || _hasInflated) {
      return;
    }
    setState(() => _hasInflated = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _precacheInfoImages();
      }
    });
  }

  /// Pre-decodes the Info header's cover and avatar into the shared image
  /// cache before the first open. Read-only warm-up (H3): both providers are
  /// only read, and the precached keys are the exact ones the header's
  /// [Image] widgets resolve, so nothing decodes twice.
  void _precacheInfoImages() {
    final resource = ref
        .read(wallpaperControllerProvider.select((state) => state.assignment))
        .all;
    unawaited(
      precacheImage(
        ProfileHeaderCard.coverImageProvider(context, resource),
        context,
        onError: (_, _) {},
      ),
    );
    // The avatar path resolves asynchronously after the service loads; when
    // it is already known the same FileImage key the header uses warms too.
    final avatarPath = ref.read(systemIdentityProvider).avatarPath;
    if (avatarPath != null) {
      unawaited(
        precacheImage(FileImage(File(avatarPath)), context, onError: (_, _) {}),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      // The page content is lifted out of the builder so the settle spring
      // only rebuilds the blur/scale shell, and wrapped in a RepaintBoundary
      // so the per-tick backdrop re-filter cannot re-paint the content layer.
      builder: (context, child) {
        final progress = _controller.value;
        final hidden = progress <= 0.001 && !widget.visible;
        if (hidden && !_hasInflated) {
          // Stay unmounted until the first open or the idle warm-up so shell
          // startup does not pay the panel's inflate. Once inflated, the
          // subtree parks under Offstage instead of unmounting, so a reopen
          // never re-pays the inflate on the opening frame.
          return const SizedBox.shrink();
        }

        final theme = context.shellTheme;
        final colors = context.shellColors;
        final size = MediaQuery.sizeOf(context);
        // The panel docks to the corner of the anchoring output, not the
        // global canvas corner, so a shelf clone on another output opens its
        // panel beside itself (COR-5).
        final anchorRect = widget.outputRect ?? (Offset.zero & size);
        final clampedProgress = progress.clamp(0.0, 1.0);
        final scale = math.max(0.0, 0.88 + 0.12 * progress);
        final panelRadius = theme.borderRadius(ShellShapeScale.extraLarge);
        final panelWidth = math.min(anchorRect.width - 16.0, _panelWidth);
        // The height is fixed, not a cap the content can shrink under: every
        // tab opens the same fully docked panel and pages scroll inside it.
        final panelHeight = math.max(
          160.0,
          anchorRect.height - widget.shelfHeight - 24.0,
        );

        // The wrapper keeps one shape for the shown and hidden states —
        // switching branches would rebuild the subtree — so parking flips
        // the Offstage flag instead of unmounting. TickerMode parks the
        // subtree's animations and pauses its provider listeners while it is
        // hidden, and Offstage keeps it out of paint, hit-test, semantics,
        // and focus; the backdrop shell costs nothing offstage. ExcludeFocus
        // cuts the parked subtree out of the focus tree — the kept-alive
        // content focus node would otherwise hold primary focus after close
        // (the old unmount released it) and Tab could walk an invisible
        // panel.
        return TickerMode(
          enabled: !hidden,
          child: Offstage(
            offstage: hidden,
            child: ExcludeFocus(
              excluding: hidden,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: widget.onDismiss,
                    child: const SizedBox.expand(),
                  ),
                  Positioned.fromRect(
                    rect: anchorRect,
                    child: Stack(
                      children: [
                        Positioned(
                          right: 8.0,
                          bottom: widget.shelfHeight + 8.0,
                          child: Transform.scale(
                            scale: scale,
                            alignment: Alignment.bottomRight,
                            child: SizedBox(
                              width: panelWidth,
                              height: panelHeight,
                              child: ShellBackdropBlur(
                                strength: clampedProgress,
                                borderRadius: panelRadius,
                                separateChild: true,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: theme.panelColor(
                                      colors.surfaceContainerLow,
                                    ),
                                    borderRadius: panelRadius,
                                    border: Border.all(
                                      color: colors.hairlineSoft,
                                      width: 1.0,
                                    ),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: panelRadius,
                                    child: child,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      child: DashboardPanelVisibility(
        visible: widget.visible,
        child: RepaintBoundary(
          child: Focus(
            focusNode: _contentFocus,
            autofocus: widget.visible,
            child: FocusTraversalGroup(
              child: CallbackShortcuts(
                bindings: <ShortcutActivator, VoidCallback>{
                  const SingleActivator(LogicalKeyboardKey.escape): () =>
                      widget.onDismiss?.call(),
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
                      child: DashboardTabBar(
                        selected: _tab,
                        onSelected: (tab) => setState(() => _tab = tab),
                      ),
                    ),
                    Expanded(child: _TabPageHost(tab: _tab)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Lazily mounts tab pages. A page joins the stack the first time its tab is
/// selected and then stays mounted, so switching back preserves scroll
/// positions and drawer state while closed pages never subscribe — the
/// Weather page in particular mounts (and starts its first fetch, D8) only
/// after the Weather tab is opened, not when the panel opens on Info.
class _TabPageHost extends StatefulWidget {
  const _TabPageHost({required this.tab});

  final DashboardTab tab;

  @override
  State<_TabPageHost> createState() => _TabPageHostState();
}

class _TabPageHostState extends State<_TabPageHost> {
  late final Set<DashboardTab> _mountedTabs = {widget.tab};

  @override
  void didUpdateWidget(covariant _TabPageHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    _mountedTabs.add(widget.tab);
  }

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: widget.tab.index,
      children: [
        for (final tab in DashboardTab.values)
          KeyedSubtree(
            key: ValueKey('dashboard-tab-${tab.name}'),
            child: _mountedTabs.contains(tab)
                ? _buildPage(tab)
                : const SizedBox(),
          ),
      ],
    );
  }

  Widget _buildPage(DashboardTab tab) {
    return switch (tab) {
      DashboardTab.info => const InfoView(),
      DashboardTab.system => const SystemView(),
      DashboardTab.weather => const WeatherView(),
    };
  }
}
