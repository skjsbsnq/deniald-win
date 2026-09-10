import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../localization/denial_localizations.dart';
import '../../settings/settings_controller.dart';
import '../../state/shell_controller.dart';
import '../../theme/motion.dart';
import '../../theme/shell_theme.dart';
import '../../theme/tokens.dart';
import '../desktop_workspace.dart';

/// ChromeOS-style Desk button on the left edge of the shelf.
///
/// It sits between the launcher and the application strip and only appears
/// while monitor-local workspaces are enabled. A tap advances the monitor to
/// its next workspace; the compositor stays authoritative and echoes the new
/// active workspace back through the shell action channel.
class ShelfWorkspaceButton extends ConsumerStatefulWidget {
  const ShelfWorkspaceButton({this.monitorId, super.key});

  /// Output whose workspace this button controls. Null keeps the control
  /// hidden because a workspace switch is always monitor-local.
  final int? monitorId;

  static const double height = 36.0;

  @override
  ConsumerState<ShelfWorkspaceButton> createState() =>
      _ShelfWorkspaceButtonState();
}

class _ShelfWorkspaceButtonState extends ConsumerState<ShelfWorkspaceButton>
    with TickerProviderStateMixin {
  late final AnimationController _hoverController;
  late final AnimationController _pressController;
  bool _hovered = false;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _hoverController = AnimationController.unbounded(vsync: this, value: 0.0);
    _pressController = AnimationController.unbounded(vsync: this, value: 0.0);
  }

  @override
  void dispose() {
    _hoverController.dispose();
    _pressController.dispose();
    super.dispose();
  }

  void _updateHover(bool hovered) {
    if (_hovered == hovered) {
      return;
    }
    setState(() => _hovered = hovered);
    _drive(_hoverController, hovered ? 1.0 : 0.0, 'shelf_workspace_hover');
  }

  void _updatePress(bool pressed) {
    if (_pressed == pressed) {
      return;
    }
    setState(() => _pressed = pressed);
    _drive(_pressController, pressed ? 1.0 : 0.0, 'shelf_workspace_press');
  }

  // Reduce-motion users get the end state directly; hover and press springs
  // are decorative overshoot.
  void _drive(AnimationController controller, double target, String label) {
    if (MediaQuery.disableAnimationsOf(context)) {
      controller.value = target;
      return;
    }
    springTo(
      controller,
      target,
      spring: Motion.expressiveSpatialFast,
      telemetryLabel: label,
    );
  }

  void _switchToNextWorkspace(int monitorId, int workspaceCount, int active) {
    final next = active >= workspaceCount ? 1 : active + 1;
    ref
        .read(denialBridgeProvider)
        .switchWorkspace(monitorId: monitorId, workspaceId: next);
  }

  @override
  Widget build(BuildContext context) {
    final monitorId = widget.monitorId;
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
    final borderRadius = theme.borderRadius(ShellShapeScale.full);
    final label = '${l10n.desktopWorkspaceDesk} $active';

    return Tooltip(
      message: l10n.desktopWorkspaceSwitch,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => _updateHover(true),
        onExit: (_) => _updateHover(false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => _updatePress(true),
          onTapUp: (_) => _updatePress(false),
          onTapCancel: () => _updatePress(false),
          onTap: () =>
              _switchToNextWorkspace(monitorId, workspaceCount, active),
          child: Semantics(
            button: true,
            label: '${l10n.desktopWorkspaceSwitch}, $label',
            child: SizedBox(
              height: ShelfWorkspaceButton.height,
              child: AnimatedBuilder(
                animation: Listenable.merge([
                  _hoverController,
                  _pressController,
                ]),
                builder: (context, child) {
                  final hoverT = _hoverController.value.clamp(0.0, 1.0);
                  final pressT = _pressController.value.clamp(0.0, 1.0);
                  final hoverColor = Color.lerp(
                    Colors.transparent,
                    colors.panelHighlight,
                    hoverT,
                  );
                  final backgroundColor = Color.lerp(
                    hoverColor,
                    theme.accentPalette.subtle,
                    pressT,
                  );
                  final scale = 1.0 - 0.04 * _pressController.value;
                  return Transform.scale(
                    scale: scale,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: backgroundColor,
                        borderRadius: borderRadius,
                      ),
                      child: child,
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.space_dashboard_outlined,
                        size: 18,
                        color: colors.textPrimary,
                      ),
                      const SizedBox(width: 6.0),
                      Text(
                        label,
                        style: theme.text.systemBarValue.copyWith(
                          color: colors.textPrimary,
                        ),
                        maxLines: 1,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
