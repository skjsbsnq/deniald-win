import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/dbus_menu_node.dart';
import '../../models/tray_item.dart';
import '../../services/dbus_menu_client.dart';
import '../../state/status_notifier.dart';
import '../../theme/motion.dart';
import '../../theme/shell_theme.dart';
import '../../theme/tokens.dart';
import '../shell_surface_host.dart';

/// Shows the context menu for a [TrayItem] near [position].
///
/// If the item does not provide a DBusMenu path (`menuPath.isEmpty`), falls back
/// to calling `ContextMenu(x, y)` on the StatusNotifierItem D-Bus interface.
ShellSurfaceHandle? showTrayMenu({
  required BuildContext context,
  required WidgetRef ref,
  required TrayItem item,
  required Offset position,
  VoidCallback? onClosed,
}) {
  if (item.menuPath.isEmpty) {
    // Fallback to legacy ContextMenu method
    ref
        .read(statusNotifierProvider.notifier)
        .contextMenu(item, x: position.dx.toInt(), y: position.dy.toInt());
    return null;
  }

  final client = ref
      .read(statusNotifierProvider.notifier)
      .createMenuClient(item);
  if (client == null) return null;

  return ref
      .read(shellSurfaceControllerProvider.notifier)
      .show(
        keyName: 'tray-menu-${item.key}',
        debugLabel: 'Tray menu for ${item.displayLabel}',
        barrierColor: const Color(0x00000000),
        dismissPolicy: ShellDismissPolicy.outsideTapAndEscape,
        transitionDuration: Motion.cardSettle,
        builder: (context, handle) => TrayMenuOverlay(
          handle: handle,
          client: client,
          anchorPosition: position,
          onClosed: onClosed,
        ),
      );
}

/// Overlay managing the top-level tray menu and any active nested submenus.
class TrayMenuOverlay extends StatefulWidget {
  const TrayMenuOverlay({
    super.key,
    this.handle,
    this.onClose,
    required this.client,
    required this.anchorPosition,
    this.onClosed,
  });

  final ShellSurfaceHandle? handle;
  final VoidCallback? onClose;
  final DBusMenuClient client;
  final Offset anchorPosition;
  final VoidCallback? onClosed;

  @override
  State<TrayMenuOverlay> createState() => _TrayMenuOverlayState();
}

class _TrayMenuOverlayState extends State<TrayMenuOverlay> {
  DBusMenuNode? _rootNode;
  bool _loading = true;
  String? _error;

  /// Active submenu chain: list of opened (node, parentRect) entries.
  final List<_ActiveSubmenu> _submenus = <_ActiveSubmenu>[];
  Timer? _submenuHoverTimer;
  int _submenuRequestGeneration = 0;

  static const double _menuWidth = 210.0;
  static const double _screenMargin = 8.0;

  @override
  void initState() {
    super.initState();
    _loadMenu();
  }

