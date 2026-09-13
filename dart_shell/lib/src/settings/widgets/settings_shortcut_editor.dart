import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../launcher/models/desktop_app.dart';
import '../../launcher/services/desktop_exec_parser.dart';
import '../../localization/denial_localizations.dart';
import '../../models/shortcut_configuration.dart';
import '../../theme/motion.dart';
import '../../theme/shell_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/app_icon.dart';
import 'settings_buttons.dart';
import 'settings_controls.dart';
import 'settings_loading_indicator.dart';
import 'settings_shortcut_presentation.dart';

typedef ShortcutValidationCallback =
    Future<DenialShortcutValidation> Function({
      required DenialShortcutBinding shortcut,
      String? existingShortcut,
    });

class SettingsShortcutEditor extends StatefulWidget {
  const SettingsShortcutEditor({
    required this.configuration,
    required this.applications,
    required this.binding,
    required this.busy,
    required this.deleteBusy,
    required this.nativeError,
    required this.onValidate,
    required this.onSave,
    required this.onDelete,
    required this.onClearError,
    required this.onClose,
    super.key,
  });

  final DenialShortcutConfiguration configuration;
  final List<DesktopApp> applications;
  final DenialShortcutBinding? binding;
  final bool busy;
  final bool deleteBusy;
  final String? nativeError;
  final ShortcutValidationCallback onValidate;
  final Future<bool> Function(DenialShortcutBinding shortcut) onSave;
  final Future<bool> Function()? onDelete;
  final VoidCallback onClearError;
  final VoidCallback onClose;

  @override
  State<SettingsShortcutEditor> createState() => _SettingsShortcutEditorState();
}

enum _EditorView { form, actions, applications, inputs }

enum _EditorTarget { denialAction, application, spawn, spawnSh }

class _SettingsShortcutEditorState extends State<SettingsShortcutEditor> {
  static const Duration _validationDebounce = Duration(milliseconds: 300);

  late final TextEditingController _shortcut;
  late final TextEditingController _catalogSearch;
  late final TextEditingController _program;
  late final TextEditingController _shellCommand;
  final List<TextEditingController> _arguments = [];
  late _EditorTarget _targetKind;
  late DenialShortcutAction _action;
  late List<DenialShortcutAction> _visibleActions;
  late List<DesktopApp> _visibleApplications;
  late List<DenialShortcutInput> _visibleInputs;
  String? _selectedDesktopFileId;
  List<String> _applicationCommand = const <String>[];
  Timer? _validationTimer;
  var _validationGeneration = 0;
  var _validating = false;
  DenialShortcutValidation? _validation;
  String? _validationFailure;
  var _view = _EditorView.form;

  String? get _existingShortcut => widget.binding?.shortcut;

  @override
  void initState() {
    super.initState();
    _shortcut = TextEditingController(text: widget.binding?.shortcut ?? '');
    _catalogSearch = TextEditingController();
    final target = widget.binding?.target;
    _targetKind = switch (target) {
      DenialShortcutSpawnTarget(:final desktopFileId)
          when desktopFileId != null =>
        _EditorTarget.application,
      DenialShortcutSpawnTarget() => _EditorTarget.spawn,
      DenialShortcutSpawnShTarget() => _EditorTarget.spawnSh,
      _ => _EditorTarget.denialAction,
    };
    _action = switch (target) {
      DenialShortcutActionTarget(:final action) => action,
      _ => widget.configuration.supportedActions.first,
    };
    final command = switch (target) {
      DenialShortcutSpawnTarget(:final command) => command,
      _ => const <String>[],
    };
    _selectedDesktopFileId = switch (target) {
      DenialShortcutSpawnTarget(:final desktopFileId) => desktopFileId,
      _ => null,
    };
    if (_selectedDesktopFileId != null) {
      _applicationCommand = command;
    }
    _program = TextEditingController(
      text: command.isEmpty ? '' : command.first,
    );
    for (final argument in command.skip(1)) {
      _arguments.add(TextEditingController(text: argument));
    }
    _shellCommand = TextEditingController(
      text: switch (target) {
        DenialShortcutSpawnShTarget(:final command) => command,
        _ => '',
      },
    );
    _visibleActions = widget.configuration.supportedActions;
    _visibleApplications = widget.applications;
    _visibleInputs = widget.configuration.supportedInputs;
    _validating = true;
    final generation = ++_validationGeneration;
    _validationTimer = Timer(
      Duration.zero,
      () => unawaited(_validate(generation)),
    );
  }

