import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../localization/denial_localizations.dart';
import '../../launcher/models/desktop_app.dart';
import '../../models/shortcut_configuration.dart';
import '../../state/shortcut_configuration.dart';
import '../../theme/shell_theme.dart';
import '../../theme/tokens.dart';
import 'settings_buttons.dart';
import 'settings_controls.dart';
import 'settings_loading_indicator.dart';
import 'settings_shortcut_editor.dart';
import 'settings_shortcut_presentation.dart';

class SettingsShortcutsPage extends ConsumerStatefulWidget {
  const SettingsShortcutsPage({
    this.applications = const <DesktopApp>[],
    super.key,
  });

  final List<DesktopApp> applications;

  @override
  ConsumerState<SettingsShortcutsPage> createState() =>
      _SettingsShortcutsPageState();
}

class _SettingsShortcutsPageState extends ConsumerState<SettingsShortcutsPage> {
  var _editorOpen = false;
  DenialShortcutBinding? _editedBinding;

  void _openEditor(DenialShortcutBinding? binding) {
    ref.read(shortcutConfigurationProvider.notifier).clearError();
    setState(() {
      _editedBinding = binding;
      _editorOpen = true;
    });
  }

  void _closeEditor() {
    ref.read(shortcutConfigurationProvider.notifier).clearError();
    setState(() {
      _editorOpen = false;
      _editedBinding = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(shortcutConfigurationProvider);
    final controller = ref.read(shortcutConfigurationProvider.notifier);
    final configuration = state.configuration;
    final l10n = context.l10n;
    return Stack(
      fit: StackFit.expand,
      children: [
        SettingsPageLayout(
          icon: Icons.keyboard_command_key_rounded,
          eyebrow: l10n.settingsShortcutsSection,
          title: l10n.settingsShortcutsTitle,
          children: [
            if (state.error case final error?)
              _ShortcutErrorBanner(
                error: error,
                canRetry: !state.busy,
                onRetry: () => unawaited(controller.refresh()),
              ),
            _ShortcutList(
              state: state,
              onRetry: () => unawaited(controller.refresh()),
              onEdit: state.busy ? null : _openEditor,
              onDelete: (shortcut) =>
                  unawaited(controller.removeShortcut(shortcut)),
            ),
            Row(
              children: [
                if (configuration case final configuration?)
                  _ShortcutCountBadge(count: configuration.shortcuts.length),
                const Spacer(),
                SettingsButton(
                  label: l10n.settingsShortcutsAdd,
                  variant: SettingsButtonVariant.filledTonal,
                  icon: Icons.add_rounded,
                  onPressed: configuration == null || state.busy
                      ? null
                      : () => _openEditor(null),
                ),
              ],
            ),
          ],
        ),
        if (_editorOpen && configuration != null)
          SettingsShortcutEditor(
            key: ValueKey<String>(
              _editedBinding == null
                  ? 'shortcut-editor-add'
                  : 'shortcut-editor-${_editedBinding!.shortcut}',
            ),
            configuration: configuration,
            applications: widget.applications,
            binding: _editedBinding,
            busy: state.busy,
            deleteBusy: state.deletingShortcut == _editedBinding?.shortcut,
            nativeError: state.error,
            onValidate: controller.validateShortcut,
            onSave: (shortcut) async {
              final edited = _editedBinding;
              final saved = edited == null
                  ? await controller.addShortcut(shortcut)
                  : await controller.updateShortcut(
                      existingShortcut: edited.shortcut,
                      shortcut: shortcut,
                    );
              if (mounted && saved) {
                _closeEditor();
              }
              return saved;
            },
            onDelete: _editedBinding == null
                ? null
                : () async {
                    final deleted = await controller.removeShortcut(
                      _editedBinding!.shortcut,
                    );
                    if (mounted && deleted) {
                      _closeEditor();
                    }
                    return deleted;
                  },
            onClearError: controller.clearError,
            onClose: state.busy ? () {} : _closeEditor,
          ),
      ],
    );
  }
}

class _ShortcutCountBadge extends StatelessWidget {
  const _ShortcutCountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.shellColors.surfaceContainerHigh,
        borderRadius: context.shellTheme.borderRadius(ShellShapeScale.full),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Text(
          context.l10n.settingsShortcutsConfigured(count),
          style: ShellText.settingsBadgeLabel.copyWith(
            color: context.shellColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _ShortcutList extends StatelessWidget {
  const _ShortcutList({
    required this.state,
    required this.onRetry,
    required this.onEdit,
    required this.onDelete,
  });

  final ShortcutConfigurationState state;
  final VoidCallback onRetry;
  final ValueChanged<DenialShortcutBinding>? onEdit;
  final ValueChanged<String> onDelete;

  @override
  Widget build(BuildContext context) {
    final configuration = state.configuration;
    if (configuration == null) {
      if (state.loading) {
        return _ShortcutStatus(
          icon: Icons.keyboard_command_key_rounded,
          message: context.l10n.settingsShortcutsLoading,
          loading: true,
        );
      }
      return _ShortcutStatus(
        icon: Icons.link_off_rounded,
        message: context.l10n.settingsShortcutsUnavailable,
        actionLabel: context.l10n.settingsShortcutsRetry,
        onAction: onRetry,
      );
    }
    if (configuration.shortcuts.isEmpty) {
      return _ShortcutStatus(
        icon: Icons.keyboard_command_key_rounded,
        message: context.l10n.settingsShortcutsEmpty,
      );
    }
    return FocusTraversalGroup(
      child: SettingsCardGroup(
        children: [
          for (final binding in configuration.shortcuts)
            _ShortcutRow(
              key: ValueKey<String>(binding.shortcut),
              binding: binding,
              deleteBusy: state.deletingShortcut == binding.shortcut,
              deleteEnabled: !state.busy,
              onEdit: onEdit == null ? null : () => onEdit!(binding),
              onDelete: () => onDelete(binding.shortcut),
            ),
        ],
      ),
    );
  }
}

class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow({
    required this.binding,
    required this.deleteBusy,
    required this.deleteEnabled,
    required this.onEdit,
    required this.onDelete,
    super.key,
  });

  final DenialShortcutBinding binding;
  final bool deleteBusy;
  final bool deleteEnabled;
  final VoidCallback? onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final actionLabel = settingsShortcutTargetLabel(context, binding);
    final displayShortcut = settingsShortcutDisplay(context, binding.shortcut);
    return Semantics(
      container: true,
      label: context.l10n.settingsShortcutsRowSemantics(
        displayShortcut,
        actionLabel,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          children: [
            Expanded(
              flex: 5,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Tooltip(
                  message: displayShortcut,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: context.shellColors.surfaceContainerHigh,
                      borderRadius: context.shellTheme.borderRadius(
                        ShellShapeScale.small,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 8,
                      ),
                      child: Text(
                        displayShortcut,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ShellText.settingsSectionHeader.copyWith(
                          color: context.shellColors.textPrimary,
                          fontFamily: ShellText.systemBarFontFamily,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Icon(
                Icons.arrow_forward_rounded,
                size: 15,
                color: context.shellColors.textSecondary,
              ),
            ),
            Expanded(
              flex: 5,
              child: Row(
                children: [
                  _ShortcutTargetGlyph(binding: binding),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      actionLabel,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: ShellText.settingsRowTitle.copyWith(
                        color: context.shellColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _ShortcutIconButton(
              icon: Icons.edit_outlined,
              tooltip: context.l10n.settingsShortcutEditorEditTitle,
              onPressed: onEdit,
            ),
            const SizedBox(width: 4),
            _ShortcutIconButton(
              icon: Icons.delete_outline_rounded,
              tooltip: context.l10n.settingsShortcutsDeleteTooltip(
                displayShortcut,
              ),
              destructive: true,
              busy: deleteBusy,
              onPressed: deleteEnabled ? onDelete : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _ShortcutTargetGlyph extends StatelessWidget {
  const _ShortcutTargetGlyph({required this.binding});

  final DenialShortcutBinding binding;

  @override
  Widget build(BuildContext context) {
    final palette = ShellTheme.of(context).accentPalette;
    final accent = palette.primary;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: accent.withAlpha(30),
        shape: BoxShape.circle,
        border: Border.all(color: accent.withAlpha(70)),
      ),
      child: SizedBox.square(
        dimension: 34,
        child: Icon(
          settingsShortcutTargetIcon(binding),
          size: 17,
          color: accent,
        ),
      ),
    );
  }
}

class _ShortcutIconButton extends StatelessWidget {
  const _ShortcutIconButton({
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.destructive = false,
    this.busy = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool destructive;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final foreground = destructive
        ? context.shellColors.performanceBad
        : context.shellColors.textSecondary;
    return IconButton(
      tooltip: tooltip,
      onPressed: busy ? null : onPressed,
      iconSize: 18,
      constraints: const BoxConstraints.tightFor(width: 40, height: 40),
      padding: EdgeInsets.zero,
      style: IconButton.styleFrom(
        foregroundColor: foreground,
        disabledForegroundColor: context.shellColors.textSecondary.withAlpha(86),
        backgroundColor: context.shellColors.surfaceContainerHigh,
        disabledBackgroundColor: context.shellColors.surfaceContainerHigh
            .withAlpha(120),
        hoverColor: foreground.withAlpha(28),
        focusColor: foreground.withAlpha(28),
        shape: RoundedRectangleBorder(
          borderRadius: context.shellTheme.borderRadius(ShellShapeScale.medium),
          side: BorderSide(color: context.shellColors.hairline),
        ),
      ),
      icon: busy
          ? SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: foreground,
              ),
            )
          : Icon(icon),
    );
  }
}

class _ShortcutErrorBanner extends StatelessWidget {
  const _ShortcutErrorBanner({
    required this.error,
    required this.canRetry,
    required this.onRetry,
  });

  final String error;
  final bool canRetry;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.shellColors.performanceBad.withAlpha(18),
          borderRadius: context.shellTheme.borderRadius(ShellShapeScale.medium),
          border: Border.all(
            color: context.shellColors.performanceBad.withAlpha(82),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(13, 10, 8, 10),
          child: Row(
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: 18,
                color: context.shellColors.performanceBad,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  error,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: ShellText.settingsRowSupport.copyWith(
                    color: context.shellColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SettingsTextButton(
                label: context.l10n.settingsShortcutsRetry,
                onPressed: canRetry ? onRetry : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShortcutStatus extends StatelessWidget {
  const _ShortcutStatus({
    required this.icon,
    required this.message,
    this.loading = false,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final bool loading;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (loading)
                SettingsLoadingIndicator(semanticsLabel: message)
              else
                Icon(icon, size: 34, color: context.shellColors.textSecondary),
              const SizedBox(height: 14),
              Text(
                message,
                textAlign: TextAlign.center,
                style: ShellText.settingsRowSupport.copyWith(
                  color: context.shellColors.textSecondary,
                ),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 14),
                SettingsTextButton(label: actionLabel!, onPressed: onAction),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