  Future<void> _loadMenu() async {
    widget.client.startListening();
    widget.client.onLayoutChanged = (updatedRoot) {
      if (mounted) {
        setState(() {
          _rootNode = updatedRoot;
        });
      }
    };

    try {
      final node = await widget.client.openMenu();
      if (mounted) {
        setState(() {
          _rootNode = node;
          _loading = false;
          _error = widget.client.error;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  void _onItemClicked(DBusMenuNode item) {
    if (!item.enabled || item.isSeparator) return;

    if (item.hasSubmenu) {
      // Tapping a submenu item toggles/focuses it
      return;
    }

    unawaited(widget.client.sendClicked(item.id));
    widget.handle?.close();
    widget.onClose?.call();
  }

  void _requestOpenSubmenu(DBusMenuNode node, Rect itemGlobalRect, int depth) {
    _submenuHoverTimer?.cancel();
    final requestGeneration = ++_submenuRequestGeneration;
    _submenuHoverTimer = Timer(const Duration(milliseconds: 160), () {
      unawaited(_openSubmenu(node, itemGlobalRect, depth, requestGeneration));
    });
  }

  Future<void> _openSubmenu(
    DBusMenuNode node,
    Rect itemGlobalRect,
    int depth,
    int requestGeneration,
  ) async {
    try {
      await widget.client.openSubmenu(node.id);
    } on Object {
      return;
    }
    if (!mounted || requestGeneration != _submenuRequestGeneration) return;

    final refreshedNode = widget.client.rootNode?.findNode(node.id) ?? node;
    setState(() {
      if (_submenus.length > depth) {
        _submenus.removeRange(depth, _submenus.length);
      }
      _submenus.add(
        _ActiveSubmenu(node: refreshedNode, parentItemRect: itemGlobalRect),
      );
    });
  }

  void _requestCloseSubmenu(int depth) {
    _submenuHoverTimer?.cancel();
    ++_submenuRequestGeneration;
    _submenuHoverTimer = Timer(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      setState(() {
        if (_submenus.length > depth) {
          _submenus.removeRange(depth, _submenus.length);
        }
      });
    });
  }

  void _cancelSubmenuTimers() {
    _submenuHoverTimer?.cancel();
    ++_submenuRequestGeneration;
  }

  @override
  void dispose() {
    _submenuHoverTimer?.cancel();
    ++_submenuRequestGeneration;
    unawaited(widget.client.dispose());
    widget.onClosed?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenSize = Size(constraints.maxWidth, constraints.maxHeight);

        // Position primary menu
        final visibleItems =
            _rootNode?.children.where((c) => c.visible).toList() ?? const [];
        final estimatedHeight = math.min(
          screenSize.height - _screenMargin * 2,
          _calculateMenuHeight(visibleItems),
        );

        double left = widget.anchorPosition.dx;
        if (left + _menuWidth + _screenMargin > screenSize.width) {
          left = widget.anchorPosition.dx - _menuWidth;
        }
        left = left.clamp(
          _screenMargin,
          math.max(
            _screenMargin,
            screenSize.width - _menuWidth - _screenMargin,
          ),
        );

        double top = widget.anchorPosition.dy;
        // If anchored near bottom of the screen (taskbar), open upward
        if (top + estimatedHeight + _screenMargin > screenSize.height) {
          top = widget.anchorPosition.dy - estimatedHeight;
        }
        top = top.clamp(
          _screenMargin,
          math.max(
            _screenMargin,
            screenSize.height - estimatedHeight - _screenMargin,
          ),
        );

        final primaryRect = Rect.fromLTWH(
          left,
          top,
          _menuWidth,
          estimatedHeight,
        );

        return Stack(
          children: [
            // Primary menu card
            Positioned(
              left: left,
              top: top,
              width: _menuWidth,
              child: _MenuCard(
                isLoading: _loading,
                error: _error,
                items: visibleItems,
                depth: 0,
                onItemClicked: _onItemClicked,
                onOpenSubmenu: _requestOpenSubmenu,
                onCloseSubmenu: _requestCloseSubmenu,
                onCancelTimers: _cancelSubmenuTimers,
              ),
            ),

            // Nested submenus
            for (int i = 0; i < _submenus.length; i++)
              _buildSubmenuPositioned(
                screenSize: screenSize,
                submenu: _submenus[i],
                depth: i + 1,
                parentRect: i == 0
                    ? primaryRect
                    : _submenus[i - 1].parentItemRect,
              ),
          ],
        );
      },
    );
  }

  Widget _buildSubmenuPositioned({
    required Size screenSize,
    required _ActiveSubmenu submenu,
    required int depth,
    required Rect parentRect,
  }) {
    final items = submenu.node.children.where((c) => c.visible).toList();
    final estimatedHeight = math.min(
      screenSize.height - _screenMargin * 2,
      _calculateMenuHeight(items),
    );

    // Default: place to the right of parent rect
    double left = submenu.parentItemRect.right - 2.0;
    if (left + _menuWidth + _screenMargin > screenSize.width) {
      // Flip to the left
      left = submenu.parentItemRect.left - _menuWidth + 2.0;
    }
    left = left.clamp(
      _screenMargin,
      math.max(_screenMargin, screenSize.width - _menuWidth - _screenMargin),
    );

    double top = submenu.parentItemRect.top;
    if (top + estimatedHeight + _screenMargin > screenSize.height) {
      // Align bottom upwards
      top = math.max(
        _screenMargin,
        screenSize.height - estimatedHeight - _screenMargin,
      );
    }
    top = top.clamp(
      _screenMargin,
      math.max(
        _screenMargin,
        screenSize.height - estimatedHeight - _screenMargin,
      ),
    );

    return Positioned(
      left: left,
      top: top,
      width: _menuWidth,
      child: _MenuCard(
        isLoading: false,
        error: null,
        items: items,
        depth: depth,
        onItemClicked: _onItemClicked,
        onOpenSubmenu: _requestOpenSubmenu,
        onCloseSubmenu: _requestCloseSubmenu,
        onCancelTimers: _cancelSubmenuTimers,
      ),
    );
  }

  double _calculateMenuHeight(List<DBusMenuNode> items) {
    if (items.isEmpty) return 40.0;
    double h = 8.0; // padding top & bottom
    for (final item in items) {
      if (item.isSeparator) {
        h += 9.0;
      } else {
        h += 32.0;
      }
    }
    return h.clamp(40.0, 480.0);
  }
}

class _ActiveSubmenu {
  const _ActiveSubmenu({required this.node, required this.parentItemRect});

  final DBusMenuNode node;
  final Rect parentItemRect;
}

class _MenuCard extends StatelessWidget {
  const _MenuCard({
    required this.isLoading,
    required this.error,
    required this.items,
    required this.depth,
    required this.onItemClicked,
    required this.onOpenSubmenu,
    required this.onCloseSubmenu,
    required this.onCancelTimers,
  });

  final bool isLoading;
  final String? error;
  final List<DBusMenuNode> items;
  final int depth;
  final void Function(DBusMenuNode) onItemClicked;
  final void Function(DBusMenuNode, Rect, int) onOpenSubmenu;
  final void Function(int) onCloseSubmenu;
  final VoidCallback onCancelTimers;

  @override
  Widget build(BuildContext context) {
    final theme = ShellTheme.of(context);

    Widget content;
    if (isLoading && items.isEmpty) {
      content = const Padding(
        padding: EdgeInsets.symmetric(vertical: 14.0, horizontal: 16.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: 14.0,
              child: CircularProgressIndicator(
                strokeWidth: 2.0,
                color: ShellColors.textSecondary,
              ),
            ),
            SizedBox(width: 10.0),
            Text(
              '加载中...',
              style: TextStyle(
                color: ShellColors.textSecondary,
                fontSize: 12.0,
                fontFamilyFallback: ShellText.fallbackFontFamilies,
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ),
      );
    } else if (error != null && items.isEmpty) {
      content = Padding(
        padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
        child: Text(
          '菜单不可用',
          style: TextStyle(
            color: ShellColors.textTertiary,
            fontSize: 12.0,
            fontFamilyFallback: ShellText.fallbackFontFamilies,
            decoration: TextDecoration.none,
          ),
        ),
      );
    } else if (items.isEmpty) {
      content = Padding(
        padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
        child: Text(
          '无菜单项',
          style: TextStyle(
            color: ShellColors.textTertiary,
            fontSize: 12.0,
            fontFamilyFallback: ShellText.fallbackFontFamilies,
            decoration: TextDecoration.none,
          ),
        ),
      );
    } else {
      content = SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final item in items)
              if (item.isSeparator)
                const _TrayMenuDivider()
              else
                _TrayMenuItemWidget(
                  item: item,
                  depth: depth,
                  onClicked: () => onItemClicked(item),
                  onOpenSubmenu: (rect) => onOpenSubmenu(item, rect, depth),
                  onCloseSubmenu: () => onCloseSubmenu(depth),
                  onCancelTimers: onCancelTimers,
                ),
          ],
        ),
      );
    }