  @override
  void didUpdateWidget(covariant SettingsShortcutEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.configuration.revision != widget.configuration.revision) {
      _filterCatalog(_catalogSearch.text);
      _scheduleValidation();
    }
    if (!identical(oldWidget.applications, widget.applications)) {
      _visibleApplications = _filteredApplications(_catalogSearch.text);
    }
  }

  @override
  void dispose() {
    _validationTimer?.cancel();
    _validationGeneration += 1;
    _shortcut.dispose();
    _catalogSearch.dispose();
    _program.dispose();
    _shellCommand.dispose();
    for (final argument in _arguments) {
      argument.dispose();
    }
    super.dispose();
  }

  void _scheduleValidation() {
    _validationTimer?.cancel();
    final generation = ++_validationGeneration;
    widget.onClearError();
    setState(() {
      _validating = true;
      _validation = null;
      _validationFailure = null;
    });
    _validationTimer = Timer(
      _validationDebounce,
      () => unawaited(_validate(generation)),
    );
  }

  Future<void> _validate(int generation) async {
    try {
      final validation = await widget.onValidate(
        shortcut: _draftBinding(_shortcut.text),
        existingShortcut: _existingShortcut,
      );
      if (!mounted || generation != _validationGeneration) {
        return;
      }
      setState(() {
        _validating = false;
        _validation = validation;
        _validationFailure = null;
      });
    } on Object catch (error) {
      if (!mounted || generation != _validationGeneration) {
        return;
      }
      setState(() {
        _validating = false;
        _validation = null;
        _validationFailure = error.toString();
      });
    }
  }

  Future<void> _save() async {
    final validation = _validation;
    final canonical = validation?.canonical;
    if (widget.busy || validation?.isValid != true || canonical == null) {
      return;
    }
    await widget.onSave(_draftBinding(canonical));
  }

  DenialShortcutBinding _draftBinding(String shortcut) {
    return switch (_targetKind) {
      _EditorTarget.denialAction => DenialShortcutBinding(
        shortcut: shortcut,
        target: DenialShortcutActionTarget(_action),
      ),
      _EditorTarget.application => DenialShortcutBinding(
        shortcut: shortcut,
        target: DenialShortcutSpawnTarget(
          _applicationCommand,
          desktopFileId: _selectedDesktopFileId,
        ),
      ),
      _EditorTarget.spawn => DenialShortcutBinding(
        shortcut: shortcut,
        target: DenialShortcutSpawnTarget(<String>[
          _program.text,
          for (final argument in _arguments) argument.text,
        ]),
      ),
      _EditorTarget.spawnSh => DenialShortcutBinding(
        shortcut: shortcut,
        target: DenialShortcutSpawnShTarget(_shellCommand.text),
      ),
    };
  }

  void _selectTarget(_EditorTarget target) {
    if (_targetKind == target) {
      return;
    }
    _targetKind = target;
    _scheduleValidation();
  }

  void _addArgument() {
    _arguments.add(TextEditingController());
    _scheduleValidation();
  }

  void _removeArgument(int index) {
    final controller = _arguments.removeAt(index);
    controller.dispose();
    _scheduleValidation();
  }

  void _openCatalog(_EditorView view) {
    _catalogSearch.clear();
    setState(() {
      _view = view;
      _visibleActions = widget.configuration.supportedActions;
      _visibleApplications = widget.applications;
      _visibleInputs = widget.configuration.supportedInputs;
    });
  }

  void _closeCatalog() {
    setState(() => _view = _EditorView.form);
  }

  void _filterCatalog(String query) {
    final normalized = query.trim().toLowerCase();
    if (_view == _EditorView.actions) {
      final actions = normalized.isEmpty
          ? widget.configuration.supportedActions
          : widget.configuration.supportedActions
                .where((action) {
                  return settingsShortcutActionLabel(
                    context,
                    action,
                  ).toLowerCase().contains(normalized);
                })
                .toList(growable: false);
      setState(() => _visibleActions = actions);
      return;
    }
    if (_view == _EditorView.inputs) {
      final inputs = normalized.isEmpty
          ? widget.configuration.supportedInputs
          : widget.configuration.supportedInputs
                .where((input) {
                  final category = settingsShortcutInputCategoryLabel(
                    context,
                    input.category,
                  ).toLowerCase();
                  return input.canonical.toLowerCase().contains(normalized) ||
                      category.contains(normalized) ||
                      input.aliases.any(
                        (alias) => alias.toLowerCase().contains(normalized),
                      );
                })
                .toList(growable: false);
      setState(() => _visibleInputs = inputs);
      return;
    }
    if (_view == _EditorView.applications) {
      setState(() => _visibleApplications = _filteredApplications(query));
    }
  }

  List<DesktopApp> _filteredApplications(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return widget.applications;
    }
    return widget.applications
        .where(
          (application) =>
              application.name.toLowerCase().contains(normalized) ||
              application.id.toLowerCase().contains(normalized),
        )
        .toList(growable: false);
  }

  void _selectAction(DenialShortcutAction action) {
    _action = action;
    _view = _EditorView.form;
    _scheduleValidation();
  }

  void _selectApplication(DesktopApp application) {
    _selectedDesktopFileId = application.id;
    _applicationCommand = const DesktopExecParser().parse(
      application.exec,
      application,
    );
    _view = _EditorView.form;
    _scheduleValidation();
  }

  void _insertInput(DenialShortcutInput input) {
    if (input.kind == DenialShortcutInputKind.gesture) {
      _shortcut.value = TextEditingValue(
        text: input.canonical,
        selection: TextSelection.collapsed(offset: input.canonical.length),
      );
      _view = _EditorView.form;
      _scheduleValidation();
      return;
    }
    final value = _shortcut.value;
    final selection = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed(offset: value.text.length);
    final before = value.text.substring(0, selection.start);
    final after = value.text.substring(selection.end);
    final leadingSeparator = before.isNotEmpty && !before.endsWith('+')
        ? '+'
        : '';
    final trailingSeparator = after.isNotEmpty && !after.startsWith('+')
        ? '+'
        : '';
    final insertion = '$leadingSeparator${input.canonical}$trailingSeparator';
    final text = '$before$insertion$after';
    _shortcut.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(
        offset: before.length + insertion.length,
      ),
    );
    _catalogSearch.clear();
    _visibleInputs = widget.configuration.supportedInputs;
    _scheduleValidation();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.binding == null
        ? context.l10n.settingsShortcutEditorAddTitle
        : context.l10n.settingsShortcutEditorEditTitle;
    final closeOrBack = _view == _EditorView.form
        ? widget.onClose
        : _closeCatalog;
    return SettingsModalScrim(
      // Content-level Escape handling (catalog back navigation, busy guard)
      // runs ahead of the scrim's fallback dismiss.
      onDismiss: widget.busy ? () {} : closeOrBack,
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.escape): widget.busy
              ? () {}
              : closeOrBack,
        },
        child: Semantics(
          container: true,
          scopesRoute: true,
          namesRoute: true,
          explicitChildNodes: true,
          label: title,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 620,
                  maxHeight: constraints.maxHeight,
                ),
                child: _EditorSurface(
                  title: title,
                  busy: widget.busy,
                  onClose: widget.onClose,
                  child: AnimatedSwitcher(
                    duration: Motion.tile,
                    switchInCurve: Motion.md3EmphasizedDecelerate,
                    switchOutCurve: Motion.md3EmphasizedAccelerate,
                    child: switch (_view) {
                      _EditorView.form => _buildForm(),
                      _EditorView.actions => _buildActionCatalog(),
                      _EditorView.applications => _buildApplicationCatalog(),
                      _EditorView.inputs => _buildInputCatalog(),
                    },
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Column(
      key: const ValueKey<String>('shortcut-editor-form'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
            child: FocusTraversalGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    context.l10n.settingsShortcutEditorDescription,
                    style: ShellText.base.copyWith(
                      color: context.shellColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 18),
                  _EditorFieldLabel(
                    label: context.l10n.settingsShortcutEditorShortcutLabel,
                  ),
                  const SizedBox(height: 8),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final field = _ShortcutTextField(
                        controller: _shortcut,
                        enabled: !widget.busy,
                        onChanged: (_) => _scheduleValidation(),
                      );
                      final browser = SettingsTextButton(
                        label:
                            context.l10n.settingsShortcutEditorSupportedInputs,
                        onPressed: widget.busy
                            ? null
                            : () => _openCatalog(_EditorView.inputs),
                      );
                      if (constraints.maxWidth < 470) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            field,
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: browser,
                            ),
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: field),
                          const SizedBox(width: 10),
                          browser,
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  _EditorFieldLabel(
                    label: context.l10n.settingsShortcutEditorTargetLabel,
                  ),
                  const SizedBox(height: 8),
                  _TargetSelectionField(
                    target: _targetKind,
                    enabled: !widget.busy,
                    onSelected: _selectTarget,
                  ),
                  const SizedBox(height: 12),
                  switch (_targetKind) {
                    _EditorTarget.denialAction => _ActionSelectionField(
                      action: _action,
                      enabled: !widget.busy,
                      onPressed: () => _openCatalog(_EditorView.actions),
                    ),
                    _EditorTarget.application => _ApplicationSelectionField(
                      application: _selectedApplication,
                      desktopFileId: _selectedDesktopFileId,
                      enabled: !widget.busy,
                      onPressed: () => _openCatalog(_EditorView.applications),
                    ),
                    _EditorTarget.spawn => _DirectCommandEditor(
                      program: _program,
                      arguments: _arguments,
                      enabled: !widget.busy,
                      onChanged: _scheduleValidation,
                      onAddArgument: _addArgument,
                      onRemoveArgument: _removeArgument,
                    ),
                    _EditorTarget.spawnSh => _ShellCommandEditor(
                      controller: _shellCommand,
                      enabled: !widget.busy,
                      onChanged: _scheduleValidation,
                    ),
                  },
                  const SizedBox(height: 12),
                  _ValidationMessage(
                    validating: _validating,
                    validation: _validation,
                    failure: _validationFailure,
                  ),
                  if (widget.nativeError case final error?) ...[
                    const SizedBox(height: 14),
                    _EditorErrorMessage(error: error),
                  ],
                ],
              ),
            ),
          ),
        ),
        const SettingsHairline(),
        _EditorFooter(
          canSave: !widget.busy && _validation?.isValid == true,
          saving: widget.busy && !widget.deleteBusy,
          deleting: widget.deleteBusy,
          showDelete: widget.binding != null,
          onDelete: widget.busy ? null : widget.onDelete,
          onCancel: widget.busy ? null : widget.onClose,
          onSave: () => unawaited(_save()),
        ),
      ],
    );
  }

  Widget _buildActionCatalog() {
    return _CatalogLayout(
      key: const ValueKey<String>('shortcut-editor-actions'),
      title: context.l10n.settingsShortcutEditorChooseAction,
      searchController: _catalogSearch,
      onSearchChanged: _filterCatalog,
      onBack: _closeCatalog,
      empty: _visibleActions.isEmpty,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        itemCount: _visibleActions.length,
        separatorBuilder: (_, _) => const SizedBox(height: 5),
        itemBuilder: (context, index) {
          final action = _visibleActions[index];
          return _ActionCatalogRow(
            key: ValueKey<DenialShortcutAction>(action),
            action: action,
            selected: action == _action,
            onPressed: () => _selectAction(action),
          );
        },
      ),
    );
  }

  DesktopApp? get _selectedApplication {
    final desktopFileId = _selectedDesktopFileId;
    if (desktopFileId == null) {
      return null;
    }
    for (final application in widget.applications) {
      if (application.id == desktopFileId) {
        return application;
      }
    }
    return null;
  }

  Widget _buildApplicationCatalog() {
    return _CatalogLayout(
      key: const ValueKey<String>('shortcut-editor-applications'),
      title: context.l10n.settingsShortcutEditorChooseApplication,
      searchController: _catalogSearch,
      onSearchChanged: _filterCatalog,
      onBack: _closeCatalog,
      empty: _visibleApplications.isEmpty,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        itemCount: _visibleApplications.length,
        separatorBuilder: (_, _) => const SizedBox(height: 5),
        itemBuilder: (context, index) {
          final application = _visibleApplications[index];
          return _ApplicationCatalogRow(
            key: ValueKey<String>(application.id),
            application: application,
            selected: application.id == _selectedDesktopFileId,
            onPressed: () => _selectApplication(application),
          );
        },
      ),
    );
  }

  Widget _buildInputCatalog() {
    return _CatalogLayout(
      key: const ValueKey<String>('shortcut-editor-inputs'),
      title: context.l10n.settingsShortcutEditorSupportedInputs,
      searchController: _catalogSearch,
      onSearchChanged: _filterCatalog,
      onBack: _closeCatalog,
      header: _ShortcutDraftPreview(text: _shortcut.text),
      footer: Align(
        alignment: Alignment.centerRight,
        child: SettingsTextButton(
          label: context.l10n.settingsShortcutEditorDone,
          onPressed: _closeCatalog,
        ),
      ),
      empty: _visibleInputs.isEmpty,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        itemCount: _visibleInputs.length,
        separatorBuilder: (_, _) => const SizedBox(height: 5),
        itemBuilder: (context, index) {
          final input = _visibleInputs[index];
          return _InputCatalogRow(
            key: ValueKey<String>(input.canonical),
            input: input,
            onPressed: () => _insertInput(input),
          );
        },
      ),
    );
  }
}

