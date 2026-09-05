import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../settings/settings_controller.dart';
import '../../state/system_tray.dart';
import '../../theme/shell_theme.dart';
import '../../widgets/shell_backdrop_blur.dart';
import '../system_tray_module.dart';
import 'shelf_app_strip.dart';
import 'shelf_launcher_button.dart';
import 'unified_tray_button.dart';

/// The bottom shelf backdrop container for the ChromeOS-style shell.
class ShelfLayer extends ConsumerWidget {
  const ShelfLayer({
    this.height,
    this.onLauncherPressed,
    this.trayExpanded = false,
    this.onTrayPressed,
    super.key,
  });

  static const double defaultThickness = 56.0;

  final double? height;
  final VoidCallback? onLauncherPressed;
  final bool trayExpanded;
  final VoidCallback? onTrayPressed;

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
                    const Spacer(),
                    const _ShelfSystemTrayModule(),
                    const SizedBox(width: 8.0),
                    UnifiedTrayButton(
                      key: const ValueKey('shelf-tray-button'),
                      expanded: trayExpanded,
                      onPressed: onTrayPressed ?? () {},
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
