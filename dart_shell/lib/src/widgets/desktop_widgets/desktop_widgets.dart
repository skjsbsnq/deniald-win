/// MD3E blob widget family shared by the desktop widget canvas and the
/// mobile home grid (02-VISUAL-SPEC.md §6).
///
/// Every widget paints inside a tonal, blurred, borderless blob outline —
/// [DesktopBlobContainer]/[DesktopWidgetSurface] — and animates in once via
/// [DesktopWidgetEntrance]. No widget owns an idle ticker: the clock follows
/// the minute-granularity `clockProvider`, weather and battery render
/// provider snapshots.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../desktop/shelf/dashboard/weather/weather_hero_section.dart';
import '../../desktop/shelf/dashboard/weather/weather_temperature.dart';
import '../../launcher/models/home_clock_info.dart';
import '../../localization/denial_localizations.dart';
import '../../services/weather_service.dart';
import '../../settings/settings_application.dart';
import '../../settings/settings_controller.dart';
import '../../state/desktop_notifications.dart';
import '../../state/quick_settings.dart';
import '../../state/session_power.dart';
import '../../state/system_status.dart';
import '../../state/weather_state.dart';
import '../../theme/motion.dart';
import '../../theme/shell_theme.dart';
import '../../theme/tokens.dart';
import '../session/power_session_surface.dart';
import '../shell_backdrop_blur.dart';
import '../shell_expressive_surface.dart';

part 'blob_shape.dart';
part 'desktop_widget_surface.dart';
part 'blob_clock_widget.dart';
part 'blob_weather_widget.dart';
part 'blob_battery_widget.dart';
part 'quick_action_pill_row.dart';
