import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../../localization/denial_localizations.dart';
import '../../../theme/motion.dart';
import '../../../theme/shell_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/shell_hover_pill.dart';

enum DashboardTab { info, system, weather }

/// Top capsule switcher of the dashboard panel: Info / System / Weather.
///
/// The selected pill is carried by a spring so its edges stretch during a
/// switch, and the mouse wheel walks through the three pages without clicks.
class DashboardTabBar extends StatefulWidget {
  const DashboardTabBar({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final DashboardTab selected;

  final ValueChanged<DashboardTab> onSelected;

  static const double barHeight = 52;

  @override
  State<DashboardTabBar> createState() => _DashboardTabBarState();
}

class _DashboardTabBarState extends State<DashboardTabBar>
    with SingleTickerProviderStateMixin {
  // The pill tracks the normalized tab position (0-2) so it follows the
  // equally divided entry widths instead of a fixed pixel stride.
  static const int _tabCount = 3;

  late final AnimationController _pill = AnimationController.unbounded(
    vsync: this,
  );

  @override
  void initState() {
    super.initState();
    _pill.value = widget.selected.index.toDouble();
  }

  @override
  void didUpdateWidget(covariant DashboardTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected) {
      // Reduce-motion users get the selection pill in place; the spring is
      // decorative overshoot.
      if (MediaQuery.disableAnimationsOf(context)) {
        _pill.value = widget.selected.index.toDouble();
      } else {
        springTo(
          _pill,
          widget.selected.index.toDouble(),
          spring: Motion.expressiveSpatialFast,
          telemetryLabel: 'dashboard_tab_pill',
        );
      }
    }
  }

  @override
  void dispose() {
    _pill.dispose();
    super.dispose();
  }

  void _selectNearest(int delta) {
    final next = (widget.selected.index + delta).clamp(
      0,
      DashboardTab.values.length - 1,
    );
    if (next != widget.selected.index) {
      widget.onSelected(DashboardTab.values[next]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = context.shellColors;
    final l10n = context.l10n;

    return SizedBox(
      height: DashboardTabBar.barHeight,
      child: Listener(
        onPointerSignal: _handlePointerSignal,
        child: Container(
          decoration: BoxDecoration(
            color: colors.surfaceContainerHighest,
            borderRadius: theme.borderRadius(ShellShapeScale.full),
          ),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final cellWidth = constraints.maxWidth / _tabCount;
                return Stack(
                  children: [
                    AnimatedBuilder(
                      animation: _pill,
                      builder: (context, child) => Positioned(
                        left: _pill.value * cellWidth,
                        top: 0,
                        bottom: 0,
                        width: cellWidth,
                        child: child!,
                      ),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: theme.accentPalette.container,
                          borderRadius: theme.borderRadius(
                            ShellShapeScale.full,
                          ),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        for (final tab in DashboardTab.values)
                          Expanded(
                            child: _Entry(
                              tab: tab,
                              label: _Entry._label(l10n, tab),
                              selected: tab == widget.selected,
                              onTap: () => widget.onSelected(tab),
                            ),
                          ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) {
      return;
    }
    final delta = event.scrollDelta;
    final direction = delta.dy.abs() >= delta.dx.abs()
        ? delta.dy.sign
        : delta.dx.sign;
    if (direction == 0) {
      return;
    }
    // Wheel down (positive dy) advances forward like scroll content moves up.
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      _selectNearest(direction > 0 ? 1 : -1);
    });
  }
}

class _Entry extends StatelessWidget {
  const _Entry({
    required this.tab,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final DashboardTab tab;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  static String _label(AppLocalizations l10n, DashboardTab tab) {
    return switch (tab) {
      DashboardTab.info => l10n.dashboardTabInfo,
      DashboardTab.system => l10n.dashboardTabSystem,
      DashboardTab.weather => l10n.dashboardTabWeather,
    };
  }

  static IconData _icon(DashboardTab tab) {
    return switch (tab) {
      DashboardTab.info => Icons.info_outline_rounded,
      DashboardTab.system => Icons.show_chart_rounded,
      DashboardTab.weather => Icons.wb_sunny_outlined,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = context.shellColors;
    final icon = _Entry._icon(tab);

    return ShellHoverPill.builder(
      onTap: onTap,
      height: double.infinity,
      childBuilder: (context, hovered, focused) {
        // The selected entry inverts over the accent pill; selection also
        // swaps to the filled glyph where a rounded pair exists.
        final fg = selected
            ? theme.accentPalette.onContainer
            : (hovered ? colors.textPrimary : colors.textSecondary);
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              selected && tab == DashboardTab.info ? Icons.info_rounded : icon,
              size: 18,
              color: fg,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: fg,
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                decoration: TextDecoration.none,
              ),
            ),
          ],
        );
      },
    );
  }
}
