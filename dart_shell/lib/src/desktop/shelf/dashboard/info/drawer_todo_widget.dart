import 'package:flutter/material.dart' show Colors, Icons;
import 'package:flutter/services.dart'
    show FilteringTextInputFormatter, TextInputAction, TextInputType;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../services/todo_service.dart';
import '../../../../localization/denial_localizations.dart';
import '../../../../state/todo_list.dart';
import '../../../../theme/shell_theme.dart';
import '../../../../theme/tokens.dart';
import '../../../../widgets/shell_cursor.dart';
import '../../../../widgets/shell_hover_pill.dart';

/// Todo list for the dashboard tool drawer: open/completed tabs, quick add,
/// and per-item completion, backed by the persisted todo list state.
class DrawerTodoWidget extends ConsumerStatefulWidget {
  const DrawerTodoWidget({super.key});

  @override
  ConsumerState<DrawerTodoWidget> createState() => _DrawerTodoWidgetState();
}

class _DrawerTodoWidgetState extends ConsumerState<DrawerTodoWidget> {
  final TextEditingController _inputController = TextEditingController();
  final FocusNode _inputFocus = FocusNode();
  bool _showCompleted = false;

  @override
  void dispose() {
    _inputController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _submit() {
    final controller = ref.read(todoListProvider.notifier);
    controller.add(_inputController.text);
    _inputController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final todos = ref.watch(todoListProvider);
    final controller = ref.read(todoListProvider.notifier);
    final openCount = todos.where((item) => !item.done).length;
    final doneCount = todos.length - openCount;
    // Materialized once: leaving this a lazy where() makes the builder's
    // elementAt walk the filter for every row, turning the list O(n^2).
    final visible =
        (_showCompleted
                ? todos.where((item) => item.done)
                : todos.where((item) => !item.done))
            .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TodoTabSwitcher(
          showCompleted: _showCompleted,
          openCount: openCount,
          doneCount: doneCount,
          onSelected: (completed) => setState(() => _showCompleted = completed),
        ),
        const SizedBox(height: 8),
        _TodoQuickAddField(
          controller: _inputController,
          focusNode: _inputFocus,
          onSubmit: _submit,
        ),
        const SizedBox(height: 8),
        Expanded(
          child: visible.isEmpty
              ? _TodoEmptyState(showCompleted: _showCompleted)
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 4),
                  itemCount: visible.length,
                  itemBuilder: (context, index) {
                    final item = visible.elementAt(index);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: _TodoRow(
                        item: item,
                        onToggle: () => controller.toggle(item.id),
                        onRemove: () => controller.remove(item.id),
                      ),
                    );
                  },
                ),
        ),
        if (_showCompleted && doneCount > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: _ClearCompletedButton(onPressed: controller.clearCompleted),
          ),
      ],
    );
  }
}

class _TodoTabSwitcher extends StatelessWidget {
  const _TodoTabSwitcher({
    required this.showCompleted,
    required this.openCount,
    required this.doneCount,
    required this.onSelected,
  });

  final bool showCompleted;
  final int openCount;
  final int doneCount;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = context.shellColors;
    final l10n = context.l10n;
    final radius = theme.borderRadius(ShellShapeScale.full);

    return Container(
      height: 32,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: radius,
      ),
      child: Row(
        children: [
          _TodoTabButton(
            label: l10n.todoOpenCount(openCount),
            selected: !showCompleted,
            onPressed: () => onSelected(false),
          ),
          const SizedBox(width: 4),
          _TodoTabButton(
            label: l10n.todoDoneCount(doneCount),
            selected: showCompleted,
            onPressed: () => onSelected(true),
          ),
        ],
      ),
    );
  }
}

class _TodoTabButton extends StatelessWidget {
  const _TodoTabButton({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = context.shellColors;

    return Expanded(
      child: ShellHoverPill(
        onTap: onPressed,
        radius: ShellShapeScale.full,
        color: selected ? theme.accentPalette.container : Colors.transparent,
        hoverColor: selected
            ? theme.accentPalette.container
            : colors.panelHighlight,
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: selected
                ? theme.accentPalette.onContainer
                : colors.textSecondary,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }
}

/// Raw [EditableText] capsule following the launcher search field: the shell
/// tree has no Material ancestor, so the placeholder is stacked manually.
/// The field rebuilds on every controller edit because both the placeholder
/// and the submit button depend on the text being non-empty.
class _TodoQuickAddField extends StatefulWidget {
  const _TodoQuickAddField({
    required this.controller,
    required this.focusNode,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSubmit;

  @override
  State<_TodoQuickAddField> createState() => _TodoQuickAddFieldState();
}

class _TodoQuickAddFieldState extends State<_TodoQuickAddField> {
  static final List<FilteringTextInputFormatter> _inputFormatters =
      List<FilteringTextInputFormatter>.unmodifiable(
        <FilteringTextInputFormatter>[
          FilteringTextInputFormatter.deny(RegExp('[\\u0000-\\u001F\\u007F]')),
        ],
      );

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleControllerChange);
  }

  @override
  void didUpdateWidget(covariant _TodoQuickAddField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleControllerChange);
      widget.controller.addListener(_handleControllerChange);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChange);
    super.dispose();
  }

  void _handleControllerChange() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = context.shellColors;
    final accent = theme.accentPalette;
    final hasText = widget.controller.text.isNotEmpty;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.cardColor(colors.surfaceContainerHigh),
        borderRadius: theme.borderRadius(ShellShapeScale.full),
      ),
      child: SizedBox(
        height: 40,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Icon(
                Icons.checklist_rounded,
                size: 18,
                color: colors.textSecondary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    if (!hasText)
                      IgnorePointer(
                        child: Text(
                          context.l10n.todoAddHint,
                          style: TextStyle(
                            color: colors.textTertiary,
                            fontSize: 13,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                    EditableText(
                      controller: widget.controller,
                      focusNode: widget.focusNode,
                      mouseCursor: ShellMouseCursors.text,
                      maxLines: 1,
                      keyboardType: TextInputType.text,
                      textInputAction: TextInputAction.done,
                      onEditingComplete: widget.onSubmit,
                      onSubmitted: (_) => widget.onSubmit(),
                      style: theme.text.base.copyWith(fontSize: 13),
                      cursorColor: accent.primary,
                      backgroundCursorColor: colors.textSecondary,
                      selectionColor: accent.selection,
                      // Raw shortcuts and text input are separate channels.
                      // Deny control characters in case an IME commits one.
                      inputFormatters: _inputFormatters,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _TodoSubmitButton(enabled: hasText, onPressed: widget.onSubmit),
            ],
          ),
        ),
      ),
    );
  }
}

