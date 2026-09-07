import 'package:flutter/material.dart' show Colors, Icons;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../localization/denial_localizations.dart';
import '../../../../state/system_status.dart';
import '../../../../state/todo_list.dart';
import '../../../../theme/motion.dart';
import '../../../../theme/shell_color_scheme.dart';
import '../../../../theme/shell_theme.dart';
import '../../../../theme/tokens.dart';
import 'drawer_calendar_widget.dart';
import 'drawer_timer_widget.dart';
import 'drawer_todo_widget.dart';

enum _InfoDrawerTool { calendar, todo, timer }

/// Collapsible productivity drawer at the bottom of the dashboard Info view:
/// a slim capsule when folded, and a 340 dp tool panel with a vertical
/// navigation rail (calendar / todo / timer) when expanded.
class InfoToolDrawer extends ConsumerStatefulWidget {
  const InfoToolDrawer({super.key});

  @override
  ConsumerState<InfoToolDrawer> createState() => _InfoToolDrawerState();
}

class _InfoToolDrawerState extends ConsumerState<InfoToolDrawer>
    with SingleTickerProviderStateMixin {
  static const double _railWidth = 52;
  static const double _railButtonSize = 44;
  static const double _railStride = _railButtonSize + 8;
  static const double _expandedHeight = 340;

  // Opens expanded so the calendar is immediately visible when the dashboard
  // opens, matching what the old calendar bubble showed on the clock capsule.
  bool _expanded = true;
  _InfoDrawerTool _tool = _InfoDrawerTool.calendar;
  // Initialized eagerly (not late): a drawer that stays collapsed never runs
  // build past the collapsed capsule, and creating the controller lazily in
  // dispose would look up TickerMode on an already-deactivated element.
  late final AnimationController _toolSlider;

  @override
  void initState() {
    super.initState();
    _toolSlider = AnimationController.unbounded(vsync: this);
  }

  @override
  void dispose() {
    _toolSlider.dispose();
    super.dispose();
  }

  void _toggleExpanded() {
    setState(() => _expanded = !_expanded);
  }

  void _selectTool(_InfoDrawerTool tool) {
    if (_tool == tool) {
      return;
    }
    setState(() => _tool = tool);
    springTo(
      _toolSlider,
      tool.index * _railStride,
      spring: Motion.expressiveSpatialFast,
      telemetryLabel: 'info_drawer_tool_slider',
    );
  }

  String _weekdaySymbol(String name, bool isZh) {
    if (isZh) {
      if (name.startsWith('星期') && name.length >= 3) {
        return name.substring(2);
      }
      if (name.startsWith('周') && name.length >= 2) {
        return name.substring(1);
      }
    }
    return name.length >= 2 ? name.substring(0, 2) : name;
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = context.shellColors;
    final l10n = context.l10n;
    final isZh = Localizations.localeOf(context).languageCode == 'zh';

    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final openTodos = ref.watch(
      todoListProvider.select(
        (list) => list.where((item) => !item.done).length,
      ),
    );

    final weekday = _weekdaySymbol(localizedWeekday(l10n, now.weekday), isZh);
    final dateLabel = isZh
        ? '${now.month}月${now.day}日 $weekday · $openTodos 项待办'
        : '${localizedShortDate(context, now)} · $openTodos todos';

    return AnimatedContainer(
      duration: Motion.cardSettle,
      curve: Motion.standard,
      decoration: BoxDecoration(
        color: theme.panelColor(colors.surfaceContainerHigh),
        borderRadius: _expanded
            ? theme.borderRadius(ShellShapeScale.large)
            : theme.borderRadius(ShellShapeScale.full),
        border: Border.all(color: colors.hairlineSoft, width: 1.0),
      ),
      child: AnimatedSize(
        duration: Motion.cardSettle,
        curve: Motion.standard,
        alignment: Alignment.topCenter,
        child: _expanded
            ? SizedBox(
                height: _expandedHeight,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildNavRail(theme, colors),
                      const SizedBox(width: 12),
                      Expanded(
                        child: IndexedStack(
                          index: _tool.index,
                          children: const [
                            Padding(
                              padding: EdgeInsets.symmetric(vertical: 4),
                              child: DrawerCalendarWidget(),
                            ),
                            DrawerTodoWidget(),
                            DrawerTimerWidget(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : _DrawerCollapsedCapsule(
                dateLabel: dateLabel,
                onToggle: _toggleExpanded,
              ),
      ),
    );
  }

  Widget _buildNavRail(ShellThemeData theme, ShellColorScheme colors) {
    final slider = AnimatedBuilder(
      animation: _toolSlider,
      builder: (context, child) => Positioned(
        left: (_railWidth - _railButtonSize) / 2,
        top: _toolSlider.value,
        child: child!,
      ),
      child: Container(
        width: _railButtonSize,
        height: _railButtonSize,
        decoration: BoxDecoration(
          color: theme.accentPalette.container,
          borderRadius: theme.borderRadius(ShellShapeScale.full),
        ),
      ),
    );

    return SizedBox(
      width: _railWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              slider,
              Column(
                children: [
                  _RailToolButton(
                    icon: Icons.calendar_month_rounded,
                    selected: _tool == _InfoDrawerTool.calendar,
                    onPressed: () => _selectTool(_InfoDrawerTool.calendar),
                  ),
                  const SizedBox(height: 8),
                  _RailToolButton(
                    icon: Icons.checklist_rounded,
                    selected: _tool == _InfoDrawerTool.todo,
                    onPressed: () => _selectTool(_InfoDrawerTool.todo),
                  ),
                  const SizedBox(height: 8),
                  _RailToolButton(
                    icon: Icons.timer_rounded,
                    selected: _tool == _InfoDrawerTool.timer,
                    onPressed: () => _selectTool(_InfoDrawerTool.timer),
                  ),
                ],
              ),
            ],
          ),
          const Spacer(),
          _RailToolButton(
            icon: Icons.keyboard_arrow_down_rounded,
            onPressed: _toggleExpanded,
          ),
        ],
      ),
    );
  }
}

class _DrawerCollapsedCapsule extends StatelessWidget {
  const _DrawerCollapsedCapsule({
    required this.dateLabel,
    required this.onToggle,
  });

  final String dateLabel;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = context.shellColors;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onToggle,
      child: SizedBox(
        height: 44,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Icon(
                Icons.expand_less_rounded,
                size: 20,
                color: theme.accentPalette.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  dateLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.keyboard_arrow_up_rounded,
                size: 20,
                color: colors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RailToolButton extends StatefulWidget {
  const _RailToolButton({
    required this.icon,
    required this.onPressed,
    this.selected = false,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final bool selected;

  @override
  State<_RailToolButton> createState() => _RailToolButtonState();
}

class _RailToolButtonState extends State<_RailToolButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = context.shellColors;

    final showHoverBubble = !widget.selected && _hovered;
    final fg = widget.selected
        ? theme.accentPalette.onContainer
        : (_hovered ? colors.textPrimary : colors.textSecondary);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: Motion.pill,
          curve: Curves.easeOut,
          height: 44,
          decoration: BoxDecoration(
            color: showHoverBubble ? colors.panelHighlight : Colors.transparent,
            borderRadius: theme.borderRadius(ShellShapeScale.full),
          ),
          child: Center(child: Icon(widget.icon, size: 22, color: fg)),
        ),
      ),
    );
  }
}
