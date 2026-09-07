import 'dart:math' as math;

import 'package:flutter/material.dart' show Colors, Icons;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../localization/denial_localizations.dart';
import '../../../../state/timer_state.dart';
import '../../../../theme/shell_theme.dart';
import '../../../../theme/tokens.dart';
import '../../../../widgets/shell_hover_pill.dart';

/// Timer tools for the dashboard tool drawer: a pomodoro countdown with a
/// draining progress ring and a stopwatch with lap splits. Both share the
/// 1 Hz ticker from [timerToolProvider].
class DrawerTimerWidget extends ConsumerWidget {
  const DrawerTimerWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.shellTheme;
    final colors = context.shellColors;

    final state = ref.watch(timerToolProvider);
    final controller = ref.read(timerToolProvider.notifier);
    final isStopwatch = state.mode == TimerMode.stopwatch;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TimerToolSwitcher(
          stopwatch: isStopwatch,
          onSelected: (stopwatch) => controller.switchMode(
            stopwatch ? TimerMode.stopwatch : TimerMode.pomodoroFocus,
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: isStopwatch
              ? _StopwatchPane(state: state, controller: controller)
              : _PomodoroPane(
                  state: state,
                  controller: controller,
                  trackColor: colors.surfaceContainerHighest,
                  accentColor: theme.accentPalette.primary,
                ),
        ),
      ],
    );
  }
}

class _TimerToolSwitcher extends StatelessWidget {
  const _TimerToolSwitcher({required this.stopwatch, required this.onSelected});

  final bool stopwatch;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = context.shellColors;
    final l10n = context.l10n;
    final radius = theme.borderRadius(ShellShapeScale.full);

    return Container(
      height: 32,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: radius,
      ),
      child: Row(
        children: [
          _TimerToolButton(
            icon: Icons.local_fire_department_rounded,
            label: l10n.timerPomodoro,
            selected: !stopwatch,
            onPressed: () => onSelected(false),
          ),
          const SizedBox(width: 4),
          _TimerToolButton(
            icon: Icons.timer_rounded,
            label: l10n.timerStopwatch,
            selected: stopwatch,
            onPressed: () => onSelected(true),
          ),
        ],
      ),
    );
  }
}

class _TimerToolButton extends StatelessWidget {
  const _TimerToolButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = context.shellColors;

