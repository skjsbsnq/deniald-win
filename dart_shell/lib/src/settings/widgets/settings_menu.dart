import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/shell_popup_placement.dart';
import '../../theme/shell_theme.dart';
import '../../theme/tokens.dart';
import 'settings_buttons.dart';

/// A single selectable entry in a [SettingsMenu].
@immutable
class SettingsMenuItem<T> {
  const SettingsMenuItem(this.value, this.label);

  final T value;
  final String label;
}

class _OpenSettingsMenuIntent extends Intent {
  const _OpenSettingsMenuIntent();
}

/// M3E menu used in place of `DropdownButton` (`02-VISUAL-SPEC.md` §3.9).
///
/// The trigger is a `filledTonal` S button showing the current value plus a
/// drop-down glyph. The popup is a `surfaceContainer` panel with a 4dp radius
/// and no shadow (Denial uses outline/blur instead of elevation), entries at
/// least 64×48, and the selected entry filled with `accentPalette.container`.
///
/// Placement reuses [ShellPopupAnchor] so the panel opens below, above or
/// beside the trigger without a fixed dropdown geometry.
class SettingsMenu<T> extends StatefulWidget {
  const SettingsMenu({
    required this.semanticsLabel,
    required this.value,
    required this.items,
    required this.onChanged,
    this.enabled = true,
    this.anchor = ShellPopupAnchor.bottomLeft,
    super.key,
  });

  final String semanticsLabel;
  final T value;
  final List<SettingsMenuItem<T>> items;
  final ValueChanged<T> onChanged;
  final bool enabled;
  final ShellPopupAnchor anchor;

  @override
  State<SettingsMenu<T>> createState() => _SettingsMenuState<T>();
}

class _SettingsMenuState<T> extends State<SettingsMenu<T>> {
  final _layerLink = LayerLink();
  final _triggerKey = GlobalKey();
  final _triggerFocusNode = FocusNode();
  final _panelFocusNode = FocusNode();
  OverlayEntry? _entry;
  var _expanded = false;
  var _highlighted = 0;

  SettingsMenuItem<T> get _selected => widget.items.firstWhere(
    (item) => item.value == widget.value,
    orElse: () => SettingsMenuItem<T>(widget.value, widget.value.toString()),
  );

  @override
  void didUpdateWidget(covariant SettingsMenu<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && _expanded) {
      _close(returnFocus: false);
      return;
    }
    if (_expanded) {
      _entry?.markNeedsBuild();
    }
  }

  @override
  void dispose() {
    _entry?.remove();
    _entry = null;
    _triggerFocusNode.dispose();
    _panelFocusNode.dispose();
    super.dispose();
  }

  void _toggle() {
    if (!widget.enabled) {
      return;
    }
    if (_expanded) {
      _close();
    } else {
      _open();
    }
  }

  void _open() {
    if (_expanded) {
      return;
    }
    final target = _triggerKey.currentContext?.findRenderObject();
    final overlay = Overlay.of(context);
    final overlayBox = overlay.context.findRenderObject();
    if (target is! RenderBox || overlayBox is! RenderBox) {
      return;
    }
    final targetOffset = target.localToGlobal(
      Offset.zero,
      ancestor: overlayBox,
    );
    final targetSize = target.size;
    final desiredHeight = widget.items.length * _itemHeight + 8;
    final below = overlayBox.size.height - targetOffset.dy - targetSize.height;
    final above = targetOffset.dy;
    var showAbove = widget.anchor.vertical < 0;
    if (showAbove) {
      if (above < desiredHeight + 6 && below > above) {
        showAbove = false;
      }
    } else if (below < desiredHeight + 6 && above > below) {
      showAbove = true;
    }
    final available = showAbove ? above : below;
    final maximumHeight = math.max(48.0, math.min(320.0, available - 8));
    _highlighted = widget.items.indexWhere(
      (item) => item.value == widget.value,
    );
    if (_highlighted < 0) {
      _highlighted = 0;
    }

    setState(() => _expanded = true);
    _entry = OverlayEntry(
      builder: (_) => _SettingsMenuPanel<T>(
        focusNode: _panelFocusNode,
        link: _layerLink,
        width: math.max(targetSize.width, 64.0),
        maximumHeight: maximumHeight,
        showAbove: showAbove,
        horizontal: widget.anchor.alignment.x,
        items: widget.items,
        value: widget.value,
        highlighted: _highlighted,
        onDismissed: _close,
        onSelected: _select,
        onMoveHighlight: _moveHighlight,
        onHighlightChanged: _setHighlight,
      ),
    );
    overlay.insert(_entry!);
    // The trigger keeps focus when the panel mounts, which would suppress the
    // panel's autofocus; claim it explicitly on the next frame so arrow keys
    // and Escape reach the popup.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _expanded) {
        _panelFocusNode.requestFocus();
      }
    });
  }

  void _close({bool returnFocus = true}) {
    _entry?.remove();
    _entry = null;
    if (mounted && _expanded) {
      setState(() => _expanded = false);
    }
    if (returnFocus && mounted) {
      _triggerFocusNode.requestFocus();
    }
  }

  void _select(SettingsMenuItem<T> item) {
    _close();
    widget.onChanged(item.value);
  }

  void _setHighlight(int index) {
    if (index == _highlighted) {
      return;
    }
    _highlighted = index;
    _entry?.markNeedsBuild();
  }

  void _moveHighlight(int delta) {
    if (widget.items.isEmpty) {
      return;
    }
    final next = (_highlighted + delta).clamp(0, widget.items.length - 1);
    _setHighlight(next);
  }

  @override
  Widget build(BuildContext context) {
    final palette = ShellTheme.of(context).accentPalette;
    final selected = _selected;
    return CompositedTransformTarget(
      link: _layerLink,
      child: KeyedSubtree(
        key: _triggerKey,
        child: SettingsButton(
          label: selected.label,
          variant: SettingsButtonVariant.filledTonal,
          size: SettingsButtonSize.small,
          onPressed: widget.enabled ? _toggle : null,
          focusNode: _triggerFocusNode,
          trailing: Icon(
            Icons.arrow_drop_down,
            size: 20,
            color: palette.onContainer,
          ),
          semanticsLabel: widget.semanticsLabel,
          semanticsValue: selected.label,
          semanticsExpanded: _expanded,
          shortcuts: const <ShortcutActivator, Intent>{
            SingleActivator(LogicalKeyboardKey.arrowDown):
                _OpenSettingsMenuIntent(),
          },
          actions: <Type, Action<Intent>>{
            _OpenSettingsMenuIntent: CallbackAction<_OpenSettingsMenuIntent>(
              onInvoke: (_) {
                _open();
                return null;
              },
            ),
          },
        ),
      ),
    );
  }
}

