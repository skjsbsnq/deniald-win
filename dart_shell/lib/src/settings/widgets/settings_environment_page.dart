import 'dart:convert' show utf8;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../launcher/models/desktop_app.dart';
import '../../localization/denial_localizations.dart';
import '../../theme/motion.dart';
import '../../theme/shell_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/shell_cursor.dart';
import '../shell_settings.dart';
import 'settings_controls.dart';
import 'settings_loading_indicator.dart';

const settingsEnvironmentNameFieldKey = ValueKey<String>(
  'settings-environment-name-field',
);
const settingsEnvironmentValueFieldKey = ValueKey<String>(
  'settings-environment-value-field',
);
const settingsEnvironmentModeControlKey = ValueKey<String>(
  'settings-environment-mode-control',
);
const settingsEnvironmentSaveButtonKey = ValueKey<String>(
  'settings-environment-save-button',
);
const settingsEnvironmentAllApplicationsScopeKey = ValueKey<String>(
  'settings-environment-all-applications-scope',
);
const settingsEnvironmentBackToApplicationsKey = ValueKey<String>(
  'settings-environment-back-to-applications',
);

ValueKey<String> settingsEnvironmentApplicationScopeKey(String desktopFileId) =>
    ValueKey<String>('settings-environment-application-$desktopFileId');

typedef ApplicationEnvironmentSave =
    void Function(
      String? desktopFileId,
      String? previousName,
      String name,
      String? value,
    );
typedef ApplicationEnvironmentDelete =
    void Function(String? desktopFileId, String name);

enum _EnvironmentOverrideMode { add, hide }

class SettingsEnvironmentPage extends StatefulWidget {
  const SettingsEnvironmentPage({
    required this.settings,
    required this.onSave,
    required this.onDelete,
    required this.onReset,
    required this.onResetScope,
    this.applications = const <DesktopApp>[],
    this.applicationsLoading = false,
    this.applicationsUnavailable = false,
    super.key,
  });

  final ShellApplicationEnvironmentSettings settings;
  final List<DesktopApp> applications;
  final bool applicationsLoading;
  final bool applicationsUnavailable;
  final ApplicationEnvironmentSave onSave;
  final ApplicationEnvironmentDelete onDelete;
  final VoidCallback onReset;
  final ValueChanged<String?> onResetScope;

  @override
  State<SettingsEnvironmentPage> createState() =>
      _SettingsEnvironmentPageState();
}