    return FocusTraversalGroup(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.panelColor(ShellColors.surfaceContainerHigh),
          borderRadius: BorderRadius.circular(8.0),
          border: Border.all(color: ShellColors.hairlineSoft),
          boxShadow: const [
            BoxShadow(
              color: ShellColors.shadow,
              blurRadius: 18.0,
              spreadRadius: 1.0,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 4.0),
          child: content,
        ),
      ),
    );
  }
}

class _TrayMenuItemWidget extends StatefulWidget {
  const _TrayMenuItemWidget({
    required this.item,
    required this.depth,
    required this.onClicked,
    required this.onOpenSubmenu,
    required this.onCloseSubmenu,
    required this.onCancelTimers,
  });

  final DBusMenuNode item;
  final int depth;
  final VoidCallback onClicked;
  final void Function(Rect globalRect) onOpenSubmenu;
  final VoidCallback onCloseSubmenu;
  final VoidCallback onCancelTimers;

  @override
  State<_TrayMenuItemWidget> createState() => _TrayMenuItemWidgetState();
}

class _TrayMenuItemWidgetState extends State<_TrayMenuItemWidget> {
  bool _hovered = false;
  bool _focused = false;

  void _handleHoverEnter() {
    setState(() => _hovered = true);
    widget.onCancelTimers();

    if (widget.item.hasSubmenu) {
      final renderBox = context.findRenderObject() as RenderBox?;
      if (renderBox != null && renderBox.hasSize) {
        final origin = renderBox.localToGlobal(Offset.zero);
        final rect = Rect.fromLTWH(
          origin.dx,
          origin.dy,
          renderBox.size.width,
          renderBox.size.height,
        );
        widget.onOpenSubmenu(rect);
      }
    } else {
      widget.onCloseSubmenu();
    }
  }

