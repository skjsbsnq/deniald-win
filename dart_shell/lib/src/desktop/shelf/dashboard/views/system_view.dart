import 'dart:io';

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../state/system_extended_status.dart';
import '../../../../state/system_status.dart';
import '../../../../theme/shell_color_scheme.dart';
import '../../../../theme/shell_theme.dart';
import '../../../../theme/tokens.dart';
import '../system/liquid_metric_card.dart';
import '../system/metric_sparkline_card.dart';
import '../system/network_metric_card.dart';
import '../system/storage_battery_cards.dart';

/// System monitoring dashboard: CPU and GPU load sparklines spanning the
/// full width, then memory, network rates, storage, and battery in a
/// two-column grid.
class SystemView extends ConsumerWidget {
  const SystemView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.shellColors;
    final isZh = Localizations.localeOf(context).languageCode == 'zh';

    final cpu = ref.watch(cpuUsageProvider);
    final gpus = ref.watch(gpuUsageProvider);
    final extended = ref.watch(systemExtendedStatusProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          MetricSparklineCard(
            label: 'CPU',
            usage: cpu.current,
            history: cpu.history,
            showExpressivePolygon: true,
            detail: Row(
              children: [
                _MetricChip(
                  icon: Icons.developer_board_rounded,
                  label:
                      '${Platform.numberOfProcessors} '
                      '${isZh ? '核' : 'cores'}',
                  colors: colors,
                ),
                if (cpu.temperatureC != null) ...[
                  const SizedBox(width: 6),
                  _MetricChip(
                    icon: Icons.device_thermostat_rounded,
                    label: '${cpu.temperatureC!.round()}°C',
                    colors: colors,
                  ),
                ],
              ],
            ),
          ),
          for (final gpu in gpus) ...[
            const SizedBox(height: 8),
            MetricSparklineCard(
              label: gpu.label,
              usage: gpu.series.current,
              history: gpu.series.history,
              detail: gpu.series.temperatureC == null
                  ? null
                  : _MetricChip(
                      icon: Icons.device_thermostat_rounded,
                      label: '${gpu.series.temperatureC!.round()}°C',
                      colors: colors,
                    ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: LiquidMetricCard(
                  label: isZh ? '内存' : 'Memory',
                  fraction: extended.memory?.fraction ?? 0,
                  valueLabel: extended.memory == null
                      ? null
                      : '${formatGigabytes(extended.memory!.used)} / '
                            '${formatGigabytes(extended.memory!.total)} GB',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: NetworkMetricCard(
                  label: isZh ? '网络' : 'Network',
                  downloadBytesPerSecond: extended.downloadBytesPerSecond,
                  uploadBytesPerSecond: extended.uploadBytesPerSecond,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: StorageCard(storage: extended.storage)),
              const SizedBox(width: 8),
              Expanded(
                child: BatteryTankCard(battery: ref.watch(batteryProvider)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.icon,
    required this.label,
    required this.colors,
  });

  final IconData icon;
  final String label;
  final ShellColorScheme colors;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: theme.borderRadius(ShellShapeScale.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: colors.textSecondary),
          const SizedBox(width: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }
}