class _SettingsEnvironmentPageState extends State<SettingsEnvironmentPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _valueController;
  late final FocusNode _nameFocus;
  late final FocusNode _valueFocus;
  late final TextEditingController _applicationSearchController;
  String? _editingName;
  String? _selectedDesktopFileId;
  var _mode = _EnvironmentOverrideMode.add;
  var _narrowDetailOpen = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _valueController = TextEditingController();
    _nameFocus = FocusNode();
    _valueFocus = FocusNode();
    _applicationSearchController = TextEditingController();
  }

  @override
  void dispose() {
    _nameFocus.dispose();
    _valueFocus.dispose();
    _applicationSearchController.dispose();
    _nameController.dispose();
    _valueController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SettingsPageLayout(
      icon: Icons.terminal_rounded,
      eyebrow: l10n.settingsEnvironmentSection,
      title: l10n.settingsEnvironmentTitle,
      onReset:
          widget.settings.variables.isEmpty &&
              widget.settings.applications.isEmpty
          ? null
          : widget.onReset,
      children: [
        _ScopeCard(description: l10n.settingsEnvironmentScopeDescription),
        _buildWorkspace(context),
      ],
    );
  }

  Widget _buildWorkspace(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 640;
        final scopes = _EnvironmentApplicationScopeList(
          applications: widget.applications,
          settings: widget.settings,
          selectedDesktopFileId: _selectedDesktopFileId,
          searchController: _applicationSearchController,
          loading: widget.applicationsLoading,
          unavailable: widget.applicationsUnavailable,
          onSearchChanged: (_) => setState(() {}),
          onSelected: (desktopFileId) =>
              _selectScope(desktopFileId, openNarrowDetail: narrow),
        );
        final detail = _buildScopeDetail(context, narrow: narrow);
        if (narrow) {
          return AnimatedSwitcher(
            duration: Motion.tile,
            child: _narrowDetailOpen
                ? KeyedSubtree(
                    key: ValueKey<String?>(_selectedDesktopFileId),
                    child: detail,
                  )
                : KeyedSubtree(
                    key: const ValueKey<String>('application-scope-list'),
                    child: scopes,
                  ),
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 252, child: scopes),
            const SizedBox(width: 12),
            Expanded(child: detail),
          ],
        );
      },
    );
  }

  Widget _buildScopeDetail(BuildContext context, {required bool narrow}) {
    final variables = widget.settings.variablesFor(_selectedDesktopFileId);
    final application = _selectedApplication;
    return Column(
      children: [
        _EnvironmentScopeHeader(
          application: application,
          unavailableDesktopFileId: application == null
              ? _selectedDesktopFileId
              : null,
          inheritedCount: widget.settings.variables.length,
          scopeOverrideCount: variables.length,
          showBack: narrow,
          onBack: () => setState(() => _narrowDetailOpen = false),
          onClear: variables.isEmpty
              ? null
              : () {
                  widget.onResetScope(_selectedDesktopFileId);
                  _clearEditor();
                },
        ),
        const SizedBox(height: 12),
        _buildEditorCard(context),
        const SizedBox(height: 12),
        _VariablesCard(
          variables: variables,
          defaultVariables: widget.settings.variables,
          perApplication: _selectedDesktopFileId != null,
          onEdit: _edit,
          onDelete: _delete,
        ),
      ],
    );
  }

  DesktopApp? get _selectedApplication {
    final selected = _selectedDesktopFileId;
    if (selected == null) {
      return null;
    }
    for (final application in widget.applications) {
      if (application.id == selected) {
        return application;
      }
    }
    return null;
  }

  Widget _buildEditorCard(BuildContext context) {
    final l10n = context.l10n;
    return SettingsCardGroup(
      children: [
        SettingsSection(
          title: _editingName == null
              ? l10n.settingsEnvironmentEditorTitle
              : l10n.settingsEnvironmentEditorEditTitle(_editingName!),
          child: Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: FocusTraversalGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    key: settingsEnvironmentModeControlKey,
                    container: true,
                    explicitChildNodes: true,
                    child: SettingsSegmentedControl<_EnvironmentOverrideMode>(
                      value: _mode,
                      choices: [
                        SettingsChoice(
                          _EnvironmentOverrideMode.add,
                          l10n.settingsEnvironmentModeAdd,
                        ),
                        SettingsChoice(
                          _EnvironmentOverrideMode.hide,
                          l10n.settingsEnvironmentModeHide,
                        ),
                      ],
                      onChanged: _setMode,
                    ),
                  ),
                  const SizedBox(height: 12),
                  AnimatedSwitcher(
                    duration: Motion.tile,
                    child: Text(
                      key: ValueKey<_EnvironmentOverrideMode>(_mode),
                      _mode == _EnvironmentOverrideMode.add
                          ? l10n.settingsEnvironmentAddModeDescription
                          : l10n.settingsEnvironmentHideModeDescription,
                      style: ShellText.settingsRowSupport.copyWith(
                        color: context.shellColors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildFields(context),
                  const SizedBox(height: 12),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      KeyedSubtree(
                        key: settingsEnvironmentSaveButtonKey,
                        child: SettingsTextButton(
                          label: _editingName != null
                              ? l10n.settingsEnvironmentUpdate
                              : _mode == _EnvironmentOverrideMode.add
                              ? l10n.settingsEnvironmentAdd
                              : l10n.settingsEnvironmentHide,
                          onPressed: _save,
                        ),
                      ),
                      if (_editingName != null)
                        SettingsTextButton(
                          label: l10n.settingsEnvironmentCancel,
                          onPressed: _clearEditor,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFields(BuildContext context) {
    final nameField = _EnvironmentTextField(
      key: settingsEnvironmentNameFieldKey,
      controller: _nameController,
      focusNode: _nameFocus,
      readOnly: _editingName != null,
      label: context.l10n.settingsEnvironmentNameLabel,
      hint: context.l10n.settingsEnvironmentNameHint,
      validator: _validateName,
      inputAction: _mode == _EnvironmentOverrideMode.add
          ? TextInputAction.next
          : TextInputAction.done,
      onSubmitted: _mode == _EnvironmentOverrideMode.hide ? _save : null,
    );
    if (_mode == _EnvironmentOverrideMode.hide) {
      return nameField;
    }
    final valueField = _EnvironmentTextField(
      key: settingsEnvironmentValueFieldKey,
      controller: _valueController,
      focusNode: _valueFocus,
      label: context.l10n.settingsEnvironmentValueLabel,
      hint: context.l10n.settingsEnvironmentValueHint,
      validator: _validateValue,
      inputAction: TextInputAction.done,
      onSubmitted: _save,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 520) {
          return Column(
            children: [nameField, const SizedBox(height: 10), valueField],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: nameField),
            const SizedBox(width: 10),
            Expanded(child: valueField),
          ],
        );
      },
    );
  }

  void _setMode(_EnvironmentOverrideMode mode) {
    if (_mode == mode) {
      return;
    }
    setState(() => _mode = mode);
    _formKey.currentState?.validate();
  }

  String? _validateName(String? input) {
    final l10n = context.l10n;
    final name = input?.trim() ?? '';
    if (name.isEmpty) {
      return l10n.settingsEnvironmentNameRequired;
    }
    if (!isValidApplicationEnvironmentVariableName(name)) {
      return l10n.settingsEnvironmentNameInvalid;
    }
    if (name != _editingName &&
        widget.settings
            .variablesFor(_selectedDesktopFileId)
            .containsKey(name)) {
      return l10n.settingsEnvironmentNameDuplicate;
    }
    return null;
  }

  String? _validateValue(String? input) {
    if (_mode == _EnvironmentOverrideMode.hide) {
      return null;
    }
    final value = input ?? '';
    if (value.contains('\u0000')) {
      return context.l10n.settingsEnvironmentValueNul;
    }
    if (utf8.encode(value).length > applicationEnvironmentMaximumValueBytes) {
      return context.l10n.settingsEnvironmentValueTooLong;
    }
    return null;
  }

  void _save([String? _]) {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    widget.onSave(
      _selectedDesktopFileId,
      _editingName,
      _nameController.text.trim(),
      _mode == _EnvironmentOverrideMode.hide ? null : _valueController.text,
    );
    _clearEditor();
  }

  void _edit(String name) {
    final value = widget.settings.variablesFor(_selectedDesktopFileId)[name];
    setState(() {
      _editingName = name;
      _nameController.text = name;
      _valueController.text = value ?? '';
      _mode = value == null
          ? _EnvironmentOverrideMode.hide
          : _EnvironmentOverrideMode.add;
    });
    if (value == null) {
      _nameFocus.requestFocus();
    } else {
      _valueFocus.requestFocus();
    }
  }

  void _delete(String name) {
    widget.onDelete(_selectedDesktopFileId, name);
    if (_editingName == name) {
      _clearEditor();
    }
  }

  void _clearEditor() {
    _formKey.currentState?.reset();
    setState(() {
      _editingName = null;
      _nameController.clear();
      _valueController.clear();
      _mode = _EnvironmentOverrideMode.add;
    });
    _nameFocus.requestFocus();
  }

  void _selectScope(String? desktopFileId, {required bool openNarrowDetail}) {
    _formKey.currentState?.reset();
    setState(() {
      _selectedDesktopFileId = desktopFileId;
      _editingName = null;
      _nameController.clear();
      _valueController.clear();
      _mode = _EnvironmentOverrideMode.add;
      if (openNarrowDetail) {
        _narrowDetailOpen = true;
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _nameFocus.requestFocus();
      }
    });
  }
}

class _EnvironmentApplicationScopeList extends StatelessWidget {
  const _EnvironmentApplicationScopeList({
    required this.applications,
    required this.settings,
    required this.selectedDesktopFileId,
    required this.searchController,
    required this.loading,
    required this.unavailable,
    required this.onSearchChanged,
    required this.onSelected,
  });

  final List<DesktopApp> applications;
  final ShellApplicationEnvironmentSettings settings;
  final String? selectedDesktopFileId;
  final TextEditingController searchController;
  final bool loading;
  final bool unavailable;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final installed = <String, DesktopApp>{
      for (final application in applications) application.id: application,
    };
    final query = searchController.text.trim().toLowerCase();
    final entries =
        <_EnvironmentApplicationEntry>[
          for (final application in applications)
            if (_matches(application.name, application.id, query))
              _EnvironmentApplicationEntry(
                desktopFileId: application.id,
                application: application,
                overrideCount:
                    settings.applications[application.id]?.length ?? 0,
              ),
          for (final desktopFileId in settings.applications.keys)
            if (!installed.containsKey(desktopFileId) &&
                _matches(
                  context.l10n.settingsEnvironmentUnavailableApplication,
                  desktopFileId,
                  query,
                ))
              _EnvironmentApplicationEntry(
                desktopFileId: desktopFileId,
                overrideCount: settings.applications[desktopFileId]!.length,
              ),
        ]..sort((first, second) {
          final configured = (second.overrideCount > 0 ? 1 : 0).compareTo(
            first.overrideCount > 0 ? 1 : 0,
          );
          if (configured != 0) {
            return configured;
          }
          return first
              .label(context)
              .toLowerCase()
              .compareTo(second.label(context).toLowerCase());
        });

    return SettingsCardGroup(
      children: [
        SettingsSection(
          title: context.l10n.settingsEnvironmentApplicationsTitle,
          child: Column(
            children: [
              TextField(
                controller: searchController,
                onChanged: onSearchChanged,
                autocorrect: false,
                enableSuggestions: false,
                style: ShellText.base.copyWith(
                  color: context.shellColors.textPrimary,
                  fontFamily: ShellText.systemBarFontFamily,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search_rounded, size: 17),
                  hintText:
                      context.l10n.settingsEnvironmentApplicationSearchHint,
                  hintStyle: ShellText.settingsRowSupport.copyWith(
                    color: context.shellColors.textTertiary,
                  ),
                  filled: true,
                  fillColor: context.shellColors.surfaceContainerHigh,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: context.shellTheme.borderRadius(
                      ShellShapeScale.full,
                    ),
                    borderSide: BorderSide(color: context.shellColors.hairline),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 500,
                child: ListView.builder(
                  itemCount: entries.length + 2,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return _EnvironmentScopeTile(
                        key: settingsEnvironmentAllApplicationsScopeKey,
                        selected: selectedDesktopFileId == null,
                        label: context.l10n.settingsEnvironmentAllApplications,
                        desktopFileId: context
                            .l10n
                            .settingsEnvironmentAllApplicationsDescription,
                        overrideCount: settings.variables.length,
                        onPressed: () => onSelected(null),
                      );
                    }
                    if (index <= entries.length) {
                      final entry = entries[index - 1];
                      return _EnvironmentScopeTile(
                        key: settingsEnvironmentApplicationScopeKey(
                          entry.desktopFileId,
                        ),
                        selected: selectedDesktopFileId == entry.desktopFileId,
                        label: entry.label(context),
                        desktopFileId: entry.desktopFileId,
                        overrideCount: entry.overrideCount,
                        iconPath: entry.application?.iconPath,
                        unavailable: entry.application == null,
                        onPressed: () => onSelected(entry.desktopFileId),
                      );
                    }
                    if (loading) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 18),
                        child: Center(child: SettingsLoadingIndicator()),
                      );
                    }
                    if (unavailable) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Text(
                          context
                              .l10n
                              .settingsEnvironmentApplicationsUnavailable,
                          textAlign: TextAlign.center,
                          style: ShellText.settingsRowSupport.copyWith(
                            color: context.shellColors.textSecondary,
                          ),
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  bool _matches(String label, String desktopFileId, String query) {
    return query.isEmpty ||
        label.toLowerCase().contains(query) ||
        desktopFileId.toLowerCase().contains(query);
  }
}

class _EnvironmentApplicationEntry {
  const _EnvironmentApplicationEntry({
    required this.desktopFileId,
    required this.overrideCount,
    this.application,
  });

  final String desktopFileId;
  final int overrideCount;
  final DesktopApp? application;

  String label(BuildContext context) =>
      application?.name ??
      context.l10n.settingsEnvironmentUnavailableApplication;
}

class _EnvironmentScopeTile extends StatelessWidget {
  const _EnvironmentScopeTile({
    required this.selected,
    required this.label,
    required this.desktopFileId,
    required this.overrideCount,
    required this.onPressed,
    this.iconPath,
    this.unavailable = false,
    super.key,
  });

  final bool selected;
  final String label;
  final String desktopFileId;
  final int overrideCount;
  final VoidCallback onPressed;
  final String? iconPath;
  final bool unavailable;

  @override
  Widget build(BuildContext context) {
    final accent = ShellTheme.of(context).accent;
    return Semantics(
      selected: selected,
      button: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Material(
          color: ShellMediaColors.transparentDark,
          child: ListTile(
            selected: selected,
            selectedTileColor: accent.withValues(alpha: 0.12),
            shape: RoundedRectangleBorder(
              borderRadius: context.shellTheme.borderRadius(
                ShellShapeScale.large,
              ),
              side: BorderSide(
                color: selected
                    ? accent.withValues(alpha: 0.72)
                    : ShellMediaColors.transparentDark,
              ),
            ),
            minTileHeight: 56,
            contentPadding: const EdgeInsets.symmetric(horizontal: 9),
            mouseCursor: ShellMouseCursors.link,
            onTap: onPressed,
            leading: SizedBox.square(
              dimension: 30,
              child: unavailable
                  ? Icon(
                      Icons.app_blocking_rounded,
                      color: context.shellColors.textTertiary,
                      size: 22,
                    )
                  : iconPath == null
                  ? Icon(Icons.layers_rounded, color: accent, size: 21)
                  : DeferredAppIcon(iconPath: iconPath),
            ),
            title: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ShellText.settingsRowSupport.copyWith(
                color: selected
                    ? context.shellColors.textPrimary
                    : context.shellColors.textSecondary,
              ),
            ),
            subtitle: Text(
              desktopFileId,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ShellText.settingsBadgeLabel.copyWith(
                color: context.shellColors.textSecondary,
                fontFamily: ShellText.systemBarFontFamily,
              ),
            ),
            trailing: overrideCount == 0
                ? null
                : _EnvironmentCountBadge(count: overrideCount),
          ),
        ),
      ),
    );
  }
}

class _EnvironmentCountBadge extends StatelessWidget {
  const _EnvironmentCountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: ShellTheme.of(context).accent.withValues(alpha: 0.12),
        borderRadius: context.shellTheme.borderRadius(ShellShapeScale.full),
        border: Border.all(
          color: ShellTheme.of(context).accent.withValues(alpha: 0.45),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        child: Text(
          '$count',
          style: ShellText.settingsBadgeLabel.copyWith(
            color: ShellTheme.of(context).accent,
            fontFamily: ShellText.systemBarFontFamily,
          ),
        ),
      ),
    );
  }
}

class _EnvironmentScopeHeader extends StatelessWidget {
  const _EnvironmentScopeHeader({
    required this.application,
    required this.unavailableDesktopFileId,
    required this.inheritedCount,
    required this.scopeOverrideCount,
    required this.showBack,
    required this.onBack,
    required this.onClear,
  });

  final DesktopApp? application;
  final String? unavailableDesktopFileId;
  final int inheritedCount;
  final int scopeOverrideCount;
  final bool showBack;
  final VoidCallback onBack;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final allApplications =
        application == null && unavailableDesktopFileId == null;
    final title = allApplications
        ? context.l10n.settingsEnvironmentAllApplications
        : application?.name ??
              context.l10n.settingsEnvironmentUnavailableApplication;
    final identity = allApplications
        ? context.l10n.settingsEnvironmentAllApplicationsDescription
        : application?.id ?? unavailableDesktopFileId!;
    return SettingsCardGroup(
      children: [
        Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              if (showBack) ...[
                IconButton(
                  key: settingsEnvironmentBackToApplicationsKey,
                  tooltip: context.l10n.settingsEnvironmentBackToApplications,
                  onPressed: onBack,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.arrow_back_rounded, size: 18),
                ),
                const SizedBox(width: 4),
              ],
              SizedBox.square(
                dimension: 38,
                child: allApplications
                    ? Icon(
                        Icons.layers_rounded,
                        color: ShellTheme.of(context).accent,
                        size: 26,
                      )
                    : application == null
                    ? Icon(
                        Icons.app_blocking_rounded,
                        color: context.shellColors.textTertiary,
                        size: 26,
                      )
                    : DeferredAppIcon(iconPath: application!.iconPath),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ShellText.settingsRowTitle.copyWith(
                        color: context.shellColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      identity,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ShellText.settingsBadgeLabel.copyWith(
                        color: context.shellColors.textSecondary,
                        fontFamily: ShellText.systemBarFontFamily,
                      ),
                    ),
                    if (!allApplications) ...[
                      const SizedBox(height: 4),
                      Text(
                        context.l10n.settingsEnvironmentApplicationInherited(
                          inheritedCount,
                        ),
                        style: ShellText.settingsRowSupport.copyWith(
                          color: context.shellColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (scopeOverrideCount > 0) ...[
                const SizedBox(width: 8),
                _EnvironmentCountBadge(count: scopeOverrideCount),
              ],
              if (onClear != null) ...[
                const SizedBox(width: 8),
                SettingsTextButton(
                  label: context.l10n.settingsEnvironmentClearScope,
                  onPressed: onClear!,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ScopeCard extends StatelessWidget {
  const _ScopeCard({required this.description});

  final String description;

  @override
  Widget build(BuildContext context) {
    return SettingsCardGroup(
      children: [
        SettingsSection(
          title: context.l10n.settingsEnvironmentScopeTitle,
          leading: Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: ShellTheme.of(context).accent,
          ),
          child: Text(
            description,
            style: ShellText.base.copyWith(
              color: context.shellColors.textSecondary,
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }
}

class _VariablesCard extends StatelessWidget {
  const _VariablesCard({
    required this.variables,
    required this.defaultVariables,
    required this.perApplication,
    required this.onEdit,
    required this.onDelete,
  });

  final Map<String, String?> variables;
  final Map<String, String?> defaultVariables;
  final bool perApplication;
  final ValueChanged<String> onEdit;
  final ValueChanged<String> onDelete;

  @override
  Widget build(BuildContext context) {
    final names = variables.keys.toList(growable: false)..sort();
    return SettingsCardGroup(
      children: [
        SettingsSection(
          title: context.l10n.settingsEnvironmentVariablesTitle,
          status: context.l10n.settingsEnvironmentVariablesStatus(names.length),
          child: names.isEmpty
              ? const _EmptyVariables()
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final name in names)
                      _VariableRow(
                        name: name,
                        value: variables[name],
                        overridesDefault:
                            perApplication && defaultVariables.containsKey(name),
                        onEdit: () => onEdit(name),
                        onDelete: () => onDelete(name),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _EmptyVariables extends StatelessWidget {
  const _EmptyVariables();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        children: [
          Icon(
            Icons.data_object_rounded,
            size: 28,
            color: context.shellColors.textTertiary,
          ),
          const SizedBox(height: 9),
          Text(
            context.l10n.settingsEnvironmentEmptyTitle,
            style: ShellText.settingsRowTitle.copyWith(
              color: context.shellColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            context.l10n.settingsEnvironmentEmptyDescription,
            textAlign: TextAlign.center,
            style: ShellText.settingsRowSupport.copyWith(
              color: context.shellColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _VariableRow extends StatelessWidget {
  const _VariableRow({
    required this.name,
    required this.value,
    required this.overridesDefault,
    required this.onEdit,
    required this.onDelete,
  });

  final String name;
  final String? value;
  final bool overridesDefault;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final removed = value == null;
    final statusColor = removed
        ? context.shellColors.performanceBad
        : context.shellColors.performanceGood;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          _EnvironmentStatusMarker(removed: removed, color: statusColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: name,
                    style: ShellText.settingsSectionHeader.copyWith(
                      color: context.shellColors.textPrimary,
                      fontFamily: ShellText.systemBarFontFamily,
                    ),
                  ),
                  if (!removed)
                    TextSpan(
                      text: '  $value',
                      style: ShellText.settingsBadgeLabel.copyWith(
                        color: context.shellColors.textSecondary,
                        fontFamily: ShellText.systemBarFontFamily,
                      ),
                    ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          if (overridesDefault) ...[
            Tooltip(
              message: context.l10n.settingsEnvironmentOverridesDefault,
              child: Text(
                context.l10n.settingsEnvironmentOverridesDefaultBadge,
                style: ShellText.settingsBadgeLabel.copyWith(
                  color: ShellTheme.of(context).accent,
                  fontFamily: ShellText.systemBarFontFamily,
                ),
              ),
            ),
            const SizedBox(width: 6),
          ],
          if (!removed)
            IconButton(
              tooltip: context.l10n.settingsEnvironmentEditVariable(name),
              onPressed: onEdit,
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints.tightFor(width: 32, height: 32),
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.edit_outlined, size: 16),
            ),
          IconButton(
            tooltip: context.l10n.settingsEnvironmentDeleteVariable(name),
            onPressed: onDelete,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 32, height: 32),
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.close_rounded, size: 16),
          ),
        ],
      ),
    );
  }
}

class _EnvironmentStatusMarker extends StatelessWidget {
  const _EnvironmentStatusMarker({required this.removed, required this.color});

  final bool removed;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final label = removed
        ? context.l10n.settingsEnvironmentHiddenStatus
        : context.l10n.settingsEnvironmentAddedStatus;
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: label,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: context.shellTheme.borderRadius(ShellShapeScale.small),
          border: Border.all(color: color.withValues(alpha: 0.62)),
        ),
        child: SizedBox.square(
          dimension: 24,
          child: Center(
            child: Text(
              removed ? '−' : '+',
              style: ShellText.settingsRowTitle.copyWith(
                color: color,
                fontFamily: ShellText.systemBarFontFamily,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EnvironmentTextField extends StatelessWidget {
  const _EnvironmentTextField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.validator,
    required this.inputAction,
    this.focusNode,
    this.readOnly = false,
    this.onSubmitted,
    super.key,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final String label;
  final String hint;
  final FormFieldValidator<String> validator;
  final TextInputAction inputAction;
  final bool readOnly;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final accent = ShellTheme.of(context).accent;
    return MouseRegion(
      cursor: readOnly ? SystemMouseCursors.basic : ShellMouseCursors.text,
      child: TextFormField(
        controller: controller,
        focusNode: focusNode,
        readOnly: readOnly,
        autocorrect: false,
        enableSuggestions: false,
        textInputAction: inputAction,
        onFieldSubmitted: onSubmitted,
        validator: validator,
        style: ShellText.base.copyWith(
          color: context.shellColors.textPrimary,
          fontFamily: ShellText.systemBarFontFamily,
        ),
        decoration: InputDecoration(
          isDense: true,
          labelText: label,
          hintText: hint,
          floatingLabelBehavior: FloatingLabelBehavior.always,
          hintStyle: ShellText.settingsRowSupport.copyWith(
            color: context.shellColors.textTertiary.withValues(alpha: 0.58),
            fontFamily: ShellText.systemBarFontFamily,
            fontStyle: FontStyle.italic,
          ),
          filled: true,
          fillColor: context.shellColors.surfaceContainerHigh,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 13,
            vertical: 12,
          ),
          border: OutlineInputBorder(
            borderRadius: context.shellTheme.borderRadius(
              ShellShapeScale.medium,
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: context.shellTheme.borderRadius(
              ShellShapeScale.medium,
            ),
            borderSide: BorderSide(color: context.shellColors.hairline),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: context.shellTheme.borderRadius(
              ShellShapeScale.medium,
            ),
            borderSide: BorderSide(color: accent),
          ),
        ),
      ),
    );
  }
}
