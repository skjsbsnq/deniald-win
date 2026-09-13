import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../localization/denial_localizations.dart';
import '../../settings/settings_controller.dart';
import '../../state/shell_controller.dart';
import '../../theme/shell_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/shell_expressive_surface.dart';
import '../desktop_workspace.dart';

/// ChromeOS-style Desk button on the left edge of the shelf.
///
/// It sits between the launcher and the application strip and only appears
/// while monitor-local workspaces are enabled. A tap advances the monitor to
/// its next workspace; the compositor stays authoritative and echoes the new
/// active workspace back through the shell action channel.
class ShelfWorkspaceButton extends ConsumerWidget {
  const ShelfWorkspaceButton({this.monitorId, super.key});

  /// Output whose workspace this button controls. Null keeps the control
  /// hidden because a workspace switch is always monitor-local.
  final int? monitorId;

  static const double height = 36.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final monitorId = this.monitorId;
    if (monitorId == null) {
      return const SizedBox.shrink();
    }
    final enabled = ref.watch(
      shellSettingsProvider.select((s) => s.layout.workspacesEnabled),
    );
    if (!enabled) {
      return const SizedBox.shrink();
    }
    final workspaceCount = ref.watch(
      shellSettingsProvider.select((s) => s.layout.workspaceCount),
    );
    final active = ref.watch(
      desktopWorkspaceProvider.select(
        (state) => state.activeWorkspaceFor(monitorId),
      ),
    );

    final theme = context.shellTheme;
    final colors = context.shellColors;
    final l10n = context.l10n;
    final label = '${l10n.desktopWorkspaceDesk} $active';

    return ShellExpressiveSurface(
      onPressed: () {
        final next = active >= workspaceCount ? 1 : active + 1;
        ref
            .read(denialBridgeProvider)
            .switchWorkspace(monitorId: monitorId, workspaceId: next);
      },
      shape: ShellShapeScale.full,
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: ShellSpacing.md),
      tooltip: l10n.desktopWorkspaceSwitch,
      semanticLabel: '${l10n.desktopWorkspaceSwitch}, $label',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.space_dashboard_outlined,
            size: 18,
            color: colors.textPrimary,
          ),
          const SizedBox(width: ShellSpacing.sm),
          Text(
            label,
            style: theme.text.systemBarValue.copyWith(
              color: colors.textPrimary,
            ),
            maxLines: 1,
          ),
        ],
      ),
    );
  }
}
