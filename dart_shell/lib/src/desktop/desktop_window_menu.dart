import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../localization/denial_localizations.dart';
import '../models/denial_window.dart';
import '../theme/motion.dart';
import '../theme/shell_theme.dart';
import '../theme/tokens.dart';
import '../widgets/shell_surface_host.dart';
import 'desktop_window_titlebar.dart';

/// Shows the window action context menu near [position].
///
/// Uses [shellSurfaceControllerProvider] to display a transient surface with
/// outside-tap and Escape dismissal policies.
ShellSurfaceHandle showDesktopWindowMenu({
  required BuildContext context,
  required WidgetRef ref,
  required DenialWindow window,
  required Offset position,
  required bool maximized,
  required bool fullscreen,
  required bool overviewActive,
  required VoidCallback onMinimize,
  required VoidCallback onToggleMaximize,
  required VoidCallback onClose,
}) {
  return ref
      .read(shellSurfaceControllerProvider.notifier)
      .show(
        keyName: 'desktop-window-menu-${window.objectId}',
        debugLabel: 'Desktop window menu ${window.objectId}',
        barrierColor: const Color(0x00000000),
        dismissPolicy: ShellDismissPolicy.outsideTapAndEscape,
        transitionDuration: Motion.cardSettle,
        builder: (context, handle) => DesktopWindowMenu(
          handle: handle,
          window: window,
          position: position,
          maximized: maximized,
          fullscreen: fullscreen,
          overviewActive: overviewActive,
          onMinimize: onMinimize,
          onToggleMaximize: onToggleMaximize,
          onClose: onClose,
        ),
      );
}

/// The context popup menu widget displayed for window actions.
class DesktopWindowMenu extends StatelessWidget {
  const DesktopWindowMenu({
    super.key,
    required this.handle,
    required this.window,
    required this.position,
    required this.maximized,
    required this.fullscreen,
    required this.overviewActive,
    required this.onMinimize,
    required this.onToggleMaximize,
    required this.onClose,
  });

  final ShellSurfaceHandle handle;
  final DenialWindow window;
  final Offset position;
  final bool maximized;
  final bool fullscreen;
  final bool overviewActive;
  final VoidCallback onMinimize;
  final VoidCallback onToggleMaximize;
  final VoidCallback onClose;

  static const double menuWidth = 168.0;
  static const double estimatedMenuHeight = 136.0;
  static const double margin = 8.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenSize = Size(constraints.maxWidth, constraints.maxHeight);

        double left = position.dx;
        if (left + menuWidth + margin > screenSize.width) {
          left = position.dx - menuWidth;
        }
        left = left.clamp(
          margin,
          math.max(margin, screenSize.width - menuWidth - margin),
        );

        double top = position.dy;
        if (top + estimatedMenuHeight + margin > screenSize.height) {
          top = position.dy - estimatedMenuHeight;
        }
        top = top.clamp(
          margin,
          math.max(margin, screenSize.height - estimatedMenuHeight - margin),
        );

        return Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              width: menuWidth,
              child: _DesktopWindowMenuCard(
                handle: handle,
                maximized: maximized,
                fullscreen: fullscreen,
                overviewActive: overviewActive,
                onMinimize: onMinimize,
                onToggleMaximize: onToggleMaximize,
                onClose: onClose,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DesktopWindowMenuCard extends StatelessWidget {
  const _DesktopWindowMenuCard({
    required this.handle,
    required this.maximized,
    required this.fullscreen,
    required this.overviewActive,
    required this.onMinimize,
    required this.onToggleMaximize,
    required this.onClose,
  });

  final ShellSurfaceHandle handle;
  final bool maximized;
  final bool fullscreen;
  final bool overviewActive;
  final VoidCallback onMinimize;
  final VoidCallback onToggleMaximize;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = ShellTheme.of(context);
    final l10n = context.l10n;

    final minimizeEnabled = !overviewActive;
    final maximizeEnabled = !fullscreen;

    return FocusTraversalGroup(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.panelColor(ShellColors.surfaceContainerHigh),
          borderRadius: BorderRadius.circular(theme.panelRadius),
          border: Border.all(color: ShellColors.hairline),
          boxShadow: const [
            BoxShadow(
              color: ShellColors.shadow,
              blurRadius: 16.0,
              spreadRadius: 1.0,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 4.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _WindowMenuItem(
                autofocus: true,
                type: TitlebarButtonType.minimize,
                maximized: false,
                label: l10n.windowMinimize,
                enabled: minimizeEnabled,
                onPressed: () {
                  handle.close();
                  onMinimize();
                },
              ),
              _WindowMenuItem(
                type: TitlebarButtonType.maximize,
                maximized: maximized,
                label: maximized ? l10n.windowRestore : l10n.windowMaximize,
                enabled: maximizeEnabled,
                onPressed: () {
                  handle.close();
                  onToggleMaximize();
                },
              ),
              const _WindowMenuDivider(),
              _WindowMenuItem(
                type: TitlebarButtonType.close,
                maximized: false,
                label: l10n.windowClose,
                enabled: true,
                onPressed: () {
                  handle.close();
                  onClose();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WindowMenuItem extends StatefulWidget {
  const _WindowMenuItem({
    this.autofocus = false,
    required this.type,
    required this.maximized,
    required this.label,
    required this.enabled,
    required this.onPressed,
  });

  final bool autofocus;
  final TitlebarButtonType type;
  final bool maximized;
  final String label;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  State<_WindowMenuItem> createState() => _WindowMenuItemState();
}

class _WindowMenuItemState extends State<_WindowMenuItem> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final theme = ShellTheme.of(context);
    final highlighted = (widget.enabled) && (_hovered || _focused);

    final textColor = widget.enabled
        ? ShellColors.textPrimary
        : ShellColors.textTertiary;
    final iconColor = widget.enabled
        ? ShellColors.textPrimary
        : ShellColors.textTertiary;
    final backgroundColor = highlighted
        ? const Color(0x1FFFFFFF)
        : const Color(0x00000000);

    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: widget.label,
      child: Focus(
        autofocus: widget.autofocus && widget.enabled,
        onFocusChange: (focused) => setState(() => _focused = focused),
        onKeyEvent: (node, event) {
          if (!widget.enabled) {
            return KeyEventResult.ignored;
          }
          if (event is KeyDownEvent &&
              (event.logicalKey == LogicalKeyboardKey.enter ||
                  event.logicalKey == LogicalKeyboardKey.space)) {
            widget.onPressed();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: MouseRegion(
          cursor: widget.enabled
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.enabled ? widget.onPressed : null,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(
                  math.max(0.0, theme.panelRadius - 4.0),
                ),
              ),
              child: SizedBox(
                height: 32.0,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10.0),
                  child: Row(
                    children: [
                      SizedBox.square(
                        dimension: 14.0,
                        child: Center(
                          child: CustomPaint(
                            size: const Size(10.0, 10.0),
                            painter: TitlebarGlyphPainter(
                              type: widget.type,
                              maximized: widget.maximized,
                              color: iconColor,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10.0),
                      Expanded(
                        child: Text(
                          widget.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: textColor,
                            fontSize: 12.0,
                            fontWeight: FontWeight.w500,
                            fontFamilyFallback: ShellText.fallbackFontFamilies,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WindowMenuDivider extends StatelessWidget {
  const _WindowMenuDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 8.0, vertical: 3.0),
      child: SizedBox(
        height: 1.0,
        child: ColoredBox(color: ShellColors.hairlineSoft),
      ),
    );
  }
}
