import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../settings/settings_controller.dart';
import '../../state/system_tray.dart';
import '../../theme/shell_theme.dart';
import '../../theme/tokens.dart';
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
    // The floating bar keeps the full thickness track so work-area geometry is
    // unchanged; it only visually insets itself from the screen edges.
    final barRadius = theme.borderRadius(ShellShapeScale.extraLarge);

    return SizedBox(
      height: effectiveHeight,
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.only(
          left: ShellSpacing.sm,
          right: ShellSpacing.sm,
          bottom: ShellSpacing.sm,
        ),
        child: ShellBackdropBlur(
          borderRadius: barRadius,
          separateChild: true,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: theme.panelColor(colors.surfaceContainer),
              borderRadius: barRadius,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: ShellSpacing.sm,
              ),
              child: Row(
                children: [
                  ShelfLauncherButton(
                    key: const ValueKey('shelf-launcher-button'),
                    onPressed: onLauncherPressed,
                  ),
                  const SizedBox(width: ShellSpacing.sm),
                  // The Desk button lives on the shelf's left edge, between
                  // the launcher and the application strip, so it never
                  // competes with the app icons for space.
                  ShelfWorkspaceButton(
                    key: const ValueKey('shelf-workspace-button'),
                    monitorId: monitorId,
                  ),
                  // The strip owns the leftover span: it centers itself while
                  // everything fits and shrinks into a horizontal scroll view
                  // when the launcher and tray clusters squeeze it, instead of
                  // painting underneath them.
                  const Expanded(
                    child: ShelfAppStrip(key: ValueKey('shelf-app-strip')),
                  ),
                  const _ShelfSystemTrayModule(),
                  const SizedBox(width: ShellSpacing.sm),
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
