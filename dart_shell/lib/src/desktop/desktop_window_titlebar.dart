import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../launcher/controllers/home_grid_controller.dart';
import '../launcher/models/desktop_app.dart';
import '../launcher/models/home_grid_item.dart';
import '../local_apps/local_flutter_application.dart';
import '../localization/denial_localizations.dart';
import '../models/denial_window.dart';
import '../theme/shell_theme.dart';
import '../theme/tokens.dart';
import '../wallpaper/state/wallpaper_accent.dart';
import '../widgets/app_icon.dart';
import 'desktop_window_menu.dart';
import 'desktop_workspace.dart';

/// Metrics for the window titlebar.
///
/// Along with [DesktopMetrics.frameBorder], this determines the top inset of
/// [DesktopWindowPlacement.contentRect].
abstract final class DesktopTitlebarMetrics {
  static const double height = 34.0;
  static const double iconSize = 16.0;
  static const double horizontalPadding = 12.0;
  static const double iconGap = 8.0;
  static const double buttonWidth = 46.0;
  static const double glyphSize = 10.0;
  static const Duration buttonAnimationDuration = Duration(milliseconds: 100);
}

/// The header strip rendered above decorated server-side window surfaces.
///
/// In T05, this provides full window management interactions and Win11-aligned
/// visuals:
/// - Follows wallpaper accent theme on active titlebar.
/// - Inactive state dims title text, icon, and titlebar fill.
/// - Three standard control buttons (minimize, maximize/restore, close) with
///   isolated hover/pressed transitions and custom fine-line glyphs.
/// - Close button turns red on hover/press with white glyph.
/// - Right-side corner radius smoothly clips with the window frame.
class DesktopWindowTitlebar extends ConsumerWidget {
  const DesktopWindowTitlebar({
    super.key,
    required this.window,
    required this.active,
    required this.maximized,
    this.fullscreen = false,
    this.overviewActive = false,
    required this.onActivate,
    required this.onBeginMove,
    required this.onMoveBy,
    required this.onEndMove,
    required this.onBeginMaximizedDrag,
    required this.onMinimize,
    required this.onToggleMaximize,
    required this.onClose,
  });

  final DenialWindow window;
  final bool active;
  final bool maximized;
  final bool fullscreen;
  final bool overviewActive;
  final VoidCallback onActivate;
  final VoidCallback onBeginMove;
  final ValueChanged<Offset> onMoveBy;
  final VoidCallback onEndMove;
  final void Function({
    required Offset pointerPosition,
    required double pointerFractionX,
    required double pointerOffsetY,
  })
  onBeginMaximizedDrag;
  final VoidCallback onMinimize;
  final VoidCallback onToggleMaximize;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ShellTheme.of(context);
    final accent = ref.watch(shellAccentProvider);
    final topRadius = math.max(
      0.0,
      theme.windowRadius - DesktopMetrics.frameBorder,
    );

    final backgroundColor = active
        ? accent.cardFill
        : ShellColors.surfaceContainerLow;

