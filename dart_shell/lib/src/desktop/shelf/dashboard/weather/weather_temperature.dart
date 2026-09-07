import '../../../../settings/shell_settings.dart';

/// Formats a Celsius value for display in the requested unit. Hourly and
/// daily charts keep plotting raw Celsius (min-max normalization makes the
/// curve shape unit-invariant); only the textual readouts convert.
String formatTemperature(double celsius, ShellTemperatureUnit unit) {
  final value = switch (unit) {
    ShellTemperatureUnit.celsius => celsius,
    ShellTemperatureUnit.fahrenheit => celsius * 9 / 5 + 32,
  };
  return '${value.round()}°';
}
