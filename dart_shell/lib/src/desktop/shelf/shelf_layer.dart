import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../settings/settings_controller.dart';
import '../../state/system_tray.dart';
import '../../theme/shell_theme.dart';
import '../../widgets/shell_backdrop_blur.dart';
import '../system_tray_module.dart';
import 'shelf_app_strip.dart';
import 'shelf_launcher_button.dart';
import 'shelf_workspace_button.dart';
import 'unified_tray_button.dart';

/// The bottom shelf backdrop container for the ChromeOS-style shell.
class ShelfLayer extends ConsumerWidget {
  const ShelfLayer({
    this.height,
    this.monitorId,
    this.onLauncherPressed,
    required this.trayExpanded,
    this.onTrayPressed,
    this.calendarExpanded,
    this.onClockPressed,
    super.key,
  });

  static const double defaultThickness = 56.0;

  final double? height;

  /// Output this shelf belongs to. The workspace Desk button is scoped to it.
  final int? monitorId;
  final VoidCallback? onLauncherPressed;

  /// Listenable so tray expansion rebuilds the tray button alone, not the
  /// complete shelf with its app strip and tray icons.
  final ValueListenable<bool> trayExpanded;
  final VoidCallback? onTrayPressed;

  /// Listenable so calendar expansion rebuilds the clock button without
  /// invalidating the rest of the shelf.
  final ValueListenable<bool>? calendarExpanded;
  final VoidCallback? onClockPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.shellTheme;
    final colors = context.shellColors;
    final configuredThickness = ref.watch(
      shellSettingsProvider.select((s) => s.layout.effectiveSystemBarThickness),
    );
    final effectiveHeight =
        height ??
        (configuredThickness > 0 ? configuredThickness : defaultThickness);

    return SizedBox(
      height: effectiveHeight,
      width: double.infinity,
      child: ShellBackdropBlur(
        borderRadius: BorderRadius.zero,
        separateChild: true,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.panelColor(colors.surfaceContainer),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Positioned.fill(
                  child: Center(
                    child: ShelfAppStrip(key: ValueKey('shelf-app-strip')),
                  ),
                ),
                Row(
                  children: [
                    ShelfLauncherButton(
                      key: const ValueKey('shelf-launcher-button'),
                      onPressed: onLauncherPressed,
                    ),
                    const SizedBox(width: 8.0),
                    // The Desk button lives on the shelf's left edge, between
                    // the launcher and the centered application strip, so it
                    // never competes with the app icons for space.
                    ShelfWorkspaceButton(
                      key: const ValueKey('shelf-workspace-button'),
                      monitorId: monitorId,
                    ),
                    const Spacer(),
                    const _ShelfSystemTrayModule(),
                    const SizedBox(width: 8.0),
                    ValueListenableBuilder<bool>(
                      valueListenable: trayExpanded,
                      builder: (context, expanded, _) {
                        final calendar = calendarExpanded;
                        if (calendar != null) {
                          return ValueListenableBuilder<bool>(
                            valueListenable: calendar,
                            builder: (context, clockExpanded, _) =>
                                UnifiedTrayButton(
                                  key: const ValueKey('shelf-tray-button'),
                                  expanded: expanded,
                                  clockExpanded: clockExpanded,
                                  onPressed: onTrayPressed ?? () {},
                                  onClockPressed: onClockPressed,
                                ),
                          );
                        }
                        return UnifiedTrayButton(
                          key: const ValueKey('shelf-tray-button'),
                          expanded: expanded,
                          onPressed: onTrayPressed ?? () {},
                          onClockPressed: onClockPressed,
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Keeps changes to tray contents out of the complete shelf rebuild.
class _ShelfSystemTrayModule extends ConsumerWidget {
  const _ShelfSystemTrayModule();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SystemTrayModule(
      horizontal: true,
      accent: context.shellTheme.accent,
      items: ref.watch(systemTrayProvider),
    );
  }
}
