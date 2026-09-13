part of 'desktop_widgets.dart';

/// Battery blob: large percent figure plus a charging-state glyph
/// (02-VISUAL-SPEC.md §6). Reads the shared `batteryProvider` snapshot — the
/// controller's own 15 s poll is already kept alive by the system bars, and
/// this widget adds no timer.
class BlobBatteryWidget extends ConsumerWidget {
  const BlobBatteryWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final battery = ref.watch(batteryProvider);
    final theme = context.shellTheme;
    final palette = theme.accentPalette;
    final l10n = context.l10n;

    final capacity = battery.capacity;
    final percent = capacity == null
        ? l10n.batteryCapacityUnavailable
        : l10n.percentCompact(capacity);
    final stateKey = battery.charging
        ? 'charging'
        : battery.full
        ? 'full'
        : battery.acOnline
        ? 'idle'
        : 'discharging';
    final stateLabel = localizedBatteryState(l10n, stateKey);
    final charging = battery.charging || battery.full;

    return Semantics(
      label: capacity == null
          ? l10n.batteryTitle
          : l10n.batteryStateAndPercent(
              stateLabel.isEmpty ? l10n.batteryTitle : stateLabel,
              capacity,
            ),
      child: DesktopWidgetEntrance(
        child: DesktopBlobContainer(
          shape: DesktopBlobShape.puffy,
          color: palette.secondaryContainer,
          padding: const EdgeInsets.all(ShellSpacing.lg),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxHeight < 88;
              final percentStyle = compact
                  ? theme.text.headlineMediumEmphasized
                  : theme.text.displaySmallEmphasized;
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    charging
                        ? Icons.battery_charging_full_rounded
                        : Icons.battery_std_rounded,
                    size: compact ? 18 : 24,
                    color: charging
                        ? ShellTelemetryColors.charging
                        : palette.onSecondaryContainer.withValues(alpha: 0.7),
                  ),
                  const SizedBox(height: ShellSpacing.xs),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      percent,
                      maxLines: 1,
                      softWrap: false,
                      style: percentStyle.copyWith(
                        color: palette.onSecondaryContainer,
                      ),
                    ),
                  ),
                  if (!compact && stateLabel.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: ShellSpacing.xs),
                      child: Text(
                        stateLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                        style: theme.text.labelMedium.copyWith(
                          color: palette.onSecondaryContainer.withValues(
                            alpha: 0.7,
                          ),
                        ),
                      ),
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
