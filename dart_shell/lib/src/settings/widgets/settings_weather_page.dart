import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../localization/denial_localizations.dart';
import '../../services/weather_service.dart';
import '../../theme/shell_theme.dart';
import '../../theme/tokens.dart';
import '../shell_settings.dart';
import 'settings_controls.dart';

const settingsWeatherLocationModeKey = ValueKey<String>(
  'settings-weather-location-mode',
);
const settingsWeatherUnitKey = ValueKey<String>('settings-weather-unit');
const settingsWeatherSearchFieldKey = ValueKey<String>(
  'settings-weather-search-field',
);
const settingsWeatherSearchResultsKey = ValueKey<String>(
  'settings-weather-search-results',
);

class SettingsWeatherPage extends ConsumerWidget {
  const SettingsWeatherPage({
    required this.settings,
    required this.onLocationModeChanged,
    required this.onManualLocationChanged,
    required this.onTemperatureUnitChanged,
    required this.onReset,
    super.key,
  });

  final ShellWeatherSettings settings;
  final ValueChanged<ShellWeatherLocationMode> onLocationModeChanged;
  final ValueChanged<ShellManualLocation?> onManualLocationChanged;
  final ValueChanged<ShellTemperatureUnit> onTemperatureUnitChanged;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return SettingsPageLayout(
      icon: Icons.cloud_outlined,
      eyebrow: l10n.settingsWeatherSection,
      title: l10n.settingsWeatherTitle,
      onReset: onReset,
      children: <Widget>[
        SettingsCardGroup(
          children: <Widget>[
            SettingsSection(
              title: l10n.settingsWeatherLocationMode,
              leading: _WeatherIcon(accent: ShellTheme.of(context).accent),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SettingsSegmentedControl<ShellWeatherLocationMode>(
                    key: settingsWeatherLocationModeKey,
                    value: settings.locationMode,
                    choices: [
                      SettingsChoice(
                        ShellWeatherLocationMode.auto,
                        l10n.settingsWeatherLocationAuto,
                      ),
                      SettingsChoice(
                        ShellWeatherLocationMode.manual,
                        l10n.settingsWeatherLocationManual,
                      ),
                    ],
                    onChanged: onLocationModeChanged,
                  ),
                  if (settings.locationMode ==
                      ShellWeatherLocationMode.manual) ...[
                    const SizedBox(height: 18),
                    if (settings.manualLocation case final current?) ...[
                      Text(
                        l10n.settingsWeatherCurrentCity(current.city),
                        style: ShellText.base.copyWith(
                          color: context.shellColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 18),
                    ],
                    _CitySearchField(onSelected: onManualLocationChanged),
                  ],
                ],
              ),
            ),
            SettingsSection(
              title: l10n.settingsWeatherTemperatureUnit,
              leading: _WeatherIcon(accent: ShellTheme.of(context).accent),
              child: SettingsSegmentedControl<ShellTemperatureUnit>(
                key: settingsWeatherUnitKey,
                value: settings.temperatureUnit,
                choices: [
                  SettingsChoice(
                    ShellTemperatureUnit.celsius,
                    l10n.settingsWeatherUnitCelsius,
                  ),
                  SettingsChoice(
                    ShellTemperatureUnit.fahrenheit,
                    l10n.settingsWeatherUnitFahrenheit,
                  ),
                ],
                onChanged: onTemperatureUnitChanged,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Debounced city search backed by the Open-Meteo geocoding API. Picking a
/// result pins the manual location used by the dashboard weather page.
class _CitySearchField extends ConsumerStatefulWidget {
  const _CitySearchField({required this.onSelected});

  final ValueChanged<ShellManualLocation?> onSelected;

  @override
  ConsumerState<_CitySearchField> createState() => _CitySearchFieldState();
}

class _CitySearchFieldState extends ConsumerState<_CitySearchField> {
  static const Duration _searchDebounce = Duration(milliseconds: 350);

  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  var _generation = 0;
  List<GeoLocation> _results = const <GeoLocation>[];
  bool _searching = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // Pin the autoDispose service for this field's lifetime: a transient read
    // lets the provider be reclaimed mid-search, and its dispose closes the
    // HttpClient with force, aborting the in-flight geocoding request.
    ref.watch(weatherServiceProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: settingsWeatherSearchFieldKey,
          controller: _controller,
          onSubmitted: (value) {
            _debounce?.cancel();
            unawaited(_search(value));
          },
          onChanged: _scheduleSearch,
          style: ShellText.base.copyWith(
            color: context.shellColors.textPrimary,
            fontSize: 13,
          ),
          decoration: InputDecoration(
            isDense: true,
            hintText: l10n.settingsWeatherSearchPlaceholder,
            hintStyle: ShellText.base.copyWith(
              color: context.shellColors.textTertiary,
              fontSize: 13,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: context.shellTheme.borderRadius(ShellRadii.chip),
              borderSide: BorderSide(color: context.shellColors.hairlineSoft),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: context.shellTheme.borderRadius(ShellRadii.chip),
              borderSide: BorderSide(
                color: ShellTheme.of(context).accent.withAlpha(160),
              ),
            ),
          ),
        ),
        if (_searching) ...[
          const SizedBox(height: 10),
          Text(
            l10n.settingsWeatherSearching,
            style: ShellText.base.copyWith(
              color: context.shellColors.textTertiary,
              fontSize: 12,
            ),
          ),
        ] else if (_results.isEmpty) ...[
          const SizedBox(height: 10),
          Text(
            l10n.settingsWeatherSearchNoResults,
            style: ShellText.base.copyWith(
              color: context.shellColors.textTertiary,
              fontSize: 12,
            ),
          ),
        ] else ...[
          const SizedBox(height: 10),
          Column(
            key: settingsWeatherSearchResultsKey,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final result in _results)
                _CityResultRow(
                  result: result,
                  onPressed: () {
                    widget.onSelected(
                      ShellManualLocation(
                        latitude: result.latitude,
                        longitude: result.longitude,
                        city: result.city,
                      ),
                    );
                  },
                ),
            ],
          ),
        ],
      ],
    );
  }

  void _scheduleSearch(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() {
        _results = const <GeoLocation>[];
        _searching = false;
      });
      return;
    }
    _debounce = Timer(_searchDebounce, () {
      unawaited(_search(value));
    });
  }

  Future<void> _search(String value) async {
    final generation = ++_generation;
    setState(() => _searching = true);
    List<GeoLocation> results;
    try {
      final service = ref.read(weatherServiceProvider);
      results = await service.searchCities(value);
    } on Object {
      results = const <GeoLocation>[];
    }
    if (!mounted || generation != _generation) {
      return;
    }
    setState(() {
      _results = results;
      _searching = false;
    });
  }
}

class _CityResultRow extends StatelessWidget {
  const _CityResultRow({required this.result, required this.onPressed});

  final GeoLocation result;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.shellColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surfaceContainerHigh,
              borderRadius: context.shellTheme.borderRadius(ShellRadii.chip),
              border: Border.all(color: colors.hairlineSoft),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(
                children: [
                  Icon(
                    Icons.location_on_outlined,
                    size: 15,
                    color: ShellTheme.of(context).accent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      result.city,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ShellText.base.copyWith(
                        color: colors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    '${result.latitude.toStringAsFixed(2)}, '
                    '${result.longitude.toStringAsFixed(2)}',
                    style: ShellText.base.copyWith(
                      color: colors.textTertiary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WeatherIcon extends StatelessWidget {
  const _WeatherIcon({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: accent.withAlpha(34),
        shape: BoxShape.circle,
        border: Border.all(color: accent.withAlpha(92)),
      ),
      child: SizedBox.square(
        dimension: 42,
        child: Icon(Icons.cloud_outlined, size: 20, color: accent),
      ),
    );
  }
}
