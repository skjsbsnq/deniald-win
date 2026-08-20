import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../localization/denial_localizations.dart';
import '../../models/tray_item.dart';
import '../../models/ui_development.dart';
import '../../state/status_notifier.dart';
import '../../state/ui_development.dart';
import '../../theme/shell_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/shell_cursor.dart';
import '../../widgets/tray/tray_icon.dart';
import 'settings_controls.dart';

const settingsDeveloperWorkspaceFieldKey = ValueKey<String>(
  'settings-developer-workspace-field',
);
const settingsDeveloperLiveToggleKey = ValueKey<String>(
  'settings-developer-live-toggle',
);

class SettingsDeveloperPage extends StatefulWidget {
  const SettingsDeveloperPage({
    required this.state,
    required this.controller,
    required this.workspaceSetup,
    super.key,
  });

  final DenialUiDevelopmentState state;
  final UiDevelopmentController controller;
  final UiWorkspaceSetupService workspaceSetup;

  @override
  State<SettingsDeveloperPage> createState() => _SettingsDeveloperPageState();
}

class _SettingsDeveloperPageState extends State<SettingsDeveloperPage> {
  late final TextEditingController _workspaceController;
  late final FocusNode _workspaceFocus;
  var _setupRunning = false;
  var _setupError = '';

  @override
  void initState() {
    super.initState();
    _workspaceController = TextEditingController(text: widget.state.workspace);
    _workspaceFocus = FocusNode();
  }

