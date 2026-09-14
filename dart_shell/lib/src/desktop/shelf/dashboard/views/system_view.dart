import 'dart:io';

import 'package:androidx_graphics_shapes/material_shapes.dart';
import 'package:flutter/material.dart' show Icons, Scrollbar;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../settings/settings_controller.dart';
import '../../../../state/system_extended_status.dart';
import '../../../../localization/denial_localizations.dart';
import '../../../../state/system_status.dart';
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
    final l10n = context.l10n;
    final palette = context.shellTheme.accentPalette;
    final cpu = ref.watch(
      cpuUsageProvider.select(
        (series) => (
          current: series.current,
          history: series.history,
          temperatureC: series.temperatureC,
        ),
      ),
    );
    // clavis SystemCardContent: the cpu card sits on the primaryContainer
    // surface with onContainer content and the primary accent line.
    final chipBackground = palette.primary.withValues(alpha: 0.12);

    return MetricSparklineCard(
      label: l10n.metricCpu,
      usage: cpu.current,
      history: cpu.history,
      showExpressivePolygon: true,
      decorationIcon: Icons.memory_rounded,
      decorationForeground: palette.onPrimary,
      surfaceColor: palette.container,
      contentColor: palette.onContainer,
      mutedContentColor: palette.onContainerSecondary,
      accentColor: palette.primary,
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
            background: chipBackground,
            foreground: palette.onContainer,
          ),
          if (cpu.temperatureC != null)
            _MetricChip(
              icon: Icons.device_thermostat_rounded,
              label: '${cpu.temperatureC!.round()}°C',
              background: chipBackground,
              foreground: palette.onContainer,
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
    // clavis: the gpu card sits on the secondaryContainer surface with the
    // secondary accent line (and a Gem shape decoration upstream).
    final palette = context.shellTheme.accentPalette;

    return MetricSparklineCard(
      label: gpu.label,
      usage: gpu.series.current,
      history: gpu.series.history,
      showExpressivePolygon: true,
      decorationShape: MaterialShapes.gem,
      decorationIcon: Icons.developer_board_rounded,
      decorationForeground: palette.onSecondary,
      surfaceColor: palette.secondaryContainer,
      contentColor: palette.onSecondaryContainer,
      mutedContentColor: palette.onSecondaryContainer.withValues(alpha: 0.75),
      accentColor: palette.secondary,
      detail: gpu.series.temperatureC == null
          ? null
          : _MetricChip(
              icon: Icons.device_thermostat_rounded,
              label: '${gpu.series.temperatureC!.round()}°C',
              background: palette.secondary.withValues(alpha: 0.12),
              foreground: palette.onSecondaryContainer,
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
    // clavis memoryUsed: a `MaterialShape.Slanted` surface on
    // primaryContainer with the tertiary liquid fill.
    final palette = context.shellTheme.accentPalette;

    return LiquidMetricCard(
      label: context.l10n.systemMemory,
      fraction: memory?.fraction ?? 0,
      valueLabel: memory == null
          ? null
          : '${formatGigabytes(memory.used)} / '
                '${formatGigabytes(memory.total)} GB',
      icon: Icons.sd_card_rounded,
      surfaceColor: palette.container,
      contentColor: palette.onContainer,
      fillColor: palette.tertiary.withValues(alpha: 0.66),
      shape: MaterialShapes.slanted,
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
    // clavis network: solid-primary left panel carrying the sparkline,
    // primaryContainer right rate panel.
    final palette = context.shellTheme.accentPalette;

    return NetworkMetricCard(
      label: context.l10n.systemNetwork,
      downloadBytesPerSecond: rates.download,
      uploadBytesPerSecond: rates.upload,
      surfaceColor: palette.primary,
      contentColor: palette.onPrimary,
      panelColor: palette.container,
      panelContentColor: palette.onContainer,
      downloadAccentColor: palette.tertiary,
      uploadAccentColor: palette.primary,
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
    // clavis storage: solid-tertiary left panel, tertiaryContainer right
    // rate panel.
    final palette = context.shellTheme.accentPalette;

    return StorageCard(
      storage: storage,
      surfaceColor: palette.tertiary,
      contentColor: palette.onTertiary,
      mutedContentColor: palette.onTertiary.withValues(alpha: 0.72),
      panelColor: palette.tertiaryContainer,
      panelContentColor: palette.onTertiaryContainer,
      accentColor: palette.onTertiary,
    );
  }
}

class _BatteryStatusCard extends ConsumerWidget {
  const _BatteryStatusCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // clavis battery: secondaryContainer tank, secondary fill, contents
    // repaint in onSecondary once the fill covers them.
    final palette = context.shellTheme.accentPalette;
    return BatteryTankCard(
      battery: ref.watch(batteryProvider),
      surfaceColor: palette.secondaryContainer,
      contentColor: palette.onSecondaryContainer,
      mutedContentColor: palette.onSecondaryContainer.withValues(alpha: 0.75),
      fillColor: palette.secondary,
      onFillColor: palette.onSecondary,
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
  });

  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(
        color: background,
        borderRadius: theme.borderRadius(ShellShapeScale.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: foreground),
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
                color: foreground,
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
