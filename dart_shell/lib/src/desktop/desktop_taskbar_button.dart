import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../input/shell_interaction_registry.dart';
import '../launcher/controllers/home_grid_controller.dart';
import '../launcher/models/desktop_app.dart';
import '../launcher/models/home_grid_item.dart';
import '../local_apps/local_flutter_application.dart';
import '../localization/denial_localizations.dart';
import '../models/denial_window.dart';
import '../models/display_layout.dart';
import '../state/shell_controller.dart';
import '../theme/motion.dart';
import '../theme/shell_theme.dart';
import '../theme/tokens.dart';
import '../wallpaper/state/wallpaper_accent.dart';
import '../widgets/app_icon.dart';
import 'desktop_taskbar_preview.dart';
import 'desktop_workspace.dart';

/// Metrics for individual desktop taskbar buttons.
class DesktopTaskbarButtonMetrics {
  const DesktopTaskbarButtonMetrics._();

  static const double buttonHeight = 32.0;
  static const double compactButtonWidth = 38.0;
  static const double minButtonWidth = 64.0;
  static const double maxButtonWidth = 160.0;
  static const double iconSize = 20.0;
  static const double indicatorThickness = 2.5;
  static const double indicatorRadius = 1.25;
  static const double activeIndicatorLength = 18.0;
  static const double inactiveIndicatorLength = 8.0;
  static const double minimizedIndicatorLength = 5.0;
  static const double buttonRadius = 6.0;
}

/// Pure parameter-driven taskbar button rendering an icon, optional title,
/// hover/focus states, and Win11-style active indicator.
class DesktopTaskbarButton extends StatefulWidget {
  const DesktopTaskbarButton({
    required this.icon,
    required this.title,
    required this.active,
    required this.minimized,
    required this.compact,
    required this.side,
    required this.onTap,
    this.onHoverEnter,
    this.onHoverLeave,
    this.tooltip,
    this.semanticLabel,
    this.accent,
    super.key,
  });

  final Widget icon;
  final String title;
  final bool active;
  final bool minimized;
  final bool compact;
  final SystemBarSide side;
  final VoidCallback? onTap;
  final void Function(Rect bounds)? onHoverEnter;
  final VoidCallback? onHoverLeave;
  final String? tooltip;
  final String? semanticLabel;
  final WallpaperAccent? accent;

  @override
  State<DesktopTaskbarButton> createState() => _DesktopTaskbarButtonState();
}

