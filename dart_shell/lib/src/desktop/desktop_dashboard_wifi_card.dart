import 'dart:async';

import 'package:flutter/material.dart' show CircularProgressIndicator, Icons;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/generated/app_localizations.dart';
import '../localization/denial_localizations.dart';
import '../services/network_manager_service.dart';
import '../state/network_connectivity.dart';
import '../theme/motion.dart';
import '../theme/shell_theme.dart';
import '../theme/tokens.dart';
import '../widgets/shell_cursor.dart';

/// Wi-Fi management card embedded in the desktop dashboard.
///
/// Designed to sit alongside the Bluetooth card with balanced height,
/// providing power control, scanning, network selection, and inline credentials
/// without delegating to a separate full-screen surface.
class DesktopDashboardWifiCard extends ConsumerStatefulWidget {
  const DesktopDashboardWifiCard({super.key});

  @override
  ConsumerState<DesktopDashboardWifiCard> createState() =>
      _DesktopDashboardWifiCardState();
}

class _DesktopDashboardWifiCardState
    extends ConsumerState<DesktopDashboardWifiCard> {
  final TextEditingController _passwordController = TextEditingController();
  final FocusNode _passwordFocus = FocusNode(
    debugLabel: 'desktop-wifi-password',
  );
  WifiNetwork? _credentialNetwork;
  String? _credentialError;

  @override
  void initState() {
    super.initState();
    _passwordController.addListener(_passwordChanged);
  }

  void _passwordChanged() {
    if (mounted && _credentialError != null) {
      setState(() => _credentialError = null);
    }
  }

  void _activate(WifiNetwork network) {
    final controller = ref.read(networkConnectivityProvider.notifier);
    if (network.connected) {
      unawaited(controller.disconnect(network));
      return;
    }
    if (!network.connectable) {
      return;
    }
    if (!network.saved && network.security.requiresPassword) {
      _passwordController.clear();
      setState(() {
        _credentialNetwork = network;
        _credentialError = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _passwordFocus.requestFocus();
        }
      });
      return;
    }
    unawaited(controller.connect(network));
  }

  void _submitCredential() {
    final network = _credentialNetwork;
    if (network == null) {
      return;
    }
    final secret = _passwordController.text;
    if ((network.security == WifiSecurity.wpaPersonal ||
            network.security == WifiSecurity.wpa3Personal) &&
        !_validPersonalPassword(secret)) {
      setState(() {
        _credentialError = context.l10n.wifiPasswordRequirements;
      });
      return;
    }
    if (network.security == WifiSecurity.wep &&
        (secret.length < 5 || secret.length > 64)) {
      setState(() {
        _credentialError = context.l10n.wifiWepRequirements;
      });
      return;
    }

    _passwordController.clear();
    setState(() {
      _credentialNetwork = null;
      _credentialError = null;
    });
    unawaited(
      ref
          .read(networkConnectivityProvider.notifier)
          .connect(network, password: secret),
    );
  }

  void _cancelCredential() {
    _passwordController.clear();
    setState(() {
      _credentialNetwork = null;
      _credentialError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(networkConnectivityProvider);
    final snapshot = state.snapshot;
    final controller = ref.read(networkConnectivityProvider.notifier);
    final theme = ShellTheme.of(context);
    final l10n = context.l10n;

    final radioEnabled =
        !state.initializing &&
        snapshot.serviceAvailable &&
        snapshot.wifiDeviceAvailable &&
        snapshot.wirelessHardwareEnabled &&
        snapshot.radioPermission != NetworkPermission.denied;

    final scanEnabled =
        snapshot.wirelessEnabled &&
        snapshot.serviceAvailable &&
        snapshot.wifiDeviceAvailable &&
        snapshot.wirelessHardwareEnabled &&
        snapshot.controlPermission != NetworkPermission.denied &&
        !state.scanning;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: ShellColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: ShellColors.hairlineSoft),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.wifi_rounded, size: 21, color: theme.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(l10n.commonWifi, style: ShellText.cardTitle),
                ),
                _DesktopDashboardIconButton(
                  semanticLabel: snapshot.wirelessEnabled
                      ? l10n.wifiTurnOff
                      : l10n.wifiTurnOn,
                  icon: Icons.power_settings_new_rounded,
                  active: snapshot.wirelessEnabled,
                  busy: state.radioChanging,
                  enabled: radioEnabled && !state.radioChanging,
                  onTap: controller.toggleWireless,
                ),
                const SizedBox(width: 7),
                _DesktopDashboardIconButton(
                  semanticLabel: state.scanning
                      ? l10n.desktopScanningWifiNetworks
                      : l10n.desktopScanWifi,
                  icon: Icons.radar_rounded,
                  active: state.scanning,
                  busy: state.scanning,
                  enabled: scanEnabled,
                  onTap: controller.scan,
                ),
                const SizedBox(width: 7),
                _DesktopDashboardIconButton(
                  semanticLabel: l10n.desktopRefreshWifi,
                  icon: Icons.refresh_rounded,
                  busy: state.initializing,
                  enabled: snapshot.serviceAvailable && !state.initializing,
                  onTap: controller.refresh,
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (state.error != null) ...[
              GestureDetector(
                onTap: controller.clearError,
                child: Text(
                  state.error ?? l10n.wifiOperationFailed,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: ShellText.cardTitle.copyWith(
                    color: ShellColors.performanceBad,
                    fontSize: 11,
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            if (_credentialNetwork case final network?) ...[
              _DesktopWifiCredentialPanel(
                network: network,
                controller: _passwordController,
                focusNode: _passwordFocus,
                error: _credentialError,
                onCancel: _cancelCredential,
                onSubmit: _submitCredential,
              ),
              const SizedBox(height: 10),
            ],
            Expanded(
              child: _DesktopWifiNetworkList(
                state: state,
                onActivate: _activate,
                onForget: (network) => unawaited(controller.forget(network)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _passwordController
      ..removeListener(_passwordChanged)
      ..clear()
      ..dispose();
    _passwordFocus.dispose();
    super.dispose();
  }
}

class _DesktopWifiNetworkList extends StatefulWidget {
  const _DesktopWifiNetworkList({
    required this.state,
    required this.onActivate,
    required this.onForget,
  });

  final NetworkConnectivityState state;
  final ValueChanged<WifiNetwork> onActivate;
  final ValueChanged<WifiNetwork> onForget;

  @override
  State<_DesktopWifiNetworkList> createState() =>
      _DesktopWifiNetworkListState();
}

class _DesktopWifiNetworkListState extends State<_DesktopWifiNetworkList> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final snapshot = state.snapshot;
    final accent = ShellTheme.of(context).accentPalette;
    final l10n = context.l10n;

    if (state.initializing && snapshot.networks.isEmpty) {
      return Center(
        child: SizedBox.square(
          dimension: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: accent.primary,
          ),
        ),
      );
    }
    if (!snapshot.serviceAvailable) {
      return _DesktopDashboardWifiEmptyState(
        icon: Icons.portable_wifi_off_rounded,
        title: l10n.wifiServiceUnavailable,
      );
    }
    if (!snapshot.wifiDeviceAvailable) {
      return _DesktopDashboardWifiEmptyState(
        icon: Icons.wifi_off_rounded,
        title: l10n.wifiNoAdapter,
      );
    }
    if (!snapshot.wirelessHardwareEnabled) {
      return _DesktopDashboardWifiEmptyState(
        icon: Icons.phonelink_erase_rounded,
        title: l10n.wifiHardwareBlocked,
      );
    }
    if (!snapshot.wirelessEnabled) {
      return _DesktopDashboardWifiEmptyState(
        icon: Icons.wifi_off_rounded,
        title: l10n.wifiOff,
      );
    }
    if (snapshot.networks.isEmpty) {
      return _DesktopDashboardWifiEmptyState(
        icon: state.scanning ? Icons.radar_rounded : Icons.wifi_find_rounded,
        title: state.scanning
            ? l10n.desktopScanningWifiNetworks
            : l10n.wifiNoNetworks,
      );
    }

    return RawScrollbar(
      controller: _scrollController,
      thumbVisibility: true,
      trackVisibility: false,
      radius: const Radius.circular(4),
      thickness: 4,
      thumbColor: accent.primary.withValues(alpha: 0.4),
      child: ListView.separated(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.only(right: 6),
        itemCount: snapshot.networks.length,
        separatorBuilder: (_, _) => const SizedBox(height: 6),
        itemBuilder: (context, index) {
          final network = snapshot.networks[index];
          return _DesktopWifiNetworkRow(
            network: network,
            busy: state.busyNetworks.contains(network.identity),
            activationEnabled:
                state.snapshot.controlPermission != NetworkPermission.denied &&
                (network.connected ||
                    network.saved ||
                    state.snapshot.modifyPermission !=
                        NetworkPermission.denied),
            onActivate: () => widget.onActivate(network),
            onForget:
                network.saved &&
                    state.snapshot.modifyPermission != NetworkPermission.denied
                ? () => widget.onForget(network)
                : null,
          );
        },
      ),
    );
  }
}

class _DesktopDashboardWifiEmptyState extends StatelessWidget {
  const _DesktopDashboardWifiEmptyState({
    required this.icon,
    required this.title,
  });

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 34, color: ShellColors.textTertiary),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: ShellText.cardTitle.copyWith(
              color: ShellColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopWifiNetworkRow extends StatefulWidget {
  const _DesktopWifiNetworkRow({
    required this.network,
    required this.busy,
    required this.activationEnabled,
    required this.onActivate,
    required this.onForget,
  });

  final WifiNetwork network;
  final bool busy;
  final bool activationEnabled;
  final VoidCallback onActivate;
  final VoidCallback? onForget;

  @override
  State<_DesktopWifiNetworkRow> createState() => _DesktopWifiNetworkRowState();
}

class _DesktopWifiNetworkRowState extends State<_DesktopWifiNetworkRow> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final network = widget.network;
    final accent = ShellTheme.of(context).accentPalette;
    final l10n = context.l10n;
    final enabled =
        widget.activationEnabled && (network.connectable || network.connected);
    final status = network.connected
        ? l10n.settingsConnected
        : network.saved && !network.available
        ? l10n.wifiSavedOutOfRange
        : network.saved
        ? l10n.wifiSavedWithSecurity(_wifiSecurityLabel(l10n, network.security))
        : _wifiSecurityLabel(l10n, network.security);

    return Semantics(
      button: true,
      explicitChildNodes: widget.onForget != null,
      enabled: enabled && !widget.busy,
      label: network.connected
          ? l10n.wifiDisconnectNetwork(network.ssid)
          : l10n.wifiConnectNetwork(network.ssid, status, network.strength),
      child: FocusableActionDetector(
        enabled: enabled && !widget.busy,
        mouseCursor: widget.busy
            ? ShellMouseCursors.working
            : enabled
            ? ShellMouseCursors.link
            : ShellMouseCursors.normal,
        onShowHoverHighlight: (hovered) => setState(() => _hovered = hovered),
        onShowFocusHighlight: (focused) => setState(() => _focused = focused),
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              if (enabled && !widget.busy) {
                widget.onActivate();
              }
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled && !widget.busy ? widget.onActivate : null,
          child: AnimatedContainer(
            duration: Motion.tile,
            curve: Motion.standard,
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: network.connected
                  ? accent.container
                  : _hovered || _focused
                  ? ShellColors.surfaceContainerHighest
                  : ShellColors.surfaceContainer,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _focused ? accent.primary : ShellColors.hairlineSoft,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _strengthIcon(network.strength),
                  size: 21,
                  color: network.connected
                      ? accent.onContainer
                      : enabled
                      ? ShellColors.textPrimary
                      : ShellColors.glyphInactive,
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        network.ssid,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ShellText.cardTitle.copyWith(
                          color: network.connected ? accent.onContainer : null,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ShellText.base.copyWith(
                          color: network.connected
                              ? accent.onContainer
                              : ShellColors.textTertiary,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (network.security != WifiSecurity.open) ...[
                  const SizedBox(width: 4),
                  Icon(
                    network.security == WifiSecurity.enterprise
                        ? Icons.business_rounded
                        : Icons.lock_rounded,
                    size: 16,
                    color: network.connected
                        ? accent.onContainer
                        : ShellColors.textTertiary,
                  ),
                ],
                if (widget.onForget != null) ...[
                  const SizedBox(width: 6),
                  _DesktopWifiForgetButton(
                    label: l10n.wifiForgetNetwork(network.ssid),
                    icon: Icons.delete_outline_rounded,
                    enabled: !widget.busy,
                    onPressed: widget.onForget!,
                  ),
                ],
                const SizedBox(width: 6),
                if (widget.busy)
                  SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: accent.primary,
                    ),
                  )
                else
                  Icon(
                    network.connected
                        ? Icons.link_off_rounded
                        : Icons.chevron_right_rounded,
                    size: 20,
                    color: network.connected
                        ? accent.onContainer
                        : ShellColors.textSecondary,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopWifiForgetButton extends StatefulWidget {
  const _DesktopWifiForgetButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.enabled = true,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool enabled;

  @override
  State<_DesktopWifiForgetButton> createState() =>
      _DesktopWifiForgetButtonState();
}

class _DesktopWifiForgetButtonState extends State<_DesktopWifiForgetButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: widget.label,
      child: MouseRegion(
        cursor: widget.enabled
            ? ShellMouseCursors.link
            : ShellMouseCursors.normal,
        onEnter: widget.enabled ? (_) => setState(() => _hovered = true) : null,
        onExit: widget.enabled ? (_) => setState(() => _hovered = false) : null,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.enabled ? widget.onPressed : null,
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: _hovered
                  ? ShellColors.surfaceContainerHighest
                  : const Color(0x00000000),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              widget.icon,
              size: 16,
              color: widget.enabled
                  ? ShellColors.textSecondary
                  : ShellColors.glyphInactive,
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopWifiCredentialPanel extends StatelessWidget {
  const _DesktopWifiCredentialPanel({
    required this.network,
    required this.controller,
    required this.focusNode,
    required this.error,
    required this.onCancel,
    required this.onSubmit,
  });

  final WifiNetwork network;
  final TextEditingController controller;
  final FocusNode focusNode;
  final String? error;
  final VoidCallback onCancel;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final theme = ShellTheme.of(context);
    final l10n = context.l10n;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: ShellColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: error == null
              ? ShellColors.hairlineSoft
              : ShellColors.performanceBad,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.wifiPasswordFor(network.ssid),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ShellText.cardTitle,
            ),
            const SizedBox(height: 9),
            Semantics(
              textField: true,
              obscured: true,
              label: l10n.wifiPasswordField(network.ssid),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.panelColor(ShellColors.panelBackground),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: focusNode.hasFocus
                        ? theme.accent
                        : ShellColors.hairline,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: EditableText(
                    controller: controller,
                    focusNode: focusNode,
                    autofocus: true,
                    obscureText: true,
                    enableSuggestions: false,
                    autocorrect: false,
                    keyboardType: TextInputType.visiblePassword,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => onSubmit(),
                    style: ShellText.base,
                    cursorColor: theme.accent,
                    backgroundCursorColor: ShellColors.textSecondary,
                    selectionColor: ShellColors.primaryContainer,
                  ),
                ),
              ),
            ),
            if (error case final message?) ...[
              const SizedBox(height: 7),
              Text(
                message,
                style: ShellText.base.copyWith(
                  color: ShellColors.performanceBad,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 9),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _DesktopWifiTextButton(
                  label: l10n.commonCancel,
                  onPressed: onCancel,
                ),
                const SizedBox(width: 8),
                _DesktopWifiTextButton(
                  label: l10n.settingsConnect,
                  emphasized: true,
                  onPressed: onSubmit,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopWifiTextButton extends StatefulWidget {
  const _DesktopWifiTextButton({
    required this.label,
    required this.onPressed,
    this.emphasized = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool emphasized;

  @override
  State<_DesktopWifiTextButton> createState() => _DesktopWifiTextButtonState();
}

class _DesktopWifiTextButtonState extends State<_DesktopWifiTextButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final accent = ShellTheme.of(context).accentPalette;
    return Semantics(
      button: true,
      label: widget.label,
      child: MouseRegion(
        cursor: ShellMouseCursors.link,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: Motion.pill,
            decoration: BoxDecoration(
              color: widget.emphasized
                  ? (_hovered ? accent.primary : accent.container)
                  : (_hovered
                        ? ShellColors.surfaceContainerHighest
                        : ShellColors.surfaceContainer),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: ShellColors.hairlineSoft),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Text(
              widget.label,
              style: ShellText.cardTitle.copyWith(
                color: widget.emphasized
                    ? (_hovered ? accent.onPrimary : accent.onContainer)
                    : ShellColors.textPrimary,
                fontSize: 11,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopDashboardIconButton extends StatefulWidget {
  const _DesktopDashboardIconButton({
    required this.semanticLabel,
    required this.icon,
    required this.onTap,
    this.active = false,
    this.busy = false,
    this.enabled = true,
  });

  final String semanticLabel;
  final IconData icon;
  final VoidCallback onTap;
  final bool active;
  final bool busy;
  final bool enabled;

  @override
  State<_DesktopDashboardIconButton> createState() =>
      _DesktopDashboardIconButtonState();
}

class _DesktopDashboardIconButtonState
    extends State<_DesktopDashboardIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final accent = ShellTheme.of(context).accentPalette;
    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: widget.semanticLabel,
      child: MouseRegion(
        cursor: widget.busy
            ? ShellMouseCursors.working
            : widget.enabled
            ? ShellMouseCursors.link
            : ShellMouseCursors.normal,
        onEnter: widget.enabled ? (_) => setState(() => _hovered = true) : null,
        onExit: widget.enabled ? (_) => setState(() => _hovered = false) : null,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.enabled && !widget.busy ? widget.onTap : null,
          child: AnimatedContainer(
            duration: Motion.pill,
            curve: Motion.standard,
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: widget.active
                  ? accent.container
                  : _hovered
                  ? ShellColors.surfaceContainerHighest
                  : ShellColors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
            ),
            child: widget.busy
                ? Padding(
                    padding: const EdgeInsets.all(9),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: accent.primary,
                    ),
                  )
                : Icon(
                    widget.icon,
                    size: 18,
                    color: widget.enabled
                        ? widget.active
                              ? accent.onContainer
                              : ShellColors.textPrimary
                        : ShellColors.glyphInactive,
                  ),
          ),
        ),
      ),
    );
  }
}

String _wifiSecurityLabel(AppLocalizations l10n, WifiSecurity security) {
  return switch (security) {
    WifiSecurity.open => l10n.wifiSecurityOpen,
    WifiSecurity.wep => l10n.wifiSecurityWep,
    WifiSecurity.wpaPersonal => l10n.wifiSecurityWpaPersonal,
    WifiSecurity.wpa3Personal => l10n.wifiSecurityWpa3Personal,
    WifiSecurity.owe => l10n.wifiSecurityEnhancedOpen,
    WifiSecurity.enterprise => l10n.wifiSecurityEnterprise,
    WifiSecurity.unknown => l10n.wifiSecurityUnsupported,
  };
}

IconData _strengthIcon(int strength) {
  if (strength >= 70) {
    return Icons.wifi_rounded;
  }
  if (strength >= 40) {
    return Icons.network_wifi_2_bar_rounded;
  }
  if (strength > 0) {
    return Icons.network_wifi_1_bar_rounded;
  }
  return Icons.wifi_find_rounded;
}

bool _validPersonalPassword(String value) {
  return (value.length >= 8 && value.length <= 63) ||
      RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(value);
}
