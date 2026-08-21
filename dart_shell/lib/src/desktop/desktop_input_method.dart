import 'package:flutter/material.dart' show Icons;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../localization/denial_localizations.dart';
import '../state/fcitx5.dart';
import '../theme/motion.dart';
import '../theme/shell_theme.dart';
import '../theme/tokens.dart';
import '../widgets/shell_cursor.dart';

class DesktopInputMethodMark extends ConsumerWidget {
  const DesktopInputMethodMark({super.key, this.color});

  final Color? color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(fcitx5Provider);
    final label = state.available ? state.shortLabel : '--';
    final foreground = color ?? ShellColors.textPrimary;
    return Semantics(
      label: context.l10n.inputMethodCurrent(label),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.translate_rounded, size: 16, color: foreground),
          const SizedBox(width: 3),
          Text(
            label,
            style: ShellText.systemBarValue.copyWith(color: foreground),
          ),
        ],
      ),
    );
  }
}

class DesktopInputMethodCard extends ConsumerWidget {
  const DesktopInputMethodCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(fcitx5Provider);
    final controller = ref.read(fcitx5Provider.notifier);
    final theme = ShellTheme.of(context);
    final l10n = context.l10n;
    final enabled = state.available;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: ShellColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: ShellColors.hairlineSoft),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 7, 16, 7),
        child: Row(
          children: [
            Icon(Icons.language_rounded, size: 21, color: theme.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(l10n.inputMethodTitle, style: ShellText.cardTitle),
            ),
            _InputMethodOption(
              label: 'EN',
              semanticLabel: l10n.inputMethodEnglish,
              selected: enabled && !state.isChinese,
              enabled: enabled,
              onTap: () => controller.setChinese(false),
            ),
            const SizedBox(width: 6),
            _InputMethodOption(
              label: '\u4e2d',
              semanticLabel: l10n.inputMethodChinese,
              selected: enabled && state.isChinese,
              enabled: enabled,
              onTap: () => controller.setChinese(true),
            ),
          ],
        ),
      ),
    );
  }
}

class _InputMethodOption extends StatefulWidget {
  const _InputMethodOption({
    required this.label,
    required this.semanticLabel,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final String semanticLabel;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_InputMethodOption> createState() => _InputMethodOptionState();
}

class _InputMethodOptionState extends State<_InputMethodOption> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final accent = ShellTheme.of(context).accentPalette;
    return Semantics(
      button: true,
      enabled: widget.enabled,
      selected: widget.selected,
      label: widget.semanticLabel,
      child: FocusableActionDetector(
        enabled: widget.enabled,
        mouseCursor: widget.enabled
            ? ShellMouseCursors.link
            : ShellMouseCursors.normal,
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              if (widget.enabled) widget.onTap();
              return null;
            },
          ),
        },
        onShowHoverHighlight: (value) => setState(() => _hovered = value),
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.enabled ? widget.onTap : null,
          child: AnimatedContainer(
            duration: Motion.pill,
            curve: Motion.standard,
            width: 42,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: widget.selected
                  ? accent.container
                  : _hovered
                  ? ShellColors.surfaceContainerHighest
                  : ShellColors.surfaceContainer,
              borderRadius: BorderRadius.circular(12),
              border: _focused
                  ? Border.all(color: accent.primary, width: 1.5)
                  : Border.all(color: ShellColors.hairlineSoft),
            ),
            child: Text(
              widget.label,
              style: ShellText.cardTitle.copyWith(
                color: !widget.enabled
                    ? ShellColors.glyphInactive
                    : widget.selected
                    ? accent.onContainer
                    : ShellColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