  @override
  void didUpdateWidget(covariant SettingsDeveloperPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_workspaceFocus.hasFocus &&
        oldWidget.state.workspace != widget.state.workspace &&
        _workspaceController.text != widget.state.workspace) {
      _workspaceController.text = widget.state.workspace;
    }
  }

  @override
  void dispose() {
    _workspaceFocus.dispose();
    _workspaceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final controller = widget.controller;
    final l10n = context.l10n;
    final liveControlsEnabled =
        state.activeMode == DenialUiRuntimeMode.liveDevelopment && !state.busy;
    final workspaceControlsEnabled =
        !state.busy &&
        !_setupRunning &&
        state.activeMode != DenialUiRuntimeMode.liveDevelopment &&
        state.desiredMode != DenialUiRuntimeMode.liveDevelopment;
    return SettingsPageLayout(
      icon: Icons.code_rounded,
      eyebrow: l10n.settingsDeveloperSection,
      title: l10n.settingsDeveloperDescription,
      onReset: controller.restoreOfficial,
      children: [
        SettingsCardGroup(
          children: [
            SettingsSection(
              title: l10n.settingsDeveloperRuntimeTitle,
              status: _modeLabel(context, state.activeMode),
              leading: _RuntimeStatusDot(state: state),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _RuntimeSummary(state: state),
                  const SizedBox(height: 15),
                  SettingsToggle(
                    key: settingsDeveloperLiveToggleKey,
                    label: l10n.settingsDeveloperEnableTitle,
                    description: l10n.settingsDeveloperEnableDescription,
                    value: state.liveDevelopmentEnabled,
                    enabled:
                        !state.busy &&
                        (state.liveDevelopmentEnabled ||
                            (state.developerComponentsAvailable &&
                                state.workspaceValid)),
                    onChanged: controller.setLiveDevelopmentEnabled,
                  ),
                  const SizedBox(height: 14),
                  _WarningBanner(
                    text: l10n.settingsDeveloperPerformanceWarning,
                  ),
                ],
              ),
            ),
          ],
        ),
        SettingsCardGroup(
          children: [
            SettingsSection(
              title: l10n.settingsDeveloperWorkspaceTitle,
              status: state.workspaceValid
                  ? l10n.settingsDeveloperWorkspaceReady
                  : l10n.settingsDeveloperWorkspaceNotReady,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _WorkspaceSetupPanel(
                    available: widget.workspaceSetup.available,
                    running: _setupRunning,
                    error: _setupError,
                    enabled: workspaceControlsEnabled,
                    onPressed: _setupWorkspace,
                  ),
                  const SizedBox(height: 15),
                  const Divider(height: 1, color: ShellColors.hairlineSoft),
                  const SizedBox(height: 15),
                  Text(
                    l10n.settingsDeveloperWorkspaceDescription,
                    style: ShellText.base.copyWith(
                      color: ShellColors.textTertiary,
                      fontSize: 12,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _WorkspaceField(
                    controller: _workspaceController,
                    focusNode: _workspaceFocus,
                    enabled: workspaceControlsEnabled,
                    onSubmitted: _applyWorkspace,
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SettingsTextButton(
                      label: l10n.settingsDeveloperUseWorkspace,
                      onPressed: workspaceControlsEnabled
                          ? _applyWorkspace
                          : null,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        SettingsCardGroup(
          children: [
            SettingsSection(
              title: l10n.settingsDeveloperLiveControlsTitle,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SettingsToggle(
                    label: l10n.settingsDeveloperAutoReloadTitle,
                    description: l10n.settingsDeveloperAutoReloadDescription,
                    value: state.autoReload,
                    enabled:
                        state.autoReloadSupported &&
                        state.workspaceValid &&
                        !state.busy,
                    onChanged: controller.setAutoReload,
                  ),
                  const SizedBox(height: 15),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      SettingsTextButton(
                        label: l10n.settingsDeveloperHotReload,
                        onPressed: liveControlsEnabled && state.canHotReload
                            ? controller.hotReload
                            : null,
                      ),
                      SettingsTextButton(
                        label: l10n.settingsDeveloperHotRestart,
                        onPressed: liveControlsEnabled && state.canHotRestart
                            ? controller.hotRestart
                            : null,
                      ),
                      SettingsTextButton(
                        label: l10n.settingsDeveloperRefreshStatus,
                        onPressed: state.busy ? null : controller.refresh,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        SettingsCardGroup(
          children: [
            SettingsSection(
              title: l10n.settingsDeveloperBuildRecoveryTitle,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.settingsDeveloperBuildRecoveryDescription,
                    style: ShellText.base.copyWith(
                      color: ShellColors.textTertiary,
                      fontSize: 12,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      SettingsTextButton(
                        label: l10n.settingsDeveloperBuildOptimized,
                        onPressed: state.canBuildOptimized && !state.busy
                            ? controller.buildAndActivateOptimized
                            : null,
                      ),
                      SettingsTextButton(
                        label: l10n.settingsDeveloperRevertLastWorking,
                        onPressed: state.canRevert && !state.busy
                            ? controller.revertLastWorking
                            : null,
                      ),
                      SettingsTextButton(
                        label: l10n.settingsDeveloperRestoreOfficial,
                        onPressed:
                            state.activeMode !=
                                    DenialUiRuntimeMode.officialOptimized &&
                                !state.busy
                            ? controller.restoreOfficial
                            : null,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        SettingsCardGroup(
          children: [
            SettingsSection(
              title: l10n.settingsDeveloperDiagnosticsTitle,
              status: state.generation == 0
                  ? null
                  : '${l10n.settingsDeveloperGeneration} ${state.generation}',
              child: _Diagnostics(state: state),
            ),
          ],
        ),
        const SettingsCardGroup(
          children: [
            SettingsSection(
              title: 'StatusNotifier (SNI) Tray Debug',
              child: _TrayDiagnostics(),
            ),
          ],
        ),
      ],
    );
  }

  void _applyWorkspace() {
    if (widget.controller.setWorkspace(_workspaceController.text)) {
      _workspaceFocus.unfocus();
    }
  }

  Future<void> _setupWorkspace() async {
    if (_setupRunning) {
      return;
    }
    setState(() {
      _setupRunning = true;
      _setupError = '';
    });
    try {
      await widget.workspaceSetup.setup();
      if (!mounted) {
        return;
      }
      widget.controller.refresh();
      setState(() {
        _setupRunning = false;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _setupRunning = false;
        _setupError = error.toString();
      });
    }
  }

  String _modeLabel(BuildContext context, DenialUiRuntimeMode mode) {
    final l10n = context.l10n;
    return switch (mode) {
      DenialUiRuntimeMode.officialOptimized =>
        l10n.settingsDeveloperModeOfficial,
      DenialUiRuntimeMode.customOptimized => l10n.settingsDeveloperModeCustom,
      DenialUiRuntimeMode.liveDevelopment => l10n.settingsDeveloperModeLive,
      DenialUiRuntimeMode.unavailable => l10n.settingsDeveloperModeUnavailable,
    };
  }
}

class _WorkspaceSetupPanel extends StatelessWidget {
  const _WorkspaceSetupPanel({
    required this.available,
    required this.running,
    required this.error,
    required this.enabled,
    required this.onPressed,
  });

  final bool available;
  final bool running;
  final String error;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final status = error.isNotEmpty
        ? error
        : running
        ? l10n.settingsDeveloperSetupRunning
        : !available
        ? l10n.settingsDeveloperSetupUnavailable
        : '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.settingsDeveloperSetupDescription,
          style: ShellText.base.copyWith(
            color: ShellColors.textSecondary,
            fontSize: 12,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: SettingsTextButton(
            label: l10n.settingsDeveloperSetupAction,
            onPressed: available && enabled && !running ? onPressed : null,
          ),
        ),
        if (status.isNotEmpty) ...[
          const SizedBox(height: 10),
          Semantics(
            liveRegion: true,
            label: status,
            child: Text(
              status,
              style: ShellText.base.copyWith(
                color: error.isNotEmpty
                    ? ShellColors.performanceBad
                    : ShellColors.textTertiary,
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ),
        ],
        if (running) ...[
          const SizedBox(height: 10),
          LinearProgressIndicator(
            minHeight: 4,
            borderRadius: BorderRadius.circular(99),
            color: ShellTheme.of(context).accent,
            backgroundColor: ShellColors.surfaceContainerHighest,
          ),
        ],
      ],
    );
  }
}

class _WorkspaceField extends StatelessWidget {
  const _WorkspaceField({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    final accent = ShellTheme.of(context).accent;
    return Semantics(
      textField: true,
      label: context.l10n.settingsDeveloperWorkspaceFieldLabel,
      child: MouseRegion(
        cursor: ShellMouseCursors.text,
        child: TextField(
          key: settingsDeveloperWorkspaceFieldKey,
          controller: controller,
          focusNode: focusNode,
          enabled: enabled,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => onSubmitted(),
          style: ShellText.base.copyWith(
            color: ShellColors.textPrimary,
            fontFamily: ShellText.systemBarFontFamily,
            fontSize: 12,
          ),
          decoration: InputDecoration(
            isDense: true,
            hintText: context.l10n.settingsDeveloperWorkspaceHint,
            hintStyle: ShellText.base.copyWith(
              color: ShellColors.textTertiary,
              fontSize: 12,
            ),
            filled: true,
            fillColor: ShellColors.surfaceContainerHigh,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 13,
              vertical: 12,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(ShellRadii.chip),
              borderSide: const BorderSide(color: ShellColors.hairline),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(ShellRadii.chip),
              borderSide: BorderSide(color: accent),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(ShellRadii.chip),
              borderSide: const BorderSide(color: ShellColors.hairlineSoft),
            ),
          ),
        ),
      ),
    );
  }
}

class _RuntimeStatusDot extends StatelessWidget {
  const _RuntimeStatusDot({required this.state});

  final DenialUiDevelopmentState state;

  @override
  Widget build(BuildContext context) {
    final color = state.error.isNotEmpty
        ? ShellColors.performanceBad
        : state.busy
        ? ShellColors.performanceWarning
        : state.activeMode == DenialUiRuntimeMode.liveDevelopment
        ? ShellTheme.of(context).accent
        : ShellColors.performanceGood;
    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _RuntimeSummary extends StatelessWidget {
  const _RuntimeSummary({required this.state});

  final DenialUiDevelopmentState state;

  @override
  Widget build(BuildContext context) {
    final text = state.error.isNotEmpty
        ? state.error
        : state.status.isNotEmpty
        ? state.status
        : context.l10n.settingsDeveloperWaitingForStatus;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          text,
          style: ShellText.base.copyWith(
            color: state.error.isNotEmpty
                ? ShellColors.performanceBad
                : ShellColors.textSecondary,
            fontSize: 12,
            height: 1.45,
          ),
        ),
        if (state.progress case final progress?) ...[
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: progress,
            minHeight: 4,
            borderRadius: BorderRadius.circular(99),
            color: ShellTheme.of(context).accent,
            backgroundColor: ShellColors.surfaceContainerHighest,
          ),
        ],
      ],
    );
  }
}

class _WarningBanner extends StatelessWidget {
  const _WarningBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: ShellColors.performanceWarning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: ShellColors.performanceWarning.withValues(alpha: 0.28),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.speed_rounded,
              size: 16,
              color: ShellColors.performanceWarning,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                text,
                style: ShellText.base.copyWith(
                  color: ShellColors.textSecondary,
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Diagnostics extends StatelessWidget {
  const _Diagnostics({required this.state});

  final DenialUiDevelopmentState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.vmServiceAvailable && state.vmServiceUri.isNotEmpty) ...[
          Text(
            l10n.settingsDeveloperVmServiceTitle,
            style: ShellText.cardTitle.copyWith(
              color: ShellColors.textSecondary,
            ),
          ),
          const SizedBox(height: 5),
          SelectableText(
            state.vmServiceUri,
            style: ShellText.base.copyWith(
              color: ShellTheme.of(context).accent,
              fontFamily: ShellText.systemBarFontFamily,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            l10n.settingsDeveloperEditorAttachDescription,
            style: ShellText.base.copyWith(
              color: ShellColors.textTertiary,
              fontSize: 11,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (state.diagnostics.isEmpty)
          Text(
            l10n.settingsDeveloperNoDiagnostics,
            style: ShellText.base.copyWith(
              color: ShellColors.textTertiary,
              fontSize: 12,
            ),
          )
        else
          for (final diagnostic in state.diagnostics)
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: _DiagnosticRow(diagnostic: diagnostic),
            ),
      ],
    );
  }
}

class _DiagnosticRow extends StatelessWidget {
  const _DiagnosticRow({required this.diagnostic});

  final DenialUiDiagnostic diagnostic;

  @override
  Widget build(BuildContext context) {
    final color = switch (diagnostic.severity) {
      DenialUiDiagnosticSeverity.information => ShellTheme.of(context).accent,
      DenialUiDiagnosticSeverity.warning => ShellColors.performanceWarning,
      DenialUiDiagnosticSeverity.error => ShellColors.performanceBad,
    };
    final location = diagnostic.path.isEmpty
        ? ''
        : diagnostic.line == 0
        ? diagnostic.path
        : '${diagnostic.path}:${diagnostic.line}:${diagnostic.column}';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                diagnostic.message,
                style: ShellText.base.copyWith(
                  color: ShellColors.textSecondary,
                  fontSize: 12,
                ),
              ),
              if (location.isNotEmpty) ...[
                const SizedBox(height: 3),
                SelectableText(
                  location,
                  style: ShellText.base.copyWith(
                    color: ShellColors.textTertiary,
                    fontFamily: ShellText.systemBarFontFamily,
                    fontSize: 10,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _TrayDiagnostics extends ConsumerWidget {
  const _TrayDiagnostics();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trayState = ref.watch(statusNotifierProvider);
    final items = trayState.items;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.spaceBetween,
          children: [
            Text(
              'Watcher: ${trayState.isWatcher ? "Primary Owner" : "Secondary / External"}',
              style: ShellText.base.copyWith(
                color: ShellColors.textSecondary,
                fontSize: 11,
              ),
            ),
            Text(
              'Host: ${trayState.isHostRegistered ? "Registered" : "Unregistered"}',
              style: ShellText.base.copyWith(
                color: ShellColors.textSecondary,
                fontSize: 11,
              ),
            ),
            SettingsTextButton(
              label: 'Refresh',
              onPressed: trayState.refreshing
                  ? null
                  : () => ref.read(statusNotifierProvider.notifier).refresh(),
            ),
          ],
        ),
        if (trayState.error != null) ...[
          const SizedBox(height: 6),
          Text(
            trayState.error!,
            style: ShellText.base.copyWith(
              color: ShellColors.performanceBad,
              fontSize: 11,
            ),
          ),
        ],
        const SizedBox(height: 10),
        if (items.isEmpty)
          Text(
            'No StatusNotifier items currently registered.',
            style: ShellText.base.copyWith(
              color: ShellColors.textTertiary,
              fontSize: 12,
            ),
          )
        else
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: ShellColors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: ShellColors.hairlineSoft),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: ShellColors.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: ShellColors.hairlineSoft),
                      ),
                      child: TrayIcon(item: item, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  item.displayLabel,
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                  style: ShellText.base.copyWith(
                                    color: ShellColors.textPrimary,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      item.status ==
                                          TrayItemStatus.needsAttention
                                      ? ShellColors.performanceWarning
                                      : item.status == TrayItemStatus.active
                                      ? ShellTheme.of(context).accent
                                      : ShellColors.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  item.status.toWireString(),
                                  style: ShellText.base.copyWith(
                                    color: item.status == TrayItemStatus.passive
                                        ? ShellColors.textTertiary
                                        : Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          SelectableText(
                            'Id: ${item.id.isEmpty ? "(empty)" : item.id} | Title: ${item.title.isEmpty ? "(empty)" : item.title} | Category: ${item.category.toWireString()}',
                            style: ShellText.base.copyWith(
                              color: ShellColors.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 2),
                          SelectableText(
                            'Bus: ${item.service} | Path: ${item.path}',
                            style: ShellText.base.copyWith(
                              color: ShellColors.textTertiary,
                              fontFamily: ShellText.systemBarFontFamily,
                              fontSize: 10,
                            ),
                          ),
                          if (item.iconName.isNotEmpty ||
                              item.iconPixmap.isNotEmpty ||
                              item.iconThemePath.isNotEmpty ||
                              item.menuPath.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            SelectableText(
                              'Icon: ${item.iconName.isNotEmpty ? item.iconName : "(pixmaps: ${item.iconPixmap.length})"}'
                              '${item.iconThemePath.isNotEmpty ? " | Path: ${item.iconThemePath}" : ""}'
                              '${item.menuPath.isNotEmpty ? " | Menu: ${item.menuPath}" : ""}',
                              style: ShellText.base.copyWith(
                                color: ShellColors.textTertiary,
                                fontFamily: ShellText.systemBarFontFamily,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}
