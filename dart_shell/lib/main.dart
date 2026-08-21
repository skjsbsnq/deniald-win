import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/svg.dart' as flutter_svg;

import 'src/config/startup_environment.dart';
import 'src/desktop/desktop_window_render_telemetry.dart';
import 'src/local_apps/local_flutter_application.dart';
import 'src/settings/settings_application.dart';
import 'src/shell_app.dart';
import 'src/theme/motion.dart';

void main() {
  final environment = StartupEnvironment.capture();
  WidgetsFlutterBinding.ensureInitialized();
  flutter_svg.svg.cache.maximumSize = 512;
  MotionTelemetry.install(enabled: environment.flag('DENIA_DART_FRAME_TRACE'));
  DesktopWindowRenderTelemetry.install(
    enabled: environment.flag('DENIA_RENDER_AUDIT'),
  );
  runApp(
    ProviderScope(
      overrides: [
        startupEnvironmentProvider.overrideWithValue(environment),
        localFlutterApplicationsProvider.overrideWithValue(
          <LocalFlutterApplication>[denialSettingsApplication],
        ),
      ],
      child: const DenialShellApp(),
    ),
  );
}