class _DesktopTaskbarButtonState extends State<DesktopTaskbarButton> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  void _handleHover(bool hovered) {
    if (_hovered != hovered && mounted) {
      setState(() => _hovered = hovered);
    }
    if (hovered) {
      final renderBox = context.findRenderObject();
      if (renderBox is RenderBox && renderBox.hasSize) {
        final origin = renderBox.localToGlobal(Offset.zero);
        widget.onHoverEnter?.call(origin & renderBox.size);
      }
    } else {
      widget.onHoverLeave?.call();
    }
  }

  void _handleFocus(bool focused) {
    if (_focused != focused && mounted) {
      setState(() => _focused = focused);
    }
  }

  @override
  Widget build(BuildContext context) {
    final horizontal = widget.side.isHorizontal;
    final theme = ShellTheme.of(context);
    final accentColor = widget.accent?.color ?? theme.accent;

    // Background highlight color based on active, pressed, hovered states.
    Color backgroundColor = Colors.transparent;
    if (widget.active) {
      backgroundColor = widget.accent != null
          ? theme.panelColor(widget.accent!.cardFillTop)
          : Colors.white.withValues(alpha: 0.12);
    }
    if (_pressed) {
      backgroundColor = Colors.white.withValues(alpha: 0.16);
    } else if (_hovered) {
      backgroundColor = widget.active
          ? Colors.white.withValues(alpha: 0.16)
          : Colors.white.withValues(alpha: 0.08);
    }

    final double contentOpacity = widget.minimized ? 0.65 : 1.0;

    // Build content row/column
    Widget content;
    if (widget.compact || !horizontal) {
      content = Center(
        child: SizedBox.square(
          dimension: DesktopTaskbarButtonMetrics.iconSize,
          child: widget.icon,
        ),
      );
    } else {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: DesktopTaskbarButtonMetrics.iconSize,
            child: widget.icon,
          ),
          const SizedBox(width: 8.0),
          Flexible(
            child: Text(
              widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ShellText.systemBarValue.copyWith(
                fontSize: 12.5,
                color: widget.active
                    ? ShellColors.textPrimary
                    : ShellColors.textSecondary,
                fontWeight: widget.active ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        ],
      );
    }

    // Active indicator layout
    final indicatorLength = widget.active
        ? DesktopTaskbarButtonMetrics.activeIndicatorLength
        : widget.minimized
        ? DesktopTaskbarButtonMetrics.minimizedIndicatorLength
        : DesktopTaskbarButtonMetrics.inactiveIndicatorLength;

    final indicatorColor = widget.active
        ? accentColor
        : widget.minimized
        ? Colors.white.withValues(alpha: 0.28)
        : Colors.white.withValues(alpha: 0.50);

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
              color: indicatorColor,
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
              color: indicatorColor,
              borderRadius: BorderRadius.circular(
                DesktopTaskbarButtonMetrics.indicatorRadius,
              ),
            ),
          ),
        ),
      );
    }

    Widget buttonBody = AnimatedContainer(
      duration: Motion.pill,
      curve: Motion.standard,
      height: DesktopTaskbarButtonMetrics.buttonHeight,
      constraints: BoxConstraints(
        minWidth: widget.compact || !horizontal
            ? DesktopTaskbarButtonMetrics.compactButtonWidth
            : DesktopTaskbarButtonMetrics.minButtonWidth,
        maxWidth: widget.compact || !horizontal
            ? DesktopTaskbarButtonMetrics.compactButtonWidth
            : DesktopTaskbarButtonMetrics.maxButtonWidth,
      ),
      padding: widget.compact || !horizontal
          ? const EdgeInsets.symmetric(horizontal: 6.0, vertical: 4.0)
          : const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(
          DesktopTaskbarButtonMetrics.buttonRadius,
        ),
        border: _focused
            ? Border.all(color: accentColor, width: 1.0)
            : Border.all(color: Colors.transparent, width: 1.0),
      ),
      child: Opacity(opacity: contentOpacity, child: content),
    );

    buttonBody = Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [buttonBody, indicator],
    );

    final semanticText =
        widget.semanticLabel ??
        (widget.active
            ? context.l10n.taskbarWindowMinimize(widget.title)
            : widget.minimized
            ? context.l10n.taskbarWindowRestore(widget.title)
            : context.l10n.taskbarWindowButton(widget.title));

    final tooltipText = widget.tooltip ?? widget.title;

    return RepaintBoundary(
      child: Semantics(
        button: true,
        label: semanticText,
        enabled: widget.onTap != null,
        child: Tooltip(
          message: tooltipText,
          waitDuration: const Duration(milliseconds: 600),
          child: ShellInputRegion(
            debugLabel: 'Taskbar button (${widget.title})',
            child: FocusableActionDetector(
              enabled: true,
              onShowFocusHighlight: _handleFocus,
              onShowHoverHighlight: _handleHover,
              actions: {
                ActivateIntent: CallbackAction<ActivateIntent>(
                  onInvoke: (_) {
                    widget.onTap?.call();
                    return null;
                  },
                ),
              },
              child: MouseRegion(
                cursor: widget.onTap != null
                    ? SystemMouseCursors.click
                    : SystemMouseCursors.basic,
                onEnter: (_) => _handleHover(true),
                onExit: (_) => _handleHover(false),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (_) {
                    if (mounted) setState(() => _pressed = true);
                  },
                  onTapUp: (_) {
                    if (mounted) setState(() => _pressed = false);
                  },
                  onTapCancel: () {
                    if (mounted) setState(() => _pressed = false);
                  },
                  onTap: widget.onTap,
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

/// Consumer wrapper that connects a window ID to [DesktopTaskbarButton].
class DesktopTaskbarWindowButton extends ConsumerWidget {
  const DesktopTaskbarWindowButton({
    required this.objectId,
    required this.side,
    required this.compact,
    this.monitorId,
    super.key,
  });

  final int objectId;
  final SystemBarSide side;
  final bool compact;
  final int? monitorId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final window = ref.watch(
      shellControllerProvider.select((s) => s.windowByObjectId(objectId)),
    );

    if (window == null) {
      return const SizedBox.shrink();
    }

    final isMinimized = ref.watch(
      desktopWorkspaceProvider.select(
        (s) => s.placements[objectId]?.minimized ?? false,
      ),
    );

    final isActive = ref.watch(
      desktopWorkspaceProvider.select((s) {
        int topZ = -1;
        int? activeId;
        for (final p in s.placements.values) {
          if (!p.minimized && p.z > topZ) {
            topZ = p.z;
            activeId = p.objectId;
          }
        }
        return activeId == objectId;
      }),
    );

    final accent = ref.watch(shellAccentProvider);
    final title = localizedWindowTitle(context, window);
    final iconWidget = TaskbarWindowIcon(window: window, active: isActive);

    void onTap() {
      ref.read(desktopTaskbarPreviewProvider.notifier).hideImmediately();
      if (isActive) {
        ref.read(desktopWorkspaceProvider.notifier).minimize(objectId);
      } else {
        ref.read(desktopWorkspaceProvider.notifier).activate(objectId);
        ref.read(shellControllerProvider.notifier).focusWindow(window);
      }
    }

    final effectiveMonitorId = monitorId ?? window.monitorId;

    return DesktopTaskbarButton(
      icon: iconWidget,
      title: title,
      active: isActive,
      minimized: isMinimized,
      compact: compact,
      side: side,
      accent: accent,
      onTap: onTap,
      onHoverEnter: (bounds) {
        ref
            .read(desktopTaskbarPreviewProvider.notifier)
            .scheduleShow(
              DesktopTaskbarPreviewTarget(
                objectId: objectId,
                buttonBounds: bounds,
                side: side,
                monitorId: effectiveMonitorId,
              ),
            );
      },
      onHoverLeave: () {
        ref.read(desktopTaskbarPreviewProvider.notifier).scheduleHide();
      },
    );
  }
}

class TaskbarWindowIcon extends ConsumerWidget {
  const TaskbarWindowIcon({
    required this.window,
    required this.active,
    super.key,
  });

  final DenialWindow window;
  final bool active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (window.isLocalFlutter) {
      final localApps = ref.watch(localFlutterApplicationsProvider);
      for (final app in localApps) {
        if (app.id == window.appId || app.titleFor(context) == window.title) {
          if (app.icon != null) {
            return Icon(
              app.icon,
              size: DesktopTaskbarButtonMetrics.iconSize,
              color: active
                  ? ShellColors.textPrimary
                  : ShellColors.textSecondary,
            );
          }
          break;
        }
      }
      return const SizedBox.square(
        dimension: DesktopTaskbarButtonMetrics.iconSize,
      );
    }

    final gridState = ref.watch(homeGridControllerProvider);
    String? iconPath;
    if (gridState.hasValue) {
      final allApps = gridState.value!.desktopApps;
      for (final app in allApps) {
        if (_matchesWindowApp(app, window.appId)) {
          iconPath = app.iconPath;
          break;
        }
      }
      if (iconPath == null) {
        final slots = gridState.value!.slots.whereType<HomeGridItem>();
        for (final slot in slots) {
          final app = slot.app;
          if (app != null) {
            if (app.id == window.appId ||
                app.id == '${window.appId}.desktop' ||
                (app.startupWmClass != null &&
                    app.startupWmClass!.toLowerCase() ==
                        window.appId.toLowerCase())) {
              iconPath = app.iconPath;
              break;
            }
          }
        }
      }
    }

    return SizedBox.square(
      dimension: DesktopTaskbarButtonMetrics.iconSize,
      child: AppIconImage(iconPath: iconPath),
    );
  }
}

bool _matchesWindowApp(DesktopApp app, String appId) {
  return app.id == appId ||
      app.id == '$appId.desktop' ||
      (app.startupWmClass != null &&
          app.startupWmClass!.toLowerCase() == appId.toLowerCase());
}
