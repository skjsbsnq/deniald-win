import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' show Icons, Tooltip;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../input/shell_interaction_registry.dart';
import '../../localization/denial_localizations.dart';
import '../../models/display_layout.dart';
import '../../models/tray_item.dart';
import '../../state/status_notifier.dart';
import '../../theme/motion.dart';
import '../../theme/shell_theme.dart';
import '../../theme/tokens.dart';
import '../../wallpaper/state/wallpaper_accent.dart';
import '../shell_backdrop_blur.dart';
import '../shell_cursor.dart';
import '../shell_surface_host.dart';
import 'tray_icon.dart';
import 'tray_menu.dart';

/// The status notifier tray area for the desktop system bar.
///
/// Follows Windows 11 system tray UX:
/// - Active and attention-seeking items are placed directly on the system bar.
/// - Passive items are folded into an expandable overflow area triggered by a chevron button.
/// - Items seeking urgent attention ([TrayItemStatus.needsAttention]) are unconditionally
///   promoted to the primary tray bar.
/// - Full interaction pipeline: Left-click (Activate or DBusMenu when [TrayItem.itemIsMenu]),
///   Right-click (DBusMenu or ContextMenu fallback), Middle-click (SecondaryActivate),
///   and Wheel scroll (Scroll D-Bus call with bubbling suppression).
/// - Completely zero-sized and absent from layout when no tray items exist.
class TrayArea extends ConsumerStatefulWidget {
  const TrayArea({
    super.key,
    this.side = SystemBarSide.bottom,
    this.horizontal = true,
    this.color,
  });

  final SystemBarSide side;
  final bool horizontal;
  final Color? color;

  static const double itemGap = 3.0;
  static const double iconButtonSize = 28.0;

  @override
  ConsumerState<TrayArea> createState() => _TrayAreaState();
}

class _TrayAreaState extends ConsumerState<TrayArea> {
  @override
  Widget build(BuildContext context) {
    final trayState = ref.watch(statusNotifierProvider);
    final allItems = trayState.items;

    if (allItems.isEmpty) {
      return const SizedBox.shrink();
    }

    final activeItems = <TrayItem>[];
    final passiveItems = <TrayItem>[];

    for (final item in allItems) {
      if (item.status == TrayItemStatus.needsAttention ||
          item.status == TrayItemStatus.active) {
        activeItems.add(item);
      } else {
        passiveItems.add(item);
      }
    }

    if (activeItems.isEmpty && passiveItems.isEmpty) {
      return const SizedBox.shrink();
    }

    final children = <Widget>[];

    // Win11 overflow chevron button (shown when there are passive items)
    if (passiveItems.isNotEmpty) {
      children.add(
        _TrayOverflowButton(
          side: widget.side,
          horizontal: widget.horizontal,
          passiveItems: passiveItems,
          color: widget.color,
        ),
      );
    }

    // Active & urgent tray icons
    for (int i = 0; i < activeItems.length; i++) {
      final item = activeItems[i];
      if (children.isNotEmpty) {
        children.add(
          SizedBox(
            width: widget.horizontal ? TrayArea.itemGap : null,
            height: widget.horizontal ? null : TrayArea.itemGap,
          ),
        );
      }
      children.add(
        TrayItemButton(
          key: ValueKey('tray-item-${item.key}'),
          item: item,
          side: widget.side,
        ),
      );
    }

    return ShellInputRegion(
      debugLabel: 'Desktop tray area',
      child: Flex(
        direction: widget.horizontal ? Axis.horizontal : Axis.vertical,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: children,
      ),
    );
  }
}

/// An individual interactive tray icon button handling Left, Right, Middle,
/// and Wheel scroll actions according to the StatusNotifierItem specification.
class TrayItemButton extends ConsumerStatefulWidget {
  const TrayItemButton({
    super.key,
    required this.item,
    this.side = SystemBarSide.bottom,
    this.size = TrayArea.iconButtonSize,
  });

  final TrayItem item;
  final SystemBarSide side;
  final double size;

  @override
  ConsumerState<TrayItemButton> createState() => _TrayItemButtonState();
}