class _TodoSubmitButton extends StatelessWidget {
  const _TodoSubmitButton({required this.enabled, required this.onPressed});

  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = context.shellColors;

    return ShellHoverPill.builder(
      onTap: onPressed,
      enabled: enabled,
      width: 28,
      height: 28,
      color: enabled ? theme.accentPalette.container : colors.tileOff,
      hoverColor: theme.accentPalette.primary,
      childBuilder: (context, hovered, focused) => Icon(
        Icons.add_rounded,
        size: 18,
        color: !enabled
            ? colors.textTertiary
            : (hovered
                  ? theme.accentPalette.onPrimary
                  : theme.accentPalette.onContainer),
      ),
    );
  }
}

class _TodoRow extends StatelessWidget {
  const _TodoRow({
    required this.item,
    required this.onToggle,
    required this.onRemove,
  });

  final TodoItem item;
  final VoidCallback onToggle;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.shellColors;

    return Row(
      children: [
        _TodoCheckbox(checked: item.done, onToggle: onToggle),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: item.done ? colors.textTertiary : colors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              decoration: item.done ? TextDecoration.lineThrough : null,
              decorationColor: colors.textTertiary,
            ),
          ),
        ),
        const SizedBox(width: 6),
        _TodoRemoveButton(onPressed: onRemove),
      ],
    );
  }
}

class _TodoCheckbox extends StatelessWidget {
  const _TodoCheckbox({required this.checked, required this.onToggle});

  final bool checked;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = context.shellColors;

    return ShellHoverPill(
      onTap: onToggle,
      width: 22,
      height: 22,
      radius: ShellShapeScale.extraSmall,
      color: checked ? theme.accentPalette.primary : Colors.transparent,
      hoverColor: checked ? theme.accentPalette.primary : colors.panelHighlight,
      border: checked
          ? null
          : Border.all(color: colors.hairlineSoft, width: 1.5),
      hoverBorder: checked
          ? null
          : Border.all(color: colors.textTertiary, width: 1.5),
      child: checked
          ? Icon(
              Icons.check_rounded,
              size: 16,
              color: theme.accentPalette.onPrimary,
            )
          : const SizedBox.shrink(),
    );
  }
}

class _TodoRemoveButton extends StatelessWidget {
  const _TodoRemoveButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.shellColors;

    return ShellHoverPill.builder(
      onTap: onPressed,
      width: 24,
      height: 24,
      color: Colors.transparent,
      hoverColor: colors.panelHighlight,
      childBuilder: (context, hovered, focused) => Icon(
        Icons.close_rounded,
        size: 14,
        color: hovered ? colors.textSecondary : colors.textTertiary,
      ),
    );
  }
}

class _TodoEmptyState extends StatelessWidget {
  const _TodoEmptyState({required this.showCompleted});

  final bool showCompleted;

  @override
  Widget build(BuildContext context) {
    final colors = context.shellColors;
    final l10n = context.l10n;
    final title = showCompleted
        ? l10n.todoNothingCompleted
        : l10n.todoAllCaughtUp;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            showCompleted ? Icons.task_alt_rounded : Icons.celebration_rounded,
            size: 30,
            color: colors.textTertiary,
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: TextStyle(
              color: colors.textTertiary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }
}

class _ClearCompletedButton extends StatelessWidget {
  const _ClearCompletedButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.shellColors;

    return ShellHoverPill(
      onTap: onPressed,
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: colors.surfaceContainerHighest,
      hoverColor: colors.panelHighlight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.delete_sweep_rounded,
            size: 15,
            color: colors.textSecondary,
          ),
          const SizedBox(width: 6),
          Text(
            context.l10n.todoClearCompleted,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }
}
