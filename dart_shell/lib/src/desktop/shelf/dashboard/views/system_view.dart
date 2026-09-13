import 'dart:io';

import 'package:flutter/material.dart' show Icons, Scrollbar;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../settings/settings_controller.dart';
import '../../../../state/system_extended_status.dart';
import '../../../../localization/denial_localizations.dart';
import '../../../../state/system_status.dart';
import '../../../../theme/shell_color_scheme.dart';
import '../../../../theme/shell_theme.dart';
import '../../../../theme/tokens.dart';
import '../system/card_catalog.dart';
import '../system/liquid_metric_card.dart';
import '../system/metric_sparkline_card.dart';
import '../system/network_metric_card.dart';
import '../system/storage_battery_cards.dart';
import '../system/system_card_grid_view.dart';

/// System monitoring dashboard: cpu/gpu sparklines plus memory, network,
/// storage, and battery on a draggable clavis-style bento grid.
///
/// The page shell owns only scrolling, the gpu id list, and the animation
/// scale, while every card watches its own provider slice — the shared 2 s
/// telemetry tick rebuilds exactly the cards whose values moved instead of
/// the whole page.
class SystemView extends StatelessWidget {
  const SystemView({super.key});

  @override
  Widget build(BuildContext context) {
    return const _SystemPageShell();
  }
}

class _SystemPageShell extends ConsumerStatefulWidget {
  const _SystemPageShell();

  @override
  ConsumerState<_SystemPageShell> createState() => _SystemPageShellState();
}

class _SystemPageShellState extends ConsumerState<_SystemPageShell> {
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
    // Only the gpu id list may rebuild the grid: joining to a string gives
    // the selector value equality that the unmodifiable list identity lacks,
    // so the 2 s telemetry tick never re-lays out the canvas.
    final gpuKey = ref.watch(
      gpuUsageProvider.select((gpus) => gpus.map((gpu) => gpu.id).join(' ')),
    );
    final motionScale = ref.watch(
      shellSettingsProvider.select(
        (settings) => settings.animations.durationScale,
      ),
    );
    final gpuIds = gpuKey.isEmpty ? const <String>[] : gpuKey.split(' ');
    final items = <SystemCardGridItem>[
      const SystemCardGridItem(id: 'cpu', child: _CpuUsageCard()),
      for (final gpuId in gpuIds)
        SystemCardGridItem(
          id: SystemCardCatalog.gpuTileId(gpuId),
          child: _GpuUsageCard(gpuId: gpuId),
        ),
      const SystemCardGridItem(id: 'memory', child: _MemoryUsageCard()),
      const SystemCardGridItem(id: 'network', child: _NetworkUsageCard()),
      const SystemCardGridItem(id: 'storage', child: _StorageUsageCard()),
      const SystemCardGridItem(id: 'battery', child: _BatteryStatusCard()),
    ];
    // The scrollbar shares an explicit controller with the scroll view
    // because the shell provides no PrimaryScrollController to adopt.
    return Scrollbar(
      controller: _scrollController,
      child: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: SystemCardGridView(items: items, motionScale: motionScale),
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
      // A 2x1 tile leaves ~84 px next to the sparkline, so the chips wrap
      // to a second line instead of overflowing the row (was a plain Row
      // when this card always rendered at full panel width).
      detail: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          _MetricChip(
            icon: Icons.developer_board_rounded,
            label: l10n.systemCoresLabel(Platform.numberOfProcessors),
            colors: colors,
          ),
          if (cpu.temperatureC != null)
            _MetricChip(
              icon: Icons.device_thermostat_rounded,
              label: '${cpu.temperatureC!.round()}°C',
              colors: colors,
            ),
        ],
      ),
    );
  }
}

/// One grid tile per detected GPU; [gpuId] is [GpuLoad.id] (`card2`,
/// `nvml0`…), stable across polls so the saved layout survives reboots.
class _GpuUsageCard extends ConsumerWidget {
  const _GpuUsageCard({required this.gpuId});

  final String gpuId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gpu = ref.watch(
      gpuUsageProvider.select((gpus) {
        for (final gpu in gpus) {
          if (gpu.id == gpuId) {
            return gpu;
          }
        }
        return null;
      }),
    );
    if (gpu == null) {
      // The gpu vanished between the shell's id snapshot and this build;
      // the next tick removes the tile entirely.
      return const SizedBox.shrink();
    }
    final colors = context.shellColors;

    return MetricSparklineCard(
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
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: theme.borderRadius(ShellShapeScale.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: colors.textSecondary),
          const SizedBox(width: 4),
          // A 2x1 tile leaves ~68 px inside the chip once the sparkline takes
          // its share, so the label must flex and ellipsize instead of
          // pushing the Row past its constraint.
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