    return Expanded(
      child: ShellHoverPill(
        onTap: onPressed,
        radius: ShellShapeScale.full,
        color: selected ? theme.accentPalette.container : Colors.transparent,
        hoverColor: selected
            ? theme.accentPalette.container
            : colors.panelHighlight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: selected
                  ? theme.accentPalette.onContainer
                  : colors.textSecondary,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: selected
                    ? theme.accentPalette.onContainer
                    : colors.textSecondary,
                fontSize: 11.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PomodoroPane extends StatelessWidget {
  const _PomodoroPane({
    required this.state,
    required this.controller,
    required this.trackColor,
    required this.accentColor,
  });

  final TimerToolState state;
  final TimerToolController controller;
  final Color trackColor;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.shellColors;
    final l10n = context.l10n;
    final remaining = state.target - state.elapsed;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _PomodoroModeChip(
              label: l10n.timerFocus25,
              selected: state.mode == TimerMode.pomodoroFocus,
              onPressed: () => controller.switchMode(TimerMode.pomodoroFocus),
            ),
            const SizedBox(width: 8),
            _PomodoroModeChip(
              label: l10n.timerBreak5,
              selected: state.mode == TimerMode.pomodoroBreak,
              onPressed: () => controller.switchMode(TimerMode.pomodoroBreak),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Center(
          child: SizedBox.square(
            dimension: 150,
            child: CustomPaint(
              painter: _PomodoroRingPainter(
                progress: state.pomodoroProgress,
                trackColor: trackColor,
                progressColor: accentColor,
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _formatDuration(remaining),
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 27,
                        fontWeight: FontWeight.w700,
                        height: 1.1,
                        letterSpacing: 0,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      state.mode == TimerMode.pomodoroBreak
                          ? l10n.timerBreakLabel
                          : l10n.timerFocusLabel,
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _TimerActionButton(
              icon: Icons.restart_alt_rounded,
              onPressed: controller.reset,
            ),
            const SizedBox(width: 16),
            _TimerActionButton(
              icon: state.running
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
              primary: true,
              onPressed: () {
                if (state.running) {
                  controller.pause();
                } else {
                  // Restarting a finished session should begin a fresh one,
                  // otherwise the first tick completes instantly again.
                  if (state.elapsed >= state.target) {
                    controller.reset();
                  }
                  controller.start();
                }
              },
            ),
          ],
        ),
      ],
    );
  }
}

class _PomodoroModeChip extends StatelessWidget {
  const _PomodoroModeChip({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = context.shellColors;

    return ShellHoverPill(
      onTap: onPressed,
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: selected
          ? theme.accentPalette.container
          : colors.surfaceContainerHighest,
      hoverColor: selected
          ? theme.accentPalette.container
          : colors.panelHighlight,
      child: Text(
        label,
        style: TextStyle(
          color: selected
              ? theme.accentPalette.onContainer
              : colors.textSecondary,
          fontSize: 11.5,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
          decoration: TextDecoration.none,
        ),
      ),
    );
  }
}

class _StopwatchPane extends StatelessWidget {
  const _StopwatchPane({required this.state, required this.controller});

  final TimerToolState state;
  final TimerToolController controller;

  @override
  Widget build(BuildContext context) {
    final colors = context.shellColors;
    final laps = state.laps.reversed.toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Text(
            _formatDuration(state.elapsed),
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 30,
              fontWeight: FontWeight.w700,
              height: 1.1,

              decoration: TextDecoration.none,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _TimerActionButton(
              icon: Icons.restart_alt_rounded,
              onPressed: controller.reset,
            ),
            const SizedBox(width: 12),
            _TimerActionButton(
              icon: Icons.flag_rounded,
              enabled: state.running,
              onPressed: controller.lap,
            ),
            const SizedBox(width: 12),
            _TimerActionButton(
              icon: state.running
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
              primary: true,
              onPressed: state.running ? controller.pause : controller.start,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: laps.isEmpty
              ? Center(
                  child: Text(
                    context.l10n.timerNoLaps,
                    style: TextStyle(
                      color: colors.textTertiary,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.none,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  itemCount: laps.length,
                  itemBuilder: (context, index) {
                    final lapNumber = laps.length - index;
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: colors.hairlineSoft),
                        ),
                      ),
                      child: Row(
                        children: [
                          Text(
                            context.l10n.timerLapNumber(lapNumber),
                            style: TextStyle(
                              color: colors.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              decoration: TextDecoration.none,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            _formatDuration(laps[index]),
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _TimerActionButton extends StatelessWidget {
  const _TimerActionButton({
    required this.icon,
    required this.onPressed,
    this.primary = false,
    this.enabled = true,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final bool primary;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = context.shellColors;
    final size = primary ? 52.0 : 44.0;

    // A square pill at full scale renders the same circle the bespoke
    // BoxShape.circle decoration did.
    return ShellHoverPill.builder(
      onTap: onPressed,
      enabled: enabled,
      width: size,
      height: size,
      color: !enabled
          ? colors.tileOff
          : primary
          ? theme.accentPalette.container
          : colors.surfaceContainerHighest,
      hoverColor: primary ? theme.accentPalette.primary : colors.panelHighlight,
      childBuilder: (context, hovered, focused) => Icon(
        icon,
        size: primary ? 26 : 20,
        color: !enabled
            ? colors.glyphInactive
            : primary
            ? (hovered
                  ? theme.accentPalette.onPrimary
                  : theme.accentPalette.onContainer)
            : colors.textPrimary,
      ),
    );
  }
}

/// Draining ring for the pomodoro countdown: the arc spans the remaining
/// fraction of the session and shrinks clockwise from the top.
class _PomodoroRingPainter extends CustomPainter {
  const _PomodoroRingPainter({
    required this.progress,
    required this.trackColor,
    required this.progressColor,
  });

  final double progress;
  final Color trackColor;
  final Color progressColor;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 7.0;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - stroke) / 2;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = trackColor;
    final fill = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = progressColor;
    canvas.drawCircle(center, radius, track);
    final sweep = 2 * math.pi * progress.clamp(0.0, 1.0);
    if (sweep > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        sweep,
        false,
        fill,
      );
    }
  }

  @override
  bool shouldRepaint(_PomodoroRingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.progressColor != progressColor;
}

String _formatDuration(Duration value) {
  final minutes = value.inMinutes.toString().padLeft(2, '0');
  final seconds = (value.inSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