class _EditorSurface extends StatelessWidget {
  const _EditorSurface({
    required this.title,
    required this.busy,
    required this.onClose,
    required this.child,
  });

  final String title;
  final bool busy;
  final VoidCallback onClose;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final accent = ShellTheme.of(context).accent;
    // Modal surfaces share the panel/bubble radius so the editor matches the
    // accent picker and other overlays (§2: extraLarge).
    final radius = context.shellTheme.borderRadius(ShellShapeScale.extraLarge);
    // Tonal surface + hairline instead of Material elevation (§1.2).
    return ClipRRect(
      borderRadius: radius,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.shellTheme.cardColor(
            context.shellColors.surfaceContainerHigh,
          ),
          borderRadius: radius,
          border: Border.all(color: accent.withAlpha(86)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 10, 12),
              child: Row(
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: accent.withAlpha(32),
                      shape: BoxShape.circle,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(
                        Icons.keyboard_command_key_rounded,
                        color: accent,
                        size: 19,
                      ),
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ShellText.settingsRowTitle,
                    ),
                  ),
                  SettingsIconButton(
                    icon: Icons.close_rounded,
                    semanticsLabel:
                        context.l10n.settingsShortcutEditorCancel,
                    onPressed: busy ? null : onClose,
                  ),
                ],
              ),
            ),
            const SettingsHairline(),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