  void _handleHoverExit() {
    setState(() => _hovered = false);
  }

  Widget _buildLeadingIcon(Color iconColor, Color accentColor) {
    // 1. Checkmark
    if (widget.item.toggleType == DBusMenuToggleType.checkmark) {
      if (widget.item.toggleState == 1) {
        return Icon(
          Icons.check_rounded,
          size: 14.0,
          color: widget.item.enabled ? accentColor : ShellColors.textTertiary,
        );
      } else if (widget.item.toggleState == -1) {
        return Icon(
          Icons.remove_rounded,
          size: 14.0,
          color: widget.item.enabled ? iconColor : ShellColors.textTertiary,
        );
      }
      return const SizedBox.square(dimension: 14.0);
    }

    // 2. Radio button
    if (widget.item.toggleType == DBusMenuToggleType.radio) {
      if (widget.item.toggleState == 1) {
        return Icon(
          Icons.radio_button_checked_rounded,
          size: 13.0,
          color: widget.item.enabled ? accentColor : ShellColors.textTertiary,
        );
      } else {
        return Icon(
          Icons.radio_button_unchecked_rounded,
          size: 13.0,
          color: ShellColors.textTertiary,
        );
      }
    }

    // 3. PNG byte array icon-data
    if (widget.item.iconData != null && widget.item.iconData!.isNotEmpty) {
      return Image.memory(
        widget.item.iconData!,
        width: 16.0,
        height: 16.0,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => const SizedBox.square(dimension: 16.0),
      );
    }

    // 4. Fallback empty leading spacer
    return const SizedBox.square(dimension: 14.0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShellTheme.of(context);
    final isEnabled = widget.item.enabled;
    final highlighted = isEnabled && (_hovered || _focused);

    final textColor = isEnabled
        ? (widget.item.disposition == DBusMenuDisposition.alert ||
                  widget.item.disposition == DBusMenuDisposition.warning
              ? ShellColors.performanceWarning
              : ShellColors.textPrimary)
        : ShellColors.textTertiary;

    final iconColor = isEnabled
        ? ShellColors.textPrimary
        : ShellColors.textTertiary;
    final backgroundColor = highlighted
        ? const Color(0x1FFFFFFF)
        : const Color(0x00000000);

    return Semantics(
      button: true,
      enabled: isEnabled,
      label: widget.item.displayLabel,
      child: Focus(
        onFocusChange: (focused) => setState(() => _focused = focused),
        onKeyEvent: (node, event) {
          if (!isEnabled) return KeyEventResult.ignored;

          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.space) {
              widget.onClicked();
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: MouseRegion(
          cursor: isEnabled
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          onEnter: (_) => _handleHoverEnter(),
          onExit: (_) => _handleHoverExit(),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: isEnabled ? widget.onClicked : null,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(4.0),
              ),
              child: SizedBox(
                height: 30.0,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 18.0,
                        child: Center(
                          child: _buildLeadingIcon(iconColor, theme.accent),
                        ),
                      ),
                      const SizedBox(width: 8.0),
                      Expanded(
                        child: Text(
                          widget.item.displayLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: textColor,
                            fontSize: 12.0,
                            fontWeight: FontWeight.w400,
                            fontFamilyFallback: ShellText.fallbackFontFamilies,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                      if (widget.item.hasSubmenu) ...[
                        const SizedBox(width: 6.0),
                        const Icon(
                          Icons.chevron_right_rounded,
                          size: 14.0,
                          color: ShellColors.textTertiary,
                        ),
                      ] else if (widget.item.formattedShortcut != null) ...[
                        const SizedBox(width: 8.0),
                        Text(
                          widget.item.formattedShortcut!,
                          style: const TextStyle(
                            color: ShellColors.textTertiary,
                            fontSize: 10.0,
                            fontFamilyFallback: ShellText.fallbackFontFamilies,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ],
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

class _TrayMenuDivider extends StatelessWidget {
  const _TrayMenuDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 6.0, vertical: 4.0),
      child: SizedBox(
        height: 1.0,
        child: ColoredBox(color: ShellColors.hairlineSoft),
      ),
    );
  }
}
