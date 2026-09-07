import 'dart:io';

import 'package:flutter/material.dart' show Icons, Scrollbar;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../state/system_extended_status.dart';
import '../../../../localization/denial_localizations.dart';
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
///
/// The page shell owns only layout and scrolling while every card watches
/// its own provider slice, so the shared 2 s telemetry tick rebuilds exactly
/// the cards whose values moved instead of the whole page.
class SystemView extends StatelessWidget {
  const SystemView({super.key});

  @override
  Widget build(BuildContext context) {
    return const _SystemPageShell();
  }
}

class _SystemPageShell extends StatefulWidget {
  const _SystemPageShell();

  @override
  State<_SystemPageShell> createState() => _SystemPageShellState();
}

class _SystemPageShellState extends State<_SystemPageShell> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The scrollbar shares an explicit controller with the scroll view
    // because the shell provides no PrimaryScrollController to adopt.
    return Scrollbar(
      controller: _scrollController,
      child: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const _CpuUsageCard(),
            const _GpuUsageCards(),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Expanded(child: _MemoryUsageCard()),
                const SizedBox(width: 8),
                const Expanded(child: _NetworkUsageCard()),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Expanded(child: _StorageUsageCard()),
                const SizedBox(width: 8),
                const Expanded(child: _BatteryStatusCard()),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CpuUsageCard extends ConsumerWidget {
  const _CpuUsageCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.shellColors;
    final l10n = context.l10n;
    final cpu = ref.watch(
      cpuUsageProvider.select(
        (series) => (
          current: series.current,
          history: series.history,
          temperatureC: series.temperatureC,
        ),
      ),
    );

    return MetricSparklineCard(
      label: l10n.metricCpu,
      usage: cpu.current,
      history: cpu.history,
      showExpressivePolygon: true,
      detail: Row(
        children: [
          _MetricChip(
            icon: Icons.developer_board_rounded,
            label: l10n.systemCoresLabel(Platform.numberOfProcessors),
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
    );
  }
}

class _GpuUsageCards extends ConsumerWidget {
  const _GpuUsageCards();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gpus = ref.watch(gpuUsageProvider);
    final colors = context.shellColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
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
      ],
    );
  }
}

class _MemoryUsageCard extends ConsumerWidget {
  const _MemoryUsageCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memory = ref.watch(
      systemExtendedStatusProvider.select((status) => status.memory),
    );

    return LiquidMetricCard(
      label: context.l10n.systemMemory,
      fraction: memory?.fraction ?? 0,
      valueLabel: memory == null
          ? null
          : '${formatGigabytes(memory.used)} / '
                '${formatGigabytes(memory.total)} GB',
    );
  }
}

class _NetworkUsageCard extends ConsumerWidget {
  const _NetworkUsageCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rates = ref.watch(
      systemExtendedStatusProvider.select(
        (status) => (
          download: status.downloadBytesPerSecond,
          upload: status.uploadBytesPerSecond,
        ),
      ),
    );

    return NetworkMetricCard(
      label: context.l10n.systemNetwork,
      downloadBytesPerSecond: rates.download,
      uploadBytesPerSecond: rates.upload,
    );
  }
}

class _StorageUsageCard extends ConsumerWidget {
  const _StorageUsageCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storage = ref.watch(
      systemExtendedStatusProvider.select((status) => status.storage),
    );

    return StorageCard(storage: storage);
  }
}

class _BatteryStatusCard extends ConsumerWidget {
  const _BatteryStatusCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return BatteryTankCard(battery: ref.watch(batteryProvider));
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