class _ShortcutTextField extends StatelessWidget {
  const _ShortcutTextField({
    required this.controller,
    required this.enabled,
    required this.onChanged,
  });

  final TextEditingController controller;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SettingsTextField(
      controller: controller,
      enabled: enabled,
      autofocus: true,
      monospace: true,
      label: context.l10n.settingsShortcutEditorShortcutLabel,
      hint: context.l10n.settingsShortcutEditorShortcutHint,
      helperText: context.l10n.settingsShortcutEditorShortcutExample,
      helperMaxLines: 2,
      onChanged: onChanged,
    );
  }
}

class _EditorFieldLabel extends StatelessWidget {
  const _EditorFieldLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: ShellText.cardTitle.copyWith(
        color: context.shellColors.textSecondary,
      ),
    );
  }
}

class _TargetSelectionField extends StatelessWidget {
  const _TargetSelectionField({
    required this.target,
    required this.enabled,
    required this.onSelected,
  });

  final _EditorTarget target;
  final bool enabled;
  final ValueChanged<_EditorTarget> onSelected;

  @override
  Widget build(BuildContext context) {
    return SettingsSegmentedControl<_EditorTarget>(
      value: target,
      enabled: enabled,
      choices: <SettingsChoice<_EditorTarget>>[
        SettingsChoice(
          _EditorTarget.denialAction,
          context.l10n.settingsShortcutEditorTargetAction,
          icon: Icons.auto_awesome_rounded,
        ),
        SettingsChoice(
          _EditorTarget.application,
          context.l10n.settingsShortcutEditorTargetApplication,
          icon: Icons.apps_rounded,
        ),
        SettingsChoice(
          _EditorTarget.spawn,
          context.l10n.settingsShortcutEditorTargetProgram,
          icon: Icons.terminal_rounded,
        ),
        SettingsChoice(
          _EditorTarget.spawnSh,
          context.l10n.settingsShortcutEditorTargetShell,
          icon: Icons.code_rounded,
        ),
      ],
      onChanged: onSelected,
    );
  }
}

