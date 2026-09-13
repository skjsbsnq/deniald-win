import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../settings/settings_controller.dart';
import '../../state/shell_controller.dart';
import '../../theme/tokens.dart';
import '../desktop_workspace.dart';
import 'shelf_workspace_dots.dart';

/// Clavis-style workspace dot capsule on the left edge of the shelf.
///
/// It sits between the launcher and the application strip and only appears
/// while monitor-local workspaces are enabled. Each dot jumps straight to its
/// workspace; the compositor stays authoritative and echoes the new active
/// workspace back through the shell action channel.
class ShelfWorkspaceButton extends ConsumerWidget {
  const ShelfWorkspaceButton({this.monitorId, super.key});

  /// Output whose workspaces this indicator controls. Null keeps the control
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
      desktopWorkspaceProvider.select((state) => state.workspaceCount),
    );
    final active = ref.watch(
      desktopWorkspaceProvider.select(
        (state) => state.activeWorkspaceFor(monitorId),
      ),
    );
    final placements = ref.watch(
      desktopWorkspaceProvider.select((state) => state.placements),
    );
    final windowCounts = workspaceWindowCounts(
      placements.values,
      monitorId,
      workspaceCount,
    );

    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: ShellSpacing.md),
        child: Center(
          child: ShelfWorkspaceDots(
            workspaceCount: workspaceCount,
            activeWorkspace: active,
            windowCounts: windowCounts,
            onSelect: (workspaceId) {
              ref
                  .read(denialBridgeProvider)
                  .switchWorkspace(
                    monitorId: monitorId,
                    workspaceId: workspaceId,
                  );
            },
          ),
        ),
      ),
    );
  }
}
