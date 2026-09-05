import 'package:flutter/foundation.dart';

/// Immutable snapshot of the device battery.
@immutable
class BatteryStatus {
  const BatteryStatus({
    required this.capacity,
    required this.charging,
    this.full = false,
    this.acOnline = false,
  });

  static const BatteryStatus unknown = BatteryStatus(
    capacity: null,
    charging: false,
  );

  /// Percentage in `[0, 100]`, or null when unavailable.
  final int? capacity;

  /// The battery is actively drawing charge right now.
  final bool charging;

  /// At least one battery reports `Full`, so external power is connected and
  /// the pack cannot hold more charge.
  final bool full;

  /// External power is connected, derived from a mains supply's `online`
  /// flag or from battery statuses that cannot occur on battery power.
  final bool acOnline;

  String get label {
    final percent = capacity == null ? '--' : '$capacity%';
    return charging ? '$percent in carica' : percent;
  }

  @override
  bool operator ==(Object other) =>
      other is BatteryStatus &&
      other.capacity == capacity &&
      other.charging == charging &&
      other.full == full &&
      other.acOnline == acOnline;

  @override
  int get hashCode => Object.hash(capacity, charging, full, acOnline);
}