class _ApplicationSelectionField extends StatelessWidget {
  const _ApplicationSelectionField({
    required this.application,
    required this.desktopFileId,
    required this.enabled,
    required this.onPressed,
  });

  final DesktopApp? application;
  final String? desktopFileId;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final application = this.application;
    final label =
        application?.name ??
        desktopFileId ??
        context.l10n.settingsShortcutEditorChooseApplication;
    final identity = application?.id ?? desktopFileId;
    return _SelectionTile(
      enabled: enabled,
      onPressed: onPressed,
      leading: SizedBox.square(
        dimension: 28,
        child: application == null
            ? Icon(
                desktopFileId == null
                    ? Icons.apps_rounded
                    : Icons.app_blocking_rounded,
                color: context.shellColors.textTertiary,
                size: 21,
              )
            : DeferredAppIcon(iconPath: application.iconPath),
      ),
      title: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: ShellText.cardTitle.copyWith(
          color: context.shellColors.textPrimary,
        ),
      ),
      subtitle: identity == null
          ? null
          : Text(
              identity,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ShellText.settingsBadgeLabel.copyWith(
                color: context.shellColors.textSecondary,
                fontFamily: ShellText.systemBarFontFamily,
              ),
            ),
    );
  }
}

/// Full-width tonal tile hosting a [SettingsRow] — the shared shape for the
/// editor's "choose …" fields (`medium` radius, hairline, `unfold_more`
/// affordance). Replaces the previous Material `OutlinedButton` composites.
class _SelectionTile extends StatelessWidget {
  const _SelectionTile({
    required this.leading,
    required this.title,
    required this.enabled,
    required this.onPressed,
    this.subtitle,
  });

  final Widget leading;
  final Widget title;
  final Widget? subtitle;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = ShellTheme.of(context);
    final radius = theme.borderRadius(ShellShapeScale.medium);
    return ClipRRect(
      borderRadius: radius,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.shellColors.surfaceContainerHighest,
          borderRadius: radius,
          border: Border.all(color: context.shellColors.hairline),
        ),
        child: SettingsRow(
          leading: leading,
          title: title,
          subtitle: subtitle,
          trailing: Icon(
            Icons.unfold_more_rounded,
            size: 18,
            color: context.shellColors.textTertiary,
          ),
          enabled: enabled,
          onTap: enabled ? onPressed : null,
          padding: const EdgeInsets.symmetric(
            horizontal: ShellSpacing.lg,
          ),
        ),
      ),
    );
  }
}

class _DirectCommandEditor extends StatelessWidget {
  const _DirectCommandEditor({
    required this.program,
    required this.arguments,
    required this.enabled,
    required this.onChanged,
    required this.onAddArgument,
    required this.onRemoveArgument,
  });

