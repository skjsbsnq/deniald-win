import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/motion.dart';
import '../../../theme/shell_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/shell_backdrop_blur.dart';
import 'dashboard_tab_bar.dart';
import 'views/info_view.dart';
import 'views/system_view.dart';
import 'views/weather_view.dart';

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
    super.key,
  });

  final bool visible;
  final VoidCallback? onDismiss;
  final double shelfHeight;

  @override
  ConsumerState<UnifiedDashboardPanel> createState() =>
      _UnifiedDashboardPanelState();
}

class _UnifiedDashboardPanelState extends ConsumerState<UnifiedDashboardPanel>
    with SingleTickerProviderStateMixin {
  static const double _panelWidth = 420;

  late final AnimationController _controller;
  late final FocusNode _contentFocus;
  DashboardTab _tab = DashboardTab.info;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController.unbounded(
      vsync: this,
      value: widget.visible ? 1.0 : 0.0,
    );
    _contentFocus = FocusNode(debugLabel: 'unified-dashboard-panel');
  }

  @override
  void didUpdateWidget(covariant UnifiedDashboardPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visible != widget.visible) {
      if (widget.visible) {
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
    _controller.dispose();
    _contentFocus.dispose();
    super.dispose();
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
        if (progress <= 0.001 && !widget.visible) {
          return const SizedBox.shrink();
        }

        final theme = context.shellTheme;
        final colors = context.shellColors;
        final size = MediaQuery.sizeOf(context);
        final clampedProgress = progress.clamp(0.0, 1.0);
        final scale = math.max(0.0, 0.88 + 0.12 * progress);
        final panelRadius = theme.borderRadius(ShellShapeScale.extraLarge);
        final panelWidth = math.min(size.width - 16.0, _panelWidth);
        // The height is fixed, not a cap the content can shrink under: every
        // tab opens the same fully docked panel and pages scroll inside it.
        final panelHeight = math.max(
          160.0,
          size.height - widget.shelfHeight - 24.0,
        );

        return Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: widget.onDismiss,
              child: const SizedBox.expand(),
            ),
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
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: theme.panelColor(colors.surfaceContainerLow),
                        borderRadius: panelRadius,
                        border: Border.all(
                          color: colors.hairlineSoft,
                          width: 1.0,
                        ),
                      ),
                      child: ClipRRect(borderRadius: panelRadius, child: child),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
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