const double _itemHeight = 48;

class _SettingsMenuPanel<T> extends StatelessWidget {
  const _SettingsMenuPanel({
    required this.focusNode,
    required this.link,
    required this.width,
    required this.maximumHeight,
    required this.showAbove,
    required this.horizontal,
    required this.items,
    required this.value,
    required this.highlighted,
    required this.onDismissed,
    required this.onSelected,
    required this.onMoveHighlight,
    required this.onHighlightChanged,
  });

  final FocusNode focusNode;
  final LayerLink link;
  final double width;
  final double maximumHeight;
  final bool showAbove;
  final double horizontal;
  final List<SettingsMenuItem<T>> items;
  final T value;
  final int highlighted;
  final VoidCallback onDismissed;
  final ValueChanged<SettingsMenuItem<T>> onSelected;
  final ValueChanged<int> onMoveHighlight;
  final ValueChanged<int> onHighlightChanged;

  @override
  Widget build(BuildContext context) {
    final theme = ShellTheme.of(context);
    final colors = context.shellColors;
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: onDismissed,
              child: const SizedBox.expand(),
            ),
          ),
          CompositedTransformFollower(
            link: link,
            showWhenUnlinked: false,
            targetAnchor: Alignment(horizontal, showAbove ? -1 : 1),
            followerAnchor: Alignment(horizontal, showAbove ? 1 : -1),
            offset: Offset(0, showAbove ? -6 : 6),
            child: SizedBox(
              width: width,
              child: Focus(
                focusNode: focusNode,
                autofocus: true,
                onKeyEvent: (node, event) {
                  if (event is! KeyDownEvent &&
                      event is! KeyRepeatEvent) {
                    return KeyEventResult.ignored;
                  }
                  switch (event.logicalKey) {
                    case LogicalKeyboardKey.arrowDown:
                      onMoveHighlight(1);
                      return KeyEventResult.handled;
                    case LogicalKeyboardKey.arrowUp:
                      onMoveHighlight(-1);
                      return KeyEventResult.handled;
                    case LogicalKeyboardKey.enter:
                    case LogicalKeyboardKey.numpadEnter:
                    case LogicalKeyboardKey.space:
                      final index = highlighted;
                      if (index >= 0 && index < items.length) {
                        onSelected(items[index]);
                      }
                      return KeyEventResult.handled;
                    case LogicalKeyboardKey.escape:
                    case LogicalKeyboardKey.tab:
                      onDismissed();
                      return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: Semantics(
                  container: true,
                  explicitChildNodes: true,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: maximumHeight),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.surfaceContainer,
                        borderRadius: theme.borderRadius(
                          ShellShapeScale.extraSmall,
                        ),
                        border: Border.all(color: colors.hairline),
                      ),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(4),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            for (var index = 0; index < items.length; index++)
                              _SettingsMenuRow<T>(
                                item: items[index],
                                selected: items[index].value == value,
                                highlighted: index == highlighted,
                                onHover: () => onHighlightChanged(index),
                                onPressed: () => onSelected(items[index]),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsMenuRow<T> extends StatelessWidget {
  const _SettingsMenuRow({
    required this.item,
    required this.selected,
    required this.highlighted,
    required this.onHover,
    required this.onPressed,
  });

  final SettingsMenuItem<T> item;
  final bool selected;
  final bool highlighted;
  final VoidCallback onHover;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = ShellTheme.of(context);
    final colors = context.shellColors;
    final palette = theme.accentPalette;
    final radius = theme.borderRadius(ShellShapeScale.extraSmall);
    final Color background;
    if (selected) {
      background = palette.container;
    } else if (highlighted) {
      background = colors.surfaceContainerHigh;
    } else {
      background = ShellMediaColors.transparentDark;
    }
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: MouseRegion(
        onEnter: (_) => onHover(),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: _itemHeight),
            child: DecoratedBox(
              decoration: BoxDecoration(color: background, borderRadius: radius),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ShellText.settingsRowTitle.copyWith(
                      color: selected
                          ? palette.onContainer
                          : colors.textPrimary,
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