class _TrayItemButtonState extends ConsumerState<TrayItemButton> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  void _handlePrimaryTap(Offset globalPos) {
    if (widget.item.itemIsMenu) {
      _showContextMenu(globalPos);
    } else {
      ref
          .read(statusNotifierProvider.notifier)
          .activate(
            widget.item,
            x: globalPos.dx.toInt(),
            y: globalPos.dy.toInt(),
          );
    }
  }

  void _handleSecondaryTap(Offset globalPos) {
    _showContextMenu(globalPos);
  }

  void _handleTertiaryTap(Offset globalPos) {
    ref
        .read(statusNotifierProvider.notifier)
        .secondaryActivate(
          widget.item,
          x: globalPos.dx.toInt(),
          y: globalPos.dy.toInt(),
        );
  }

  void _handleScroll(PointerScrollEvent event) {
    final rawDelta = event.scrollDelta.dy != 0
        ? -event.scrollDelta.dy
        : -event.scrollDelta.dx;
    final delta = rawDelta.clamp(-120.0, 120.0).round();
    if (delta != 0) {
      ref
          .read(statusNotifierProvider.notifier)
          .scroll(widget.item, delta, 'vertical');
    }
  }

  void _showContextMenu(Offset globalPos) {
    showTrayMenu(
      context: context,
      ref: ref,
      item: widget.item,
      position: globalPos,
    );
  }

  Offset _getGlobalPosition() {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox != null && renderBox.hasSize) {
      return renderBox.localToGlobal(Offset.zero);
    }
    return Offset.zero;
  }

  String _buildTooltipMessage() {
    final title = widget.item.sanitizedToolTipTitle;
    final desc = widget.item.sanitizedToolTipDescription;
    if (title.isNotEmpty && desc.isNotEmpty) {
      return '$title\n$desc';
    }
    if (desc.isNotEmpty) return desc;
    if (title.isNotEmpty) return title;
    return widget.item.displayLabel;
  }

  @override
  Widget build(BuildContext context) {
    final accent = ref.watch(shellAccentProvider);
    final item = widget.item;
    final isAttention = item.status == TrayItemStatus.needsAttention;

    final semanticLabel = isAttention
        ? context.l10n.trayItemNeedsAttention(item.displayLabel)
        : context.l10n.trayItemSemanticLabel(item.displayLabel);

    Color backgroundColor;
    if (_pressed) {
      backgroundColor = accent.color.withValues(alpha: 0.28);
    } else if (_hovered) {
      backgroundColor = accent.color.withValues(alpha: 0.14);
    } else if (_focused) {
      backgroundColor = accent.color.withValues(alpha: 0.08);
    } else {
      backgroundColor = const Color(0x00000000);
    }

    final tooltipText = _buildTooltipMessage();

    Widget buttonContent = SizedBox.square(
      dimension: widget.size,
      child: Center(
        child: TrayIcon(item: item, size: 19.0, showTooltip: false),
      ),
    );

    return Semantics(
      button: true,
      label: semanticLabel,
      child: Focus(
        onFocusChange: (focused) => setState(() => _focused = focused),
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.space) {
              _handlePrimaryTap(_getGlobalPosition());
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: MouseRegion(
          cursor: ShellMouseCursors.link,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() {
            _hovered = false;
            _pressed = false;
          }),
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerSignal: (signal) {
              if (signal is PointerScrollEvent) {
                _handleScroll(signal);
                // Swallow signal so the parent system bar does not scroll
                GestureBinding.instance.pointerSignalResolver.register(
                  signal,
                  (_) {},
                );
              }
            },
            onPointerDown: (event) {
              if (event.buttons == kMiddleMouseButton) {
                _handleTertiaryTap(event.position);
              }
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (_) => setState(() => _pressed = true),
              onTapUp: (_) => setState(() => _pressed = false),
              onTapCancel: () => setState(() => _pressed = false),
              onTap: () => _handlePrimaryTap(_getGlobalPosition()),
              onSecondaryTapDown: (details) =>
                  _handleSecondaryTap(details.globalPosition),
              child: AnimatedContainer(
                duration: Motion.tile,
                curve: Curves.easeOut,
                decoration: BoxDecoration(
                  color: backgroundColor,
                  borderRadius: BorderRadius.circular(6.0),
                  border: _focused
                      ? Border.all(
                          color: accent.color.withValues(alpha: 0.70),
                          width: 1.5,
                        )
                      : Border.all(color: const Color(0x00000000), width: 1.5),
                ),
                child: Tooltip(
                  message: tooltipText,
                  waitDuration: const Duration(milliseconds: 350),
                  decoration: BoxDecoration(
                    color: ShellColors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6.0),
                    border: Border.all(color: ShellColors.hairlineSoft),
                    boxShadow: const [
                      BoxShadow(
                        color: ShellColors.shadow,
                        blurRadius: 8.0,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  textStyle: const TextStyle(
                    color: ShellColors.textPrimary,
                    fontSize: 12.0,
                    height: 1.35,
                    fontFamilyFallback: ShellText.fallbackFontFamilies,
                    decoration: TextDecoration.none,
                  ),
                  child: buttonContent,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The Win11-style chevron toggle button (`∧`) that reveals the hidden tray overflow card.
class _TrayOverflowButton extends ConsumerStatefulWidget {
  const _TrayOverflowButton({
    required this.side,
    required this.horizontal,
    required this.passiveItems,
    this.color,
  });

  final SystemBarSide side;
  final bool horizontal;
  final List<TrayItem> passiveItems;
  final Color? color;

  @override
  ConsumerState<_TrayOverflowButton> createState() =>
      _TrayOverflowButtonState();
}

class _TrayOverflowButtonState extends ConsumerState<_TrayOverflowButton> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  void _toggleOverflow() {
    final surfaces = ref.read(shellSurfaceControllerProvider);
    final existing = surfaces.cast<ManagedShellSurface?>().firstWhere(
      (s) => s?.keyName == 'tray-overflow-panel' && !s!.closing,
      orElse: () => null,
    );

    if (existing != null) {
      ref.read(shellSurfaceControllerProvider.notifier).close(existing.id);
      return;
    }

    final renderBox = context.findRenderObject() as RenderBox?;
    final anchor = renderBox != null && renderBox.hasSize
        ? renderBox.localToGlobal(Offset.zero) & renderBox.size
        : Rect.zero;

    ref
        .read(shellSurfaceControllerProvider.notifier)
        .show(
          keyName: 'tray-overflow-panel',
          debugLabel: 'Tray overflow panel',
          barrierColor: const Color(0x00000000),
          dismissPolicy: ShellDismissPolicy.outsideTapAndEscape,
          transitionDuration: Motion.cardSettle,
          builder: (context, handle) => TrayOverflowPanel(
            handle: handle,
            anchorRect: anchor,
            side: widget.side,
          ),
        );
  }

  IconData _resolveChevronIcon(bool isOpen) {
    switch (widget.side) {
      case SystemBarSide.bottom:
        return isOpen
            ? Icons.keyboard_arrow_down_rounded
            : Icons.keyboard_arrow_up_rounded;
      case SystemBarSide.top:
        return isOpen
            ? Icons.keyboard_arrow_up_rounded
            : Icons.keyboard_arrow_down_rounded;
      case SystemBarSide.left:
        return isOpen
            ? Icons.keyboard_arrow_left_rounded
            : Icons.keyboard_arrow_right_rounded;
      case SystemBarSide.right:
      case SystemBarSide.hidden:
        return isOpen
            ? Icons.keyboard_arrow_right_rounded
            : Icons.keyboard_arrow_left_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = ref.watch(shellAccentProvider);
    final foreground = widget.color ?? ShellColors.textPrimary;
    final isOpen = ref
        .watch(shellSurfaceControllerProvider)
        .any((s) => s.keyName == 'tray-overflow-panel' && !s.closing);

    final tooltipMsg = isOpen
        ? context.l10n.trayOverflowCollapse
        : context.l10n.trayOverflowExpand;

    Color pillColor;
    if (_pressed) {
      pillColor = accent.color.withValues(alpha: 0.28);
    } else if (isOpen) {
      pillColor = accent.color.withValues(alpha: 0.20);
    } else if (_hovered) {
      pillColor = accent.color.withValues(alpha: 0.12);
    } else if (_focused) {
      pillColor = accent.color.withValues(alpha: 0.08);
    } else {
      pillColor = const Color(0x00000000);
    }

    return Semantics(
      button: true,
      label: tooltipMsg,
      child: Focus(
        onFocusChange: (focused) => setState(() => _focused = focused),
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.space) {
              _toggleOverflow();
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: MouseRegion(
          cursor: ShellMouseCursors.link,
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
            onTap: _toggleOverflow,
            child: AnimatedContainer(
              duration: Motion.tile,
              curve: Curves.easeOut,
              width: TrayArea.iconButtonSize,
              height: TrayArea.iconButtonSize,
              decoration: BoxDecoration(
                color: pillColor,
                borderRadius: BorderRadius.circular(6.0),
                border: _focused
                    ? Border.all(
                        color: accent.color.withValues(alpha: 0.65),
                        width: 1.5,
                      )
                    : Border.all(color: const Color(0x00000000), width: 1.5),
              ),
              child: Tooltip(
                message: tooltipMsg,
                waitDuration: const Duration(milliseconds: 400),
                child: Center(
                  child: Icon(
                    _resolveChevronIcon(isOpen),
                    size: 18.0,
                    color: foreground,
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

/// Floating frosted panel hosting folded passive tray items in an adaptive grid.
class TrayOverflowPanel extends ConsumerWidget {
  const TrayOverflowPanel({
    super.key,
    required this.handle,
    required this.anchorRect,
    required this.side,
  });

  final ShellSurfaceHandle handle;
  final Rect anchorRect;
  final SystemBarSide side;

  static const double _cardPadding = 8.0;
  static const double _panelGap = 8.0;
  static const double _itemSpacing = 4.0;
  static const int _maxColumns = 4;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trayState = ref.watch(statusNotifierProvider);
    final passiveItems = trayState.passiveItems;

    if (passiveItems.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        handle.close();
      });
      return const SizedBox.shrink();
    }

    final accent = ref.watch(shellAccentProvider);
    final theme = ShellTheme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final screenSize = Size(constraints.maxWidth, constraints.maxHeight);

        final itemCount = passiveItems.length;
        final columns = itemCount <= _maxColumns
            ? math.max(1, itemCount)
            : _maxColumns;
        final rows = (itemCount / columns).ceil();

        final contentWidth =
            columns * TrayArea.iconButtonSize +
            (columns - 1) * _itemSpacing +
            _cardPadding * 2;
        final contentHeight =
            rows * TrayArea.iconButtonSize +
            (rows - 1) * _itemSpacing +
            _cardPadding * 2;

        double left;
        double top;

        switch (side) {
          case SystemBarSide.bottom:
            left = anchorRect.center.dx - contentWidth / 2;
            top = anchorRect.top - contentHeight - _panelGap;
            break;
          case SystemBarSide.top:
            left = anchorRect.center.dx - contentWidth / 2;
            top = anchorRect.bottom + _panelGap;
            break;
          case SystemBarSide.left:
            left = anchorRect.right + _panelGap;
            top = anchorRect.center.dy - contentHeight / 2;
            break;
          case SystemBarSide.right:
          case SystemBarSide.hidden:
            left = anchorRect.left - contentWidth - _panelGap;
            top = anchorRect.center.dy - contentHeight / 2;
            break;
        }

        left = left.clamp(
          8.0,
          math.max(8.0, screenSize.width - contentWidth - 8.0),
        );
        top = top.clamp(
          8.0,
          math.max(8.0, screenSize.height - contentHeight - 8.0),
        );

        const radius = BorderRadius.all(Radius.circular(12.0));

        return Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              width: contentWidth,
              height: contentHeight,
              child: ShellInputRegion(
                debugLabel: 'Tray overflow popup',
                child: FocusTraversalGroup(
                  child: ShellBackdropBlur(
                    borderRadius: radius,
                    child: Container(
                      padding: const EdgeInsets.all(_cardPadding),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            theme.panelColor(
                              Color.alphaBlend(
                                accent.color.withValues(alpha: 0.12),
                                ShellColors.panelBackground.withValues(
                                  alpha: 1,
                                ),
                              ),
                            ),
                            theme.panelColor(ShellColors.surfaceContainerLow),
                          ],
                        ),
                        borderRadius: radius,
                        border: Border.all(
                          color: accent.color.withValues(alpha: 0.35),
                          width: 1.0,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: ShellColors.shadow,
                            blurRadius: 24.0,
                            spreadRadius: 1.0,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Wrap(
                        spacing: _itemSpacing,
                        runSpacing: _itemSpacing,
                        children: [
                          for (final item in passiveItems)
                            TrayItemButton(
                              key: ValueKey('passive-tray-item-${item.key}'),
                              item: item,
                              side: side,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
