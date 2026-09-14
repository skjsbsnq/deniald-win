import 'dart:math' as math;

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

import '../../../../state/system_extended_status.dart' show NetworkRateSeries;
import '../../../../theme/shell_theme.dart';
import '../../../../theme/tokens.dart';

/// clavis `SystemNetworkCard`: a full-width split hero — the primary-colored
/// left ~53% carries the title plus a live dual-rate sparkline, the
/// primaryContainer right panel lists download/upload rates.
///
/// The widget accumulates observed rate samples into a rolling
/// [NetworkRateSeries] (capacity 45, matching the provider model); only
/// values the telemetry tick actually reported enter the buffer, nothing is
/// synthesized.
class NetworkMetricCard extends StatefulWidget {
  const NetworkMetricCard({
    super.key,
    required this.label,
    required this.downloadBytesPerSecond,
    required this.uploadBytesPerSecond,
    this.surfaceColor,
    this.contentColor,
    this.panelColor,
    this.panelContentColor,
    this.downloadAccentColor,
    this.uploadAccentColor,
  });

  final String label;

  /// Bytes per second across all interfaces, or null before two counter
  /// samples exist.
  final double? downloadBytesPerSecond;
  final double? uploadBytesPerSecond;

  /// Left panel surface; clavis `surfaceColor` (primary).
  final Color? surfaceColor;

  /// Title and rate text on the left panel (clavis `leftForeground`).
  final Color? contentColor;

  /// Right rate-panel surface; clavis `panelColor` (primaryContainer).
  final Color? panelColor;

  /// Rate text on the right panel (clavis `rightForeground`).
  final Color? panelContentColor;

  /// Download icon + sparkline accent (clavis `colTertiary`).
  final Color? downloadAccentColor;

  /// Upload icon + sparkline accent (clavis mixes primary into onPrimary).
  final Color? uploadAccentColor;

  @override
  State<NetworkMetricCard> createState() => _NetworkMetricCardState();
}

class _NetworkMetricCardState extends State<NetworkMetricCard> {
  NetworkRateSeries _series = const NetworkRateSeries();

  @override
  void initState() {
    super.initState();
    _append(widget.downloadBytesPerSecond, widget.uploadBytesPerSecond);
  }