  final TextEditingController program;
  final List<TextEditingController> arguments;
  final bool enabled;
  final VoidCallback onChanged;
  final VoidCallback onAddArgument;
  final ValueChanged<int> onRemoveArgument;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.l10n.settingsShortcutEditorProgramDescription,
          style: ShellText.settingsRowSupport.copyWith(
            color: context.shellColors.textSecondary,
          ),
        ),
        const SizedBox(height: 10),
        _CommandTextField(
          controller: program,
          enabled: enabled,
          label: context.l10n.settingsShortcutEditorProgramLabel,
          hint: context.l10n.settingsShortcutEditorProgramHint,
          onChanged: onChanged,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _EditorFieldLabel(
                label: context.l10n.settingsShortcutEditorArgumentsLabel,
              ),
            ),
            SettingsTextButton(
              label: context.l10n.settingsShortcutEditorAddArgument,
              onPressed: enabled ? onAddArgument : null,
            ),
          ],
        ),
        if (arguments.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              context.l10n.settingsShortcutEditorNoArguments,
              style: ShellText.settingsRowSupport.copyWith(
                color: context.shellColors.textSecondary,
              ),
            ),
          )
        else
          for (var index = 0; index < arguments.length; index++) ...[
            const SizedBox(height: 8),
            Row(
              key: ValueKey<TextEditingController>(arguments[index]),
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: _CommandTextField(
                    controller: arguments[index],
                    enabled: enabled,
                    label: context.l10n.settingsShortcutEditorArgumentLabel(
                      index + 1,
                    ),
                    hint: context.l10n.settingsShortcutEditorArgumentHint,
                    onChanged: onChanged,
                  ),
                ),
                const SizedBox(width: 6),
                SettingsIconButton(
                  icon: Icons.remove_circle_outline_rounded,
                  semanticsLabel:
                      context.l10n.settingsShortcutEditorRemoveArgument(
                        index + 1,
                      ),
                  onPressed: enabled ? () => onRemoveArgument(index) : null,
                ),
              ],
            ),
          ],
      ],
    );
  }
}

