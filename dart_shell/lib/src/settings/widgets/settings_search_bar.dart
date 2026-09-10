import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../localization/denial_localizations.dart';
import '../../theme/shell_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/shell_cursor.dart';

/// Height of the Settings search capsule (`02-VISUAL-SPEC.md` §3.1).
const double settingsSearchBarHeight = 56;

/// Identifies the search capsule for tests and layout asserts.
const settingsSearchBarKey = ValueKey<String>('settings-search-bar');

/// Horizontal inset of the search capsule contents.
///
/// The geometry table fixes the capsule height, radius, icon, and text roles
/// but not its inset; 16 is the shell's governing edge inset (§2.2) and keeps
/// the capsule aligned with the navigation cards below it.
const double settingsSearchBarInset = 16;

/// Diameter of the capsule's leading search glyph and trailing clear glyph
/// (§3.1 fixes the leading glyph at 24; the clear affordance reuses it so the
/// capsule keeps one icon size).
const double settingsSearchBarIconSize = 24;

/// Square tap/state-layer box of the trailing clear affordance.
///
/// 40 is the shell's established affordance size (§2.3 back button,
/// §3.4 switch state layer).
const double settingsSearchClearSize = 40;

/// Identifies the search clear affordance for its semantics asserts.
const settingsSearchClearKey = ValueKey<String>('settings-search-clear');

/// Search wiring the navigation needs to host the capsule and the result area
/// (§3.2). The application owns the state; this is the minimal interface the
/// navigation exposes for it.
@immutable
class SettingsSearchBinding {
  const SettingsSearchBinding({
    required this.query,
    required this.active,
    required this.onQueryChanged,
    required this.onActivate,
    required this.onDismiss,
    this.onPrevious,
    this.onNext,
    this.onSubmit,
    this.results,
  });

  final String query;
  final bool active;
  final ValueChanged<String> onQueryChanged;

  /// Focus (or tap) entered the capsule; the search view should open.
  final VoidCallback onActivate;

  /// Escape / clear-then-blur: return to the navigation list.
  final VoidCallback onDismiss;

  /// Move the result highlight up one row.
  final VoidCallback? onPrevious;

  /// Move the result highlight down one row.
  final VoidCallback? onNext;

  /// Open the highlighted result.
  final VoidCallback? onSubmit;

  /// Result view rendered in place of the navigation list while [active].
  final Widget? results;
}

/// The Android 17-style search capsule that heads the Settings navigation.
///
/// S02 shipped the appearance; S07 makes it a real search field. A tap opens the
/// search, the field reports every keystroke (the host opens the search on the
/// first non-empty query), and Escape — or clearing the query and moving focus
/// away — returns to the navigation list. Arrow keys and Enter are forwarded to
/// the host so results stay reachable from the keyboard alone (§3.3).
class SettingsSearchBar extends StatefulWidget {
  const SettingsSearchBar({
    required this.query,
    required this.active,
    required this.onQueryChanged,
    required this.onActivate,
    required this.onDismiss,
    this.onPrevious,
    this.onNext,
    this.onSubmit,
    super.key,
  });

  final String query;
  final bool active;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onActivate;
  final VoidCallback onDismiss;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onSubmit;

  @override
  State<SettingsSearchBar> createState() => _SettingsSearchBarState();
}

