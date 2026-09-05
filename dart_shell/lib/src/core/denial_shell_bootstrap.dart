import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../config/startup_environment.dart';
import '../desktop/desktop_window_render_telemetry.dart';
import '../local_apps/local_flutter_application.dart';
import '../theme/motion.dart';

typedef DenialLocalApplicationsBuilder =
    List<LocalFlutterApplication> Function(StartupEnvironment environment);

/// Starts a Denial shell with the complete required process configuration.
///
/// A custom shell entry point normally needs only this function and a
/// [DenialShell] widget. Startup environment capture, Flutter binding setup,
/// diagnostics, Riverpod ownership, and local application registration stay
/// consistent with the stock shell.
void runDenialShell({
  required Widget shell,
  DenialLocalApplicationsBuilder? localApplications,
}) {
  final environment = StartupEnvironment.capture();
  WidgetsFlutterBinding.ensureInitialized();
  // The default 100-entry LRU is smaller than one launcher catalog plus the
  // shelf and tray icons, so an icon-heavy browse evicts resident icons and
  // every reopen re-decodes them. Compiled icon vectors are a few KB each, so
  // a larger budget keeps working sets resident without a real memory cost.
  svg.cache.maximumSize = 500;
  MotionTelemetry.install(enabled: environment.flag('DENIA_DART_FRAME_TRACE'));
  DesktopWindowRenderTelemetry.install(
    enabled: environment.flag('DENIA_RENDER_AUDIT'),
  );
  runApp(
    ProviderScope(
      overrides: [
        startupEnvironmentProvider.overrideWithValue(environment),
        localFlutterApplicationsProvider.overrideWithValue(
          localApplications?.call(environment) ??
              const <LocalFlutterApplication>[],
        ),
      ],
      child: shell,
    ),
  );
}