class _ShellCommandEditor extends StatelessWidget {
  const _ShellCommandEditor({
    required this.controller,
    required this.enabled,
    required this.onChanged,
  });

  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.l10n.settingsShortcutEditorShellDescription,
          style: ShellText.settingsRowSupport.copyWith(
            color: context.shellColors.textSecondary,
          ),
        ),
        const SizedBox(height: 10),
        _CommandTextField(
          controller: controller,
          enabled: enabled,
          label: context.l10n.settingsShortcutEditorShellCommandLabel,
          hint: context.l10n.settingsShortcutEditorShellCommandHint,
          minLines: 2,
          maxLines: 4,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _CommandTextField extends StatelessWidget {
  const _CommandTextField({
    required this.controller,
    required this.enabled,
    required this.label,
    required this.hint,
    required this.onChanged,
    this.minLines = 1,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final bool enabled;
  final String label;
  final String hint;
  final VoidCallback onChanged;
  final int minLines;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return SettingsTextField(
      controller: controller,
      enabled: enabled,
      monospace: true,
      minLines: minLines,
      maxLines: maxLines,
      label: label,
      hint: hint,
      onChanged: (_) => onChanged(),
    );
  }
}

class _ActionSelectionField extends StatelessWidget {
  const _ActionSelectionField({
    required this.action,
    required this.enabled,
    required this.onPressed,
  });

  final DenialShortcutAction action;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final accent = ShellTheme.of(context).accent;
    return _SelectionTile(
      enabled: enabled,
      onPressed: onPressed,
      leading: Icon(
        settingsShortcutActionIcon(action),
        color: accent,
        size: 19,
      ),
      title: Text(
        settingsShortcutActionLabel(context, action),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: ShellText.cardTitle.copyWith(
          color: context.shellColors.textPrimary,
        ),
      ),
    );
  }
}

class _ValidationMessage extends StatelessWidget {
  const _ValidationMessage({
    required this.validating,
    required this.validation,
    required this.failure,
  });

  final bool validating;
  final DenialShortcutValidation? validation;
  final String? failure;

  @override
  Widget build(BuildContext context) {
    if (validating) {
      return _ValidationLine(
        color: context.shellColors.textTertiary,
        icon: Icons.sync_rounded,
        message: context.l10n.settingsShortcutEditorValidating,
        progress: true,
      );
    }
    if (failure case final failure?) {
      return _ValidationLine(
        color: context.shellColors.performanceBad,
        icon: Icons.error_outline_rounded,
        message: failure,
      );
    }
    final validation = this.validation;
    if (validation == null) {
      return const SizedBox.shrink();
    }
    return switch (validation.kind) {
      DenialShortcutValidationKind.valid => _ValidationLine(
        color: context.shellColors.performanceGood,
        icon: Icons.check_circle_outline_rounded,
        message: context.l10n.settingsShortcutEditorValid(
          settingsShortcutDisplay(context, validation.canonical!),
        ),
      ),
      DenialShortcutValidationKind.conflict => _ValidationLine(
        color: context.shellColors.performanceWarning,
        icon: Icons.warning_amber_rounded,
        message: context.l10n.settingsShortcutEditorConflict(
          settingsShortcutDisplay(context, validation.canonical!),
          settingsShortcutTargetLabel(context, validation.conflict!),
        ),
      ),
      DenialShortcutValidationKind.invalid => _ValidationLine(
        color: context.shellColors.performanceWarning,
        icon: Icons.warning_amber_rounded,
        message: validation.error!,
      ),
    };
  }
}

class _ValidationLine extends StatelessWidget {
  const _ValidationLine({
    required this.color,
    required this.icon,
    required this.message,
    this.progress = false,
  });

  final Color color;
  final IconData icon;
  final String message;
  final bool progress;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (progress)
            const Padding(
              padding: EdgeInsets.only(top: 1),
              child: SizedBox.square(
                dimension: 15,
                child: FittedBox(
                  child: SizedBox.square(
                    dimension: settingsLoadingIndicatorSize,
                    child: SettingsLoadingIndicator(),
                  ),
                ),
              ),
            )
          else
            Icon(icon, color: color, size: 17),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: ShellText.settingsRowSupport.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _EditorErrorMessage extends StatelessWidget {
  const _EditorErrorMessage({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.shellColors.performanceBad.withAlpha(18),
        borderRadius: context.shellTheme.borderRadius(ShellShapeScale.medium),
        border: Border.all(
          color: context.shellColors.performanceBad.withAlpha(82),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(11),
        child: Text(
          error,
          style: ShellText.settingsRowSupport.copyWith(
            color: context.shellColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _EditorFooter extends StatelessWidget {
  const _EditorFooter({
    required this.canSave,
    required this.saving,
    required this.deleting,
    required this.showDelete,
    required this.onDelete,
    required this.onCancel,
    required this.onSave,
  });

  final bool canSave;
  final bool saving;
  final bool deleting;
  final bool showDelete;
  final Future<bool> Function()? onDelete;
  final VoidCallback? onCancel;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: Row(
        children: [
          if (showDelete)
            _EditorButton(
              label: context.l10n.settingsShortcutEditorDelete,
              icon: Icons.delete_outline_rounded,
              destructive: true,
              busy: deleting,
              onPressed: onDelete == null
                  ? null
                  : () => unawaited(onDelete!.call()),
            ),
          const Spacer(),
          _EditorButton(
            label: context.l10n.settingsShortcutEditorCancel,
            onPressed: onCancel,
          ),
          const SizedBox(width: 8),
          _EditorButton(
            label: saving
                ? context.l10n.settingsShortcutEditorSaving
                : context.l10n.settingsShortcutEditorSave,
            icon: Icons.check_rounded,
            primary: true,
            busy: saving,
            onPressed: canSave ? onSave : null,
          ),
        ],
      ),
    );
  }
}

class _EditorButton extends StatelessWidget {
  const _EditorButton({
    required this.label,
    this.icon,
    this.primary = false,
    this.destructive = false,
    this.busy = false,
    this.onPressed,
  });

  final String label;
  final IconData? icon;
  final bool primary;
  final bool destructive;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SettingsButton(
      label: label,
      variant: primary
          ? SettingsButtonVariant.filledTonal
          : SettingsButtonVariant.outlined,
      destructive: destructive,
      icon: busy ? null : icon,
      leading: busy ? const _EditorBusyIndicator() : null,
      onPressed: busy ? null : onPressed,
    );
  }
}

/// 16dp rendition of the morphing M3E indicator used inside busy buttons.
class _EditorBusyIndicator extends StatelessWidget {
  const _EditorBusyIndicator();

  @override
  Widget build(BuildContext context) {
    return const SizedBox.square(
      dimension: 16,
      child: FittedBox(
        child: SizedBox.square(
          dimension: settingsLoadingIndicatorSize,
          child: SettingsLoadingIndicator(),
        ),
      ),
    );
  }
}

class _CatalogLayout extends StatelessWidget {
  const _CatalogLayout({
    required this.title,
    required this.searchController,
    required this.onSearchChanged,
    required this.onBack,
    required this.empty,
    required this.child,
    this.header,
    this.footer,
    super.key,
  });

  final String title;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onBack;
  final bool empty;
  final Widget child;
  final Widget? header;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
          child: Row(
            children: [
              SettingsIconButton(
                icon: Icons.arrow_back_rounded,
                semanticsLabel: context.l10n.settingsShortcutEditorBack,
                onPressed: onBack,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: ShellText.settingsRowTitle,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          child: SettingsTextField(
            controller: searchController,
            autofocus: true,
            hint: context.l10n.settingsShortcutEditorSearch,
            prefixIcon: const Icon(Icons.search_rounded, size: 19),
            onChanged: onSearchChanged,
          ),
        ),
        if (header case final header?) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: header,
          ),
        ],
        Expanded(
          child: empty
              ? Center(
                  child: Text(
                    context.l10n.settingsShortcutEditorNoResults,
                    style: ShellText.base.copyWith(
                      color: context.shellColors.textTertiary,
                    ),
                  ),
                )
              : child,
        ),
        if (footer case final footer?) ...[
          const SettingsHairline(),
          Padding(padding: const EdgeInsets.all(12), child: footer),
        ],
      ],
    );
  }
}

class _ShortcutDraftPreview extends StatelessWidget {
  const _ShortcutDraftPreview({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final accent = ShellTheme.of(context).accent;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: accent.withAlpha(22),
        borderRadius: context.shellTheme.borderRadius(ShellShapeScale.medium),
        border: Border.all(color: accent.withAlpha(70)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        child: Row(
          children: [
            Icon(Icons.keyboard_command_key_rounded, size: 16, color: accent),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                text.isEmpty
                    ? context.l10n.settingsShortcutEditorShortcutHint
                    : text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ShellText.cardTitle.copyWith(
                  color: text.isEmpty
                      ? context.shellColors.textTertiary
                      : context.shellColors.textPrimary,
                  fontFamily: ShellText.systemBarFontFamily,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionCatalogRow extends StatelessWidget {
  const _ActionCatalogRow({
    required this.action,
    required this.selected,
    required this.onPressed,
    super.key,
  });

  final DenialShortcutAction action;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = ShellTheme.of(context).accentPalette;
    final foreground = selected
        ? palette.onContainer
        : context.shellColors.textPrimary;
    return SettingsRow(
      selected: selected,
      leading: Icon(
        settingsShortcutActionIcon(action),
        size: 20,
        color: selected
            ? foreground
            : context.shellColors.textTertiary,
      ),
      title: Text(
        settingsShortcutActionLabel(context, action),
        style: ShellText.cardTitle.copyWith(color: foreground),
      ),
      trailing: selected
          ? Icon(Icons.check_rounded, size: 18, color: foreground)
          : null,
      onTap: onPressed,
      padding: const EdgeInsets.symmetric(horizontal: ShellSpacing.lg),
    );
  }
}

class _ApplicationCatalogRow extends StatelessWidget {
  const _ApplicationCatalogRow({
    required this.application,
    required this.selected,
    required this.onPressed,
    super.key,
  });

  final DesktopApp application;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = ShellTheme.of(context).accentPalette;
    final foreground = selected
        ? palette.onContainer
        : context.shellColors.textPrimary;
    return SettingsRow(
      selected: selected,
      leading: SizedBox.square(
        dimension: 30,
        child: DeferredAppIcon(iconPath: application.iconPath),
      ),
      title: Text(
        application.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: ShellText.cardTitle.copyWith(color: foreground),
      ),
      subtitle: Text(
        application.id,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: ShellText.settingsBadgeLabel.copyWith(
          color: selected
              ? foreground.withAlpha(170)
              : context.shellColors.textSecondary,
          fontFamily: ShellText.systemBarFontFamily,
        ),
      ),
      trailing: selected
          ? Icon(Icons.check_rounded, size: 18, color: foreground)
          : null,
      onTap: onPressed,
      padding: const EdgeInsets.symmetric(horizontal: ShellSpacing.lg),
    );
  }
}

class _InputCatalogRow extends StatelessWidget {
  const _InputCatalogRow({
    required this.input,
    required this.onPressed,
    super.key,
  });

  final DenialShortcutInput input;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final aliases = input.aliases.join(', ');
    return SettingsRow(
      leading: Icon(
        input.kind == DenialShortcutInputKind.gesture
            ? Icons.gesture_rounded
            : Icons.keyboard_rounded,
        size: 20,
        color: context.shellColors.textTertiary,
      ),
      title: Text(
        input.canonical,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: ShellText.cardTitle.copyWith(
          color: context.shellColors.textPrimary,
          fontFamily: ShellText.systemBarFontFamily,
        ),
      ),
      subtitle: aliases.isEmpty
          ? null
          : Text(
              aliases,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ShellText.settingsRowSupport.copyWith(
                color: context.shellColors.textSecondary,
              ),
            ),
      trailing: Text(
        settingsShortcutInputCategoryLabel(context, input.category),
        style: ShellText.settingsBadgeLabel.copyWith(
          color: context.shellColors.textSecondary,
        ),
      ),
      onTap: onPressed,
      padding: const EdgeInsets.symmetric(horizontal: ShellSpacing.lg),
    );
  }
}