class _SettingsSearchBarState extends State<SettingsSearchBar> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.query);
    _focusNode = FocusNode(
      debugLabel: 'settings-search-field',
      onKeyEvent: _handleKeyEvent,
    );
  }

  @override
  void didUpdateWidget(covariant SettingsSearchBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller.text != widget.query) {
      // Keep the field in step with host-driven changes (clearing the query,
      // closing the search after picking a result).
      _controller.value = TextEditingValue(
        text: widget.query,
        selection: TextSelection.collapsed(offset: widget.query.length),
      );
    }
    if (oldWidget.active && !widget.active) {
      _focusNode.unfocus();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _requestFocus() {
    if (!_focusNode.hasFocus) {
      _focusNode.requestFocus();
    }
  }

  /// A pointer anywhere in the capsule opens the search and focuses the field.
  ///
  /// This is a [Listener] rather than a tap recognizer so the field's own
  /// tap-to-focus can win the gesture arena without swallowing the activation.
  void _activateAndFocus() {
    if (!widget.active) {
      widget.onActivate();
    }
    _requestFocus();
  }

  /// Tracks focus for the whole capsule, so moving between the field and the
  /// clear button never counts as leaving the search.
  ///
  /// Focus alone does not open the search: that would replace the navigation
  /// list the moment Tab reaches the capsule and make the destinations
  /// unreachable by keyboard. Typing opens it instead (the host activates on a
  /// non-empty query), and clearing then moving focus away closes it (§3.2).
  void _handleCapsuleFocus(bool hasFocus) {
    if (!hasFocus && widget.active && widget.query.isEmpty) {
      widget.onDismiss();
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.escape:
        widget.onDismiss();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
        widget.onNext?.call();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        widget.onPrevious?.call();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
        widget.onSubmit?.call();
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _clear() {
    widget.onQueryChanged('');
    _requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = ShellTheme.of(context);
    final colors = context.shellColors;
    final palette = theme.accentPalette;
    final hint = l10n.settingsSearchHint;
    final fieldStyle = ShellText.settingsSearchHint.copyWith(
      color: colors.textPrimary,
    );
    return SizedBox(
      key: settingsSearchBarKey,
      height: settingsSearchBarHeight,
      child: Focus(
        canRequestFocus: false,
        onFocusChange: _handleCapsuleFocus,
        // The whole capsule focuses the field, so its full 56dp body is a tap
        // target; inner controls (field, clear button) still win their own taps.
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (_) => _activateAndFocus(),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: theme.cardColor(colors.surfaceContainerHigh),
              borderRadius: theme.borderRadius(ShellShapeScale.full),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: settingsSearchBarInset,
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.search_rounded,
                    size: settingsSearchBarIconSize,
                    color: colors.textSecondary,
                  ),
                  const SizedBox(width: settingsSearchBarInset),
                  Expanded(
                    // The placeholder is painted outside the field's semantics
                    // and the field is labelled explicitly, so assistive
                    // technology reads one "Settings search" text field rather
                    // than the hint twice (§3.3).
                    child: Stack(
                      alignment: Alignment.centerLeft,
                      children: <Widget>[
                        if (widget.query.isEmpty)
                          ExcludeSemantics(
                            child: Text(
                              hint,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: fieldStyle.copyWith(
                                color: colors.textTertiary,
                              ),
                            ),
                          ),
                        MergeSemantics(
                          child: Semantics(
                            textField: true,
                            label: hint,
                            child: TextField(
                              controller: _controller,
                              focusNode: _focusNode,
                              style: fieldStyle,
                              cursorColor: palette.primary,
                              cursorWidth: 2,
                              maxLines: 1,
                              textInputAction: TextInputAction.search,
                              textAlignVertical: TextAlignVertical.center,
                              decoration: const InputDecoration(
                                isCollapsed: true,
                                border: InputBorder.none,
                              ),
                              onChanged: widget.onQueryChanged,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.active)
                    _SearchClearButton(onPressed: _clear),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Trailing clear affordance (§3.3: explicit `settingsSearchClear` label).
class _SearchClearButton extends StatefulWidget {
  const _SearchClearButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<_SearchClearButton> createState() => _SearchClearButtonState();
}

class _SearchClearButtonState extends State<_SearchClearButton> {
  var _hovered = false;
  var _focused = false;

  @override
  Widget build(BuildContext context) {
    final theme = ShellTheme.of(context);
    final colors = context.shellColors;
    final label = context.l10n.settingsSearchClear;
    return Semantics(
      container: true,
      button: true,
      label: label,
      child: FocusableActionDetector(
        key: settingsSearchClearKey,
        mouseCursor: ShellMouseCursors.link,
        onShowHoverHighlight: (value) => setState(() => _hovered = value),
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onPressed();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: SizedBox(
            width: settingsSearchClearSize,
            height: settingsSearchClearSize,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _hovered ? colors.surfaceContainerHighest : null,
                borderRadius: theme.borderRadius(ShellShapeScale.full),
                border: _focused
                    ? Border.all(color: theme.accentPalette.primary, width: 2)
                    : null,
              ),
              child: Center(
                child: Icon(
                  Icons.close_rounded,
                  size: settingsSearchBarIconSize,
                  color: _hovered || _focused
                      ? colors.textPrimary
                      : colors.textSecondary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
