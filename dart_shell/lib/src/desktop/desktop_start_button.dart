import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../input/shell_interaction_registry.dart';
import '../localization/denial_localizations.dart';
import '../models/display_layout.dart';
import '../theme/motion.dart';
import '../theme/shell_theme.dart';
import '../wallpaper/state/wallpaper_accent.dart';
import '../widgets/denial_wordmark.dart';
import '../widgets/shell_cursor.dart';
import 'desktop_taskbar_button.dart';
import 'desktop_workspace.dart';

/// Windows 11-style Start Menu button on the desktop system bar.
///
/// Features the Denial brand wordmark, active state tracking for the application
/// launcher panel, keyboard focus navigation (Enter/Space to trigger), and
/// localization support.
class DesktopStartButton extends ConsumerStatefulWidget {
  const DesktopStartButton({required this.side, this.onTap, super.key});

  final SystemBarSide side;
  final VoidCallback? onTap;

  @override
  ConsumerState<DesktopStartButton> createState() => _DesktopStartButtonState();
}

class _DesktopStartButtonState extends ConsumerState<DesktopStartButton> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  void _handleTap() {
    if (widget.onTap != null) {
      widget.onTap!();
    } else {
      final workspace = ref.read(desktopWorkspaceProvider.notifier);
      final isOpen = ref.read(desktopWorkspaceProvider).launcherOpen;
      if (isOpen) {
        workspace.closePanels();
      } else {
        workspace.showPanel(DesktopPanel.launcher);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final launcherOpen = ref.watch(
      desktopWorkspaceProvider.select((state) => state.launcherOpen),
    );
    final accent = ref.watch(shellAccentProvider);
    final theme = ShellTheme.of(context);
    final l10n = context.l10n;
    final horizontal = widget.side.isHorizontal;

    final accentColor = accent.color;

    // Background highlight
    Color backgroundColor = Colors.transparent;
    if (launcherOpen) {
      backgroundColor = theme.panelColor(accent.cardFillTop);
    } else if (_pressed) {
      backgroundColor = Colors.white.withValues(alpha: 0.16);
    } else if (_hovered) {
      backgroundColor = Colors.white.withValues(alpha: 0.08);
    }

    final tooltip = l10n.desktopStartButton;
    final semanticLabel = launcherOpen
        ? l10n.desktopStartButtonClose
        : l10n.desktopStartButtonOpen;

    // Active indicator
    final double indicatorLength = launcherOpen
        ? DesktopTaskbarButtonMetrics.activeIndicatorLength
        : (_hovered ? 10.0 : 0.0);

    Widget? indicator;
    if (horizontal) {
      final isTop = widget.side == SystemBarSide.top;
      indicator = Positioned(
        bottom: isTop ? null : 1.0,
        top: isTop ? 1.0 : null,
        left: 0,
        right: 0,
        child: Center(
          child: AnimatedContainer(
            duration: Motion.pill,
            curve: Motion.standard,
            width: indicatorLength,
            height: DesktopTaskbarButtonMetrics.indicatorThickness,
            decoration: BoxDecoration(
              color: launcherOpen
                  ? accentColor
                  : Colors.white.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(
                DesktopTaskbarButtonMetrics.indicatorRadius,
              ),
            ),
          ),
        ),
      );
    } else {
      final isLeft = widget.side == SystemBarSide.left;
      indicator = Positioned(
        left: isLeft ? 1.0 : null,
        right: isLeft ? null : 1.0,
        top: 0,
        bottom: 0,
        child: Center(
          child: AnimatedContainer(
            duration: Motion.pill,
            curve: Motion.standard,
            width: DesktopTaskbarButtonMetrics.indicatorThickness,
            height: indicatorLength,
            decoration: BoxDecoration(
              color: launcherOpen
                  ? accentColor
                  : Colors.white.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(
                DesktopTaskbarButtonMetrics.indicatorRadius,
              ),
            ),
          ),
        ),
      );
    }

    const buttonHeight = DesktopTaskbarButtonMetrics.buttonHeight;
    final double buttonWidth = horizontal ? 42.0 : 32.0;

    Widget buttonContent = Center(
      child: SizedBox(
        width: horizontal ? 28.0 : 20.0,
        height: 18.0,
        child: DenialWordmark(semanticsLabel: tooltip, fit: BoxFit.contain),
      ),
    );

    Widget buttonBody = AnimatedContainer(
      duration: Motion.pill,
      curve: Motion.standard,
      height: buttonHeight,
      width: buttonWidth,
      padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 4.0),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(
          DesktopTaskbarButtonMetrics.buttonRadius,
        ),
        border: _focused
            ? Border.all(color: accentColor, width: 1.0)
            : Border.all(color: Colors.transparent, width: 1.0),
      ),
      child: buttonContent,
    );

    buttonBody = Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [buttonBody, indicator],
    );

    return RepaintBoundary(
      child: ShellInputRegion(
        debugLabel: 'System bar start button',
        child: Tooltip(
          message: tooltip,
          waitDuration: const Duration(milliseconds: 500),
          child: Semantics(
            button: true,
            label: semanticLabel,
            child: Focus(
              onFocusChange: (focused) {
                if (_focused != focused && mounted) {
                  setState(() => _focused = focused);
                }
              },
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent &&
                    (event.logicalKey == LogicalKeyboardKey.enter ||
                        event.logicalKey == LogicalKeyboardKey.space)) {
                  _handleTap();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: MouseRegion(
                cursor: ShellMouseCursors.link,
                onEnter: (_) {
                  if (!_hovered && mounted) {
                    setState(() => _hovered = true);
                  }
                },
                onExit: (_) {
                  if (_hovered && mounted) {
                    setState(() {
                      _hovered = false;
                      _pressed = false;
                    });
                  }
                },
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (_) {
                    if (!_pressed && mounted) {
                      setState(() => _pressed = true);
                    }
                  },
                  onTapUp: (_) {
                    if (_pressed && mounted) {
                      setState(() => _pressed = false);
                    }
                  },
                  onTapCancel: () {
                    if (_pressed && mounted) {
                      setState(() => _pressed = false);
                    }
                  },
                  onTap: _handleTap,
                  child: buttonBody,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
