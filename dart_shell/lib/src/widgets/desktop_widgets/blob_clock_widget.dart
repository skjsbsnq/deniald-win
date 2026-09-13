part of 'desktop_widgets.dart';

/// Analog clock inside a clover blob (02-VISUAL-SPEC.md §6, 参考图 2/3).
///
/// The dial is a [CustomPaint] redrawn only when [clock] changes — the
/// parent's `clockProvider` ticks once per minute, so no idle ticker runs.
/// Day and month ride as small tonal badges pinned to the blob's edge.
class BlobClockWidget extends StatelessWidget {
  const BlobClockWidget({
    super.key,
    required this.clock,
    this.showStatus = true,
  });

  final HomeClockInfo clock;
  final bool showStatus;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final palette = theme.accentPalette;
    final now = clock.now;

    return Semantics(
      label:
          '${localizedTime(context, now)}, '
          '${localizedLongDate(context, now)}',
      child: DesktopWidgetEntrance(
        child: DesktopBlobContainer(
          shape: DesktopBlobShape.clover,
          color: palette.secondaryContainer,
          padding: const EdgeInsets.all(ShellSpacing.lg),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final side = math.min(
                constraints.maxWidth,
                constraints.maxHeight,
              );
              final dialSide = side * 0.62;
              final status = showStatus
                  ? _BlobClockStatus(clock: clock, dialSide: dialSide)
                  : null;
              return Stack(
                fit: StackFit.expand,
                children: [
                  Center(
                    child: SizedBox.square(
                      dimension: dialSide,
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: _BlobClockDialPainter(
                            now: now,
                            tickColor: palette.onSecondaryContainer,
                            hourHandColor: palette.onSecondaryContainer,
                            minuteHandColor: palette.primary,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: side * 0.10,
                    right: side * 0.14,
                    child: _BlobDateBadge(label: '${now.day}'),
                  ),
                  Positioned(
                    bottom: side * 0.10,
                    left: side * 0.14,
                    child: _BlobDateBadge(
                      label: now.month.toString().padLeft(2, '0'),
                    ),
                  ),
                  if (status != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: side * 0.06,
                      child: Center(child: status),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Small rounded badge pinned to the blob edge carrying the day or month
/// number; `tertiaryContainer`/`onTertiaryContainer` is the spec's accent
/// pair for emphasized info (02-VISUAL-SPEC.md §1.2).
class _BlobDateBadge extends StatelessWidget {
  const _BlobDateBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final palette = theme.accentPalette;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.tertiaryContainer,
        borderRadius: theme.borderRadius(ShellShapeScale.small),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: ShellSpacing.sm,
          vertical: ShellSpacing.xs,
        ),
        child: Text(
          label,
          maxLines: 1,
          softWrap: false,
          style: theme.text.labelLarge.copyWith(
            color: palette.onTertiaryContainer,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// Compact battery/thermal strip kept from the previous clock tile so no
/// status information is lost in the blob form (§C2).
class _BlobClockStatus extends StatelessWidget {
  const _BlobClockStatus({required this.clock, required this.dialSide});

  final HomeClockInfo clock;
  final double dialSide;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final power = clock.power;
    final batteryLine = localizedBatteryLine(l10n, power.state, power.capacity);
    final readings = clock.thermalReadings;
    if (batteryLine.isEmpty && readings.isEmpty) {
      return const SizedBox.shrink();
    }
    final theme = context.shellTheme;
    final palette = theme.accentPalette;
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (batteryLine.isNotEmpty) ...[
            Icon(
              power.chargeProtocol != null || power.state == 'charging'
                  ? Icons.bolt_rounded
                  : Icons.battery_std_rounded,
              size: 14,
              color: _blobBatteryAccent(power, palette),
            ),
            const SizedBox(width: ShellSpacing.xs),
            Text(
              batteryLine,
              maxLines: 1,
              softWrap: false,
              style: theme.text.labelMedium.copyWith(
                color: _blobBatteryAccent(power, palette),
              ),
            ),
          ],
          for (final reading in readings) ...[
            const SizedBox(width: ShellSpacing.sm),
            Text(
              '${localizedThermalSensor(l10n, reading.sensor)} '
              '${l10n.temperatureCelsius((reading.deciC / 10).round())}',
              maxLines: 1,
              softWrap: false,
              style: theme.text.labelMedium.copyWith(
                color: _blobThermalColor(reading.deciC),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Battery accent mirroring the launcher's charge-protocol palette; kept
/// local because the launcher helper is library-private.
Color _blobBatteryAccent(HomePowerStatus power, ShellAccentPalette palette) {
  if (power.voocCharging) {
    return ShellTelemetryColors.chargingVooc;
  }
  if (power.ppsCharging) {
    return ShellTelemetryColors.chargingPps;
  }
  if (power.pdCharging) {
    return ShellTelemetryColors.chargingPd;
  }
  if (power.fastCharge || power.state == 'charging') {
    return ShellTelemetryColors.charging;
  }
  if (power.state == 'discharging') {
    final capacity = power.capacity;
    if (capacity == null || capacity >= 20) {
      return palette.onSecondaryContainer;
    }
    if (capacity >= 15) {
      return ShellTelemetryColors.warning;
    }
    return ShellTelemetryColors.danger;
  }
  return palette.onSecondaryContainer;
}

/// Thermal tint thresholds shared with the launcher clock tile.
Color _blobThermalColor(int deciC) {
  if (deciC >= 800) {
    return ShellTelemetryColors.danger;
  }
  if (deciC >= 700) {
    return ShellTelemetryColors.warm;
  }
  if (deciC >= 550) {
    return ShellTelemetryColors.warning;
  }
  return ShellTelemetryColors.nominal;
}

/// Analog dial: twelve hour ticks plus hour/minute hands. Drawn once per
/// minute tick; [shouldRepaint] keys on the displayed instant so theme
/// changes still land.
class _BlobClockDialPainter extends CustomPainter {
  const _BlobClockDialPainter({
    required this.now,
    required this.tickColor,
    required this.hourHandColor,
    required this.minuteHandColor,
  });

  final DateTime now;
  final Color tickColor;
  final Color hourHandColor;
  final Color minuteHandColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;

    final tickPaint = Paint()
      ..color = tickColor.withValues(alpha: 0.38)
      ..strokeWidth = radius * 0.022
      ..strokeCap = StrokeCap.round;
    final hourTickPaint = Paint()
      ..color = tickColor.withValues(alpha: 0.85)
      ..strokeWidth = radius * 0.04
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 12; i += 1) {
      final angle = i * math.pi / 6;
      final direction = Offset(math.cos(angle), math.sin(angle));
      final hour = i % 3 == 0;
      final paint = hour ? hourTickPaint : tickPaint;
      final inner = radius * (hour ? 0.78 : 0.86);
      canvas.drawLine(
        center + direction * inner,
        center + direction * radius * 0.96,
        paint,
      );
    }

    final minuteAngle = (now.minute / 60) * 2 * math.pi - math.pi / 2;
    final hourAngle =
        (((now.hour % 12) + now.minute / 60) / 12) * 2 * math.pi -
        math.pi / 2;

    final hourPaint = Paint()
      ..color = hourHandColor
      ..strokeWidth = radius * 0.085
      ..strokeCap = StrokeCap.round;
    final minutePaint = Paint()
      ..color = minuteHandColor
      ..strokeWidth = radius * 0.05
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      center,
      center +
          Offset(math.cos(hourAngle), math.sin(hourAngle)) * radius * 0.52,
      hourPaint,
    );
    canvas.drawLine(
      center,
      center +
          Offset(math.cos(minuteAngle), math.sin(minuteAngle)) *
              radius *
              0.78,
      minutePaint,
    );
    canvas.drawCircle(
      center,
      radius * 0.07,
      Paint()..color = minuteHandColor,
    );
  }

  @override
  bool shouldRepaint(covariant _BlobClockDialPainter oldDelegate) {
    return oldDelegate.now != now ||
        oldDelegate.tickColor != tickColor ||
        oldDelegate.hourHandColor != hourHandColor ||
        oldDelegate.minuteHandColor != minuteHandColor;
  }
}
