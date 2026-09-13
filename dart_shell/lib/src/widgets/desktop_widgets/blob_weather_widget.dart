part of 'desktop_widgets.dart';

/// Weather blob: large emphasized temperature, condition glyph, and city
/// (02-VISUAL-SPEC.md §6). Data comes from the read-only `weatherProvider`
/// snapshot; [refresh] is cache-gated to `weatherCacheLifetime`, so piggy-
/// backing it on the existing minute-tick `clockProvider` keeps the widget
/// fresh without adding any timer of its own.
class BlobWeatherWidget extends ConsumerStatefulWidget {
  const BlobWeatherWidget({super.key});

  @override
  ConsumerState<BlobWeatherWidget> createState() => _BlobWeatherWidgetState();
}

class _BlobWeatherWidgetState extends ConsumerState<BlobWeatherWidget> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(ref.read(weatherProvider.notifier).refresh());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(clockProvider, (_, _) {
      unawaited(ref.read(weatherProvider.notifier).refresh());
    });
    final state = ref.watch(weatherProvider);
    final temperatureUnit = ref.watch(
      shellSettingsProvider.select(
        (settings) => settings.weather.temperatureUnit,
      ),
    );
    final palette = context.shellTheme.accentPalette;
    final snapshot = state.snapshot;
    final l10n = context.l10n;

    final String semanticLabel;
    final Widget content;
    if (snapshot != null) {
      final current = snapshot.current;
      final now = cityNow(snapshot.utcOffsetSeconds);
      final day = snapshot.days.isEmpty ? null : snapshot.days.first;
      final condition = weatherConditionFor(current.weatherCode);
      final temperature = formatTemperature(
        current.temperatureC,
        temperatureUnit,
      );
      final conditionLabel = weatherConditionLabel(
        l10n,
        current.weatherCode,
      );
      semanticLabel =
          '$temperature, $conditionLabel, ${snapshot.location.city}';
      content = _BlobWeatherContent(
        icon: condition.icon(day: isDaylight(now, day)),
        temperature: temperature,
        title: snapshot.location.city,
        subtitle: conditionLabel,
        iconColor: palette.tertiary,
        foreground: palette.onTertiaryContainer,
      );
    } else {
      final loading =
          state.status == WeatherStatus.locating ||
          state.status == WeatherStatus.loading;
      final label = switch (state.status) {
        WeatherStatus.locating => l10n.weatherLoadingLocating,
        WeatherStatus.loading => l10n.weatherLoadingData,
        WeatherStatus.failed => state.error is WeatherLocationFailure
            ? l10n.weatherErrorLocationUnavailable
            : l10n.weatherErrorLoadFailed,
        _ => l10n.weatherLoadingData,
      };
      semanticLabel = label;
      content = _BlobWeatherContent(
        icon: loading
            ? Icons.cloud_sync_rounded
            : Icons.cloud_off_rounded,
        temperature: l10n.batteryCapacityUnavailable,
        title: label,
        subtitle: null,
        iconColor: palette.tertiary,
        foreground: palette.onTertiaryContainer,
      );
    }

    return Semantics(
      label: semanticLabel,
      child: DesktopWidgetEntrance(
        child: DesktopBlobContainer(
          shape: DesktopBlobShape.cookie,
          color: palette.tertiaryContainer,
          padding: const EdgeInsets.all(ShellSpacing.lg),
          child: content,
        ),
      ),
    );
  }
}

class _BlobWeatherContent extends StatelessWidget {
  const _BlobWeatherContent({
    required this.icon,
    required this.temperature,
    required this.title,
    required this.subtitle,
    required this.iconColor,
    required this.foreground,
  });

  final IconData icon;
  final String temperature;
  final String title;
  final String? subtitle;
  final Color iconColor;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 96;
        final iconSize = math
            .min(constraints.maxHeight * 0.4, 40)
            .clamp(20.0, 40.0)
            .toDouble();
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: iconSize, color: iconColor),
            const SizedBox(width: ShellSpacing.md),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    temperature,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: theme.text.displaySmallEmphasized.copyWith(
                      color: foreground,
                    ),
                  ),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: theme.text.labelMedium.copyWith(
                      color: foreground.withValues(alpha: 0.8),
                    ),
                  ),
                  if (subtitle != null && !compact)
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      style: theme.text.labelSmall.copyWith(
                        color: foreground.withValues(alpha: 0.62),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