  @override
  void didUpdateWidget(NetworkMetricCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.downloadBytesPerSecond != widget.downloadBytesPerSecond ||
        oldWidget.uploadBytesPerSecond != widget.uploadBytesPerSecond) {
      _append(widget.downloadBytesPerSecond, widget.uploadBytesPerSecond);
    }
  }

  void _append(double? download, double? upload) {
    if (download == null || upload == null) {
      // Before the first pair of counter samples there is no rate at all;
      // the chart waits for real data rather than seeding zeros.
      return;
    }
    _series = _series.append(download, upload);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = context.shellColors;
    final leftColor =
        widget.surfaceColor ?? theme.panelColor(colors.surfaceContainer);
    final leftForeground = widget.contentColor ?? colors.textPrimary;
    final rightColor =
        widget.panelColor ?? theme.panelColor(colors.surfaceContainer);
    final rightForeground = widget.panelContentColor ?? leftForeground;
    final downAccent =
        widget.downloadAccentColor ?? theme.accentPalette.tertiary;
    final upAccent = widget.uploadAccentColor ?? theme.accentPalette.primary;
    // clavis chart colors: accent hues lifted toward the left foreground so
    // the lines read on the saturated primary surface.
    final downLine = Color.lerp(downAccent, leftForeground, 0.64) ?? downAccent;
    final upLine = Color.lerp(upAccent, leftForeground, 0.58) ?? upAccent;
    final radius = theme.borderRadius(ShellShapeScale.extraLarge);

    return LayoutBuilder(
      builder: (context, constraints) {
        // clavis: rightPanelX = round(width * 0.53).
        final rightWidth =
            constraints.maxWidth -
            (constraints.maxWidth * 0.53).roundToDouble();
        final leftWidth = constraints.maxWidth - rightWidth;
        return Container(
          decoration: BoxDecoration(
            color: leftColor,
            borderRadius: radius,
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: colors.shadow.withValues(alpha: 0.4),
                offset: const Offset(0, 4),
                blurRadius: 18,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: Stack(
              children: [
                Positioned(
                  left: 16,
                  top: 14,
                  width: leftWidth - 16,
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: leftForeground,
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
                // Sparkline zone: full left width, below the title.
                Positioned(
                  left: 0,
                  top: 46,
                  bottom: 8,
                  width: leftWidth,
                  child: CustomPaint(
                    painter: _DualRateSparklinePainter(
                      download: _series.down,
                      upload: _series.up,
                      lineColor: downLine,
                      secondaryLineColor: upLine,
                    ),
                  ),
                ),
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: rightWidth,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: rightColor,
                      borderRadius: radius,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      child: Column(
                        children: [
                          Expanded(
                            child: _RateRow(
                              icon: Icons.arrow_downward_rounded,
                              value: widget.downloadBytesPerSecond,
                              iconColor: downAccent,
                              textColor: rightForeground,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Expanded(
                            child: _RateRow(
                              icon: Icons.arrow_upward_rounded,
                              value: widget.uploadBytesPerSecond,
                              iconColor: upAccent,
                              textColor: rightForeground,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// clavis `NetworkRate`: a 27-ish px symbol plus a heavy rate value.
class _RateRow extends StatelessWidget {
  const _RateRow({
    required this.icon,
    required this.value,
    required this.iconColor,
    required this.textColor,
  });

  final IconData icon;
  final double? value;
  final Color iconColor;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 24, color: iconColor),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            formatDataRate(value),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: textColor,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ],
    );
  }
}

/// Two sparklines on a shared auto-scaled axis (clavis draws the upload
/// series twice — once as a flat filled shape behind, once as the secondary
/// line inside the download chart). Here the download line is stroked over
/// a soft fill, the upload line is a thinner stroke with its own flat fill.
class _DualRateSparklinePainter extends CustomPainter {
  const _DualRateSparklinePainter({
    required this.download,
    required this.upload,
    required this.lineColor,
    required this.secondaryLineColor,
  });

  final List<double> download;
  final List<double> upload;
  final Color lineColor;
  final Color secondaryLineColor;

  static const int _visible = 18;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) {
      return;
    }
    final down = _tail(download);
    final up = _tail(upload);
    if (down.length < 2 && up.length < 2) {
      return;
    }
    // clavis chartMaximum: 1.2x the largest visible sample, floor 1 so a
    // quiet link still scales.
    var maximum = 0.0;
    for (final value in down) {
      maximum = math.max(maximum, value);
    }
    for (final value in up) {
      maximum = math.max(maximum, value);
    }
    maximum = math.max(1, maximum * 1.2);

    Path lineFor(List<double> values) {
      final points = <Offset>[
        for (var i = 0; i < values.length; i++)
          Offset(
            i * size.width / (values.length - 1),
            size.height - size.height * (values[i] / maximum).clamp(0.0, 1.0),
          ),
      ];
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (var i = 1; i < points.length; i++) {
        final previous = points[i - 1];
        final current = points[i];
        final mid = Offset(
          (previous.dx + current.dx) / 2,
          (previous.dy + current.dy) / 2,
        );
        path.quadraticBezierTo(previous.dx, previous.dy, mid.dx, mid.dy);
      }
      path.lineTo(points.last.dx, points.last.dy);
      return path;
    }

    Path fillFor(Path line, List<double> values) => Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    // Upload first — the flat filled shape behind everything (fillOpacity
    // 0.3, no stroke) — then the download fill + line on top.
    if (up.length >= 2) {
      final upPath = lineFor(up);
      canvas.drawPath(
        fillFor(upPath, up),
        Paint()..color = secondaryLineColor.withValues(alpha: 0.3),
      );
      canvas.drawPath(
        upPath,
        Paint()
          ..color = secondaryLineColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
    if (down.length >= 2) {
      final downPath = lineFor(down);
      canvas.drawPath(
        fillFor(downPath, down),
        Paint()..color = lineColor.withValues(alpha: 0.26),
      );
      canvas.drawPath(
        downPath,
        Paint()
          ..color = lineColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  List<double> _tail(List<double> values) => values.length <= _visible
      ? values
      : values.sublist(values.length - _visible);

  @override
  bool shouldRepaint(_DualRateSparklinePainter oldDelegate) =>
      !identical(oldDelegate.download, download) ||
      !identical(oldDelegate.upload, upload) ||
      oldDelegate.lineColor != lineColor ||
      oldDelegate.secondaryLineColor != secondaryLineColor;
}

/// Human-readable byte rate; null renders as `--` before samples exist.
String formatDataRate(double? bytesPerSecond) {
  if (bytesPerSecond == null || !bytesPerSecond.isFinite) {
    return '--';
  }
  if (bytesPerSecond < 1024) {
    return '${bytesPerSecond.round()} B/s';
  }
  final kibibytes = bytesPerSecond / 1024;
  if (kibibytes < 1024) {
    return '${kibibytes.toStringAsFixed(1)} KB/s';
  }
  return '${(kibibytes / 1024).toStringAsFixed(1)} MB/s';
}