    // Deliberately not wrapped in a ShellInputRegion. That widget measures
    // itself from RenderObject.paint(), and moving a window only re-offsets
    // the window's cached repaint-boundary layer without repainting its
    // subtree, so the published rectangle would stay at the window's previous
    // position — a phantom shell-owned band that swallows clicks meant for
    // whatever now sits there. The titlebar's hit region is published from the
    // placement geometry instead (see desktop_input_layout_publisher.dart),
    // which is authoritative and refreshed on every move.
    return ClipRRect(
      borderRadius: BorderRadius.only(
        topLeft: Radius.circular(topRadius),
        topRight: Radius.circular(topRadius),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(color: backgroundColor),
        child: Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: _DesktopWindowTitlebarInteractiveArea(
                      window: window,
                      active: active,
                      maximized: maximized,
                      fullscreen: fullscreen,
                      overviewActive: overviewActive,
                      onActivate: onActivate,
                      onBeginMove: onBeginMove,
                      onMoveBy: onMoveBy,
                      onEndMove: onEndMove,
                      onBeginMaximizedDrag: onBeginMaximizedDrag,
                      onMinimize: onMinimize,
                      onToggleMaximize: onToggleMaximize,
                      onClose: onClose,
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _TitlebarButton.minimize(
                        active: active,
                        onPressed: onMinimize,
                      ),
                      _TitlebarButton.maximize(
                        active: active,
                        maximized: maximized,
                        onPressed: onToggleMaximize,
                      ),
                      _TitlebarButton.close(
                        active: active,
                        topRadius: topRadius,
                        onPressed: onClose,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopWindowTitlebarInteractiveArea extends ConsumerStatefulWidget {
  const _DesktopWindowTitlebarInteractiveArea({
    required this.window,
    required this.active,
    required this.maximized,
    required this.fullscreen,
    required this.overviewActive,
    required this.onActivate,
    required this.onBeginMove,
    required this.onMoveBy,
    required this.onEndMove,
    required this.onBeginMaximizedDrag,
    required this.onMinimize,
    required this.onToggleMaximize,
    required this.onClose,
  });

  final DenialWindow window;
  final bool active;
  final bool maximized;
  final bool fullscreen;
  final bool overviewActive;
  final VoidCallback onActivate;
  final VoidCallback onBeginMove;
  final ValueChanged<Offset> onMoveBy;
  final VoidCallback onEndMove;
  final void Function({
    required Offset pointerPosition,
    required double pointerFractionX,
    required double pointerOffsetY,
  })
  onBeginMaximizedDrag;
  final VoidCallback onMinimize;
  final VoidCallback onToggleMaximize;
  final VoidCallback onClose;

  @override
  ConsumerState<_DesktopWindowTitlebarInteractiveArea> createState() =>
      _DesktopWindowTitlebarInteractiveAreaState();
}

class _DesktopWindowTitlebarInteractiveAreaState
    extends ConsumerState<_DesktopWindowTitlebarInteractiveArea> {
  Offset? _startPointerPosition;
  Offset? _startLocalPosition;
  bool _dragInitiated = false;
  bool _isDragging = false;

  void _handlePointerDown(PointerDownEvent event) {
    if (event.buttons == kPrimaryMouseButton ||
        event.kind == PointerDeviceKind.touch) {
      _startPointerPosition = event.position;
      _startLocalPosition = event.localPosition;
      _dragInitiated = false;
      _isDragging = false;
      widget.onActivate();
    }
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (_startPointerPosition == null) {
      return;
    }
    if (!_dragInitiated) {
      final distance = (event.position - _startPointerPosition!).distance;
      if (distance >= 3.0) {
        _dragInitiated = true;
        _isDragging = true;
        if (widget.maximized) {
          final box = context.findRenderObject() as RenderBox?;
          final interactiveWidth = box?.size.width ?? 1000.0;
          final fullTitlebarWidth =
              interactiveWidth + (DesktopTitlebarMetrics.buttonWidth * 3);
          final localX = _startLocalPosition?.dx ?? (fullTitlebarWidth / 2);
          final fractionX = (localX / fullTitlebarWidth).clamp(0.05, 0.95);
          final localY =
              _startLocalPosition?.dy ?? (DesktopTitlebarMetrics.height / 2);
          final offsetY = localY.clamp(0.0, DesktopTitlebarMetrics.height);
          widget.onBeginMaximizedDrag(
            pointerPosition: event.position,
            pointerFractionX: fractionX,
            pointerOffsetY: offsetY,
          );
        } else {
          widget.onBeginMove();
          widget.onMoveBy(event.position - _startPointerPosition!);
        }
      }
    } else {
      widget.onMoveBy(event.delta);
    }
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (_isDragging) {
      widget.onEndMove();
    }
    _dragInitiated = false;
    _isDragging = false;
    _startPointerPosition = null;
    _startLocalPosition = null;
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (_isDragging) {
      widget.onEndMove();
    }
    _dragInitiated = false;
    _isDragging = false;
    _startPointerPosition = null;
    _startLocalPosition = null;
  }

  void _openContextMenu(Offset globalPosition) {
    showDesktopWindowMenu(
      context: context,
      ref: ref,
      window: widget.window,
      position: globalPosition,
      maximized: widget.maximized,
      fullscreen: widget.fullscreen,
      overviewActive: widget.overviewActive,
      onMinimize: widget.onMinimize,
      onToggleMaximize: widget.onToggleMaximize,
      onClose: widget.onClose,
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = localizedWindowTitle(context, widget.window);
    final accent = ref.watch(shellAccentProvider);
    final titleColor = widget.active
        ? ShellColors.textPrimary
        : ShellColors.textTertiary;

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerCancel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: widget.onToggleMaximize,
        onSecondaryTapUp: (details) => _openContextMenu(details.globalPosition),
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(
                  left: DesktopTitlebarMetrics.horizontalPadding,
                  right: DesktopTitlebarMetrics.iconGap,
                ),
                child: Row(
                  children: [
                    _DesktopWindowTitlebarIcon(
                      window: widget.window,
                      active: widget.active,
                    ),
                    const SizedBox(width: DesktopTitlebarMetrics.iconGap),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: titleColor,
                          fontSize: 12.0,
                          fontWeight: widget.active
                              ? FontWeight.w600
                              : FontWeight.w500,
                          fontFamilyFallback: ShellText.fallbackFontFamilies,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(
              height: DesktopMetrics.frameBorder,
              child: ColoredBox(
                color: widget.active
                    ? accent.color.withValues(alpha: 0.18)
                    : ShellColors.hairlineSoft,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum TitlebarButtonType { minimize, maximize, close }

class _TitlebarButton extends StatefulWidget {
  const _TitlebarButton.minimize({
    required this.active,
    required this.onPressed,
  }) : type = TitlebarButtonType.minimize,
       maximized = false,
       topRadius = 0.0;

  const _TitlebarButton.maximize({
    required this.active,
    required this.maximized,
    required this.onPressed,
  }) : type = TitlebarButtonType.maximize,
       topRadius = 0.0;

  const _TitlebarButton.close({
    required this.active,
    required this.topRadius,
    required this.onPressed,
  }) : type = TitlebarButtonType.close,
       maximized = false;

  final TitlebarButtonType type;
  final bool active;
  final bool maximized;
  final double topRadius;
  final VoidCallback onPressed;

  @override
  State<_TitlebarButton> createState() => _TitlebarButtonState();
}

class _TitlebarButtonState extends State<_TitlebarButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final isClose = widget.type == TitlebarButtonType.close;

    Color backgroundColor;
    Color iconColor;

    if (isClose) {
      if (_pressed) {
        backgroundColor = ShellColors.windowClosePressed;
        iconColor = ShellColors.windowCloseForeground;
      } else if (_hovered) {
        backgroundColor = ShellColors.windowCloseHover;
        iconColor = ShellColors.windowCloseForeground;
      } else {
        backgroundColor = const Color(0x00000000);
        iconColor = widget.active
            ? ShellColors.textPrimary
            : ShellColors.textTertiary;
      }
    } else {
      if (_pressed) {
        backgroundColor = ShellColors.windowButtonPressed;
        iconColor = ShellColors.textPrimary;
      } else if (_hovered) {
        backgroundColor = ShellColors.windowButtonHover;
        iconColor = ShellColors.textPrimary;
      } else {
        backgroundColor = const Color(0x00000000);
        iconColor = widget.active
            ? ShellColors.textPrimary
            : ShellColors.textTertiary;
      }
    }

    final semanticLabel = switch (widget.type) {
      TitlebarButtonType.minimize => context.l10n.windowMinimize,
      TitlebarButtonType.maximize =>
        widget.maximized
            ? context.l10n.windowRestore
            : context.l10n.windowMaximize,
      TitlebarButtonType.close => context.l10n.windowClose,
    };

    final borderRadius = isClose && widget.topRadius > 0
        ? BorderRadius.only(topRight: Radius.circular(widget.topRadius))
        : BorderRadius.zero;

    return RepaintBoundary(
      child: Semantics(
        button: true,
        label: semanticLabel,
        child: MouseRegion(
          cursor: SystemMouseCursors.basic,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() {
            _hovered = false;
            _pressed = false;
          }),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) => setState(() => _pressed = true),
            onTapUp: (_) => setState(() => _pressed = false),
            onTapCancel: () => setState(() => _pressed = false),
            onTap: widget.onPressed,
            child: AnimatedContainer(
              duration: DesktopTitlebarMetrics.buttonAnimationDuration,
              curve: Curves.easeOut,
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: borderRadius,
              ),
              child: SizedBox(
                width: DesktopTitlebarMetrics.buttonWidth,
                height: double.infinity,
                child: Center(
                  child: CustomPaint(
                    size: const Size(
                      DesktopTitlebarMetrics.glyphSize,
                      DesktopTitlebarMetrics.glyphSize,
                    ),
                    painter: TitlebarGlyphPainter(
                      type: widget.type,
                      maximized: widget.maximized,
                      color: iconColor,
                    ),
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

class TitlebarGlyphPainter extends CustomPainter {
  const TitlebarGlyphPainter({
    required this.type,
    required this.maximized,
    required this.color,
  });

  final TitlebarButtonType type;
  final bool maximized;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.square
      ..strokeJoin = StrokeJoin.miter;

    switch (type) {
      case TitlebarButtonType.minimize:
        canvas.drawLine(const Offset(0.0, 5.5), const Offset(10.0, 5.5), paint);
      case TitlebarButtonType.maximize:
        if (maximized) {
          final backPath = Path()
            ..moveTo(2.5, 2.5)
            ..lineTo(2.5, 0.5)
            ..lineTo(9.5, 0.5)
            ..lineTo(9.5, 7.5)
            ..lineTo(7.5, 7.5);
          canvas.drawPath(backPath, paint);
          canvas.drawRect(const Rect.fromLTWH(0.5, 2.5, 7.0, 7.0), paint);
        } else {
          canvas.drawRect(const Rect.fromLTWH(0.5, 0.5, 9.0, 9.0), paint);
        }
      case TitlebarButtonType.close:
        canvas.drawLine(const Offset(0.5, 0.5), const Offset(9.5, 9.5), paint);
        canvas.drawLine(const Offset(9.5, 0.5), const Offset(0.5, 9.5), paint);
    }
  }

  @override
  bool shouldRepaint(covariant TitlebarGlyphPainter oldDelegate) {
    return oldDelegate.type != type ||
        oldDelegate.maximized != maximized ||
        oldDelegate.color != color;
  }
}

class _DesktopWindowTitlebarIcon extends ConsumerWidget {
  const _DesktopWindowTitlebarIcon({
    required this.window,
    required this.active,
  });

  final DenialWindow window;
  final bool active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget iconWidget;
    if (window.isLocalFlutter) {
      final localApps = ref.watch(localFlutterApplicationsProvider);
      Widget? localAppIcon;
      for (final app in localApps) {
        if (app.id == window.appId || app.titleFor(context) == window.title) {
          if (app.icon != null) {
            localAppIcon = Icon(
              app.icon,
              size: DesktopTitlebarMetrics.iconSize,
              color: active
                  ? ShellColors.textPrimary
                  : ShellColors.textTertiary,
            );
          }
          break;
        }
      }
      if (localAppIcon != null) {
        iconWidget = localAppIcon;
      } else {
        iconWidget = const SizedBox.square(
          dimension: DesktopTitlebarMetrics.iconSize,
        );
      }
    } else {
      final gridState = ref.watch(homeGridControllerProvider);
      String? iconPath;
      if (gridState.hasValue) {
        for (final app in gridState.value!.desktopApps) {
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

      iconWidget = SizedBox.square(
        dimension: DesktopTitlebarMetrics.iconSize,
        child: AppIconImage(iconPath: iconPath),
      );
    }

    if (!active) {
      return Opacity(opacity: 0.65, child: iconWidget);
    }
    return iconWidget;
  }
}

bool _matchesWindowApp(DesktopApp app, String appId) {
  return app.id == appId ||
      app.id == '$appId.desktop' ||
      (app.startupWmClass != null &&
          app.startupWmClass!.toLowerCase() == appId.toLowerCase());
}
