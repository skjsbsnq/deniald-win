part of 'desktop_widgets.dart';

/// Quick-action pill row: one translucent capsule holding circular tonal
/// buttons (02-VISUAL-SPEC.md §6, 参考图 3). Every action delegates to the
/// existing provider/service entry points — this widget calls them, it does
/// not reimplement them.
class QuickActionPillRow extends ConsumerWidget {
  const QuickActionPillRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.shellTheme;
    final colors = context.shellColors;
    final l10n = context.l10n;
    final dndActive = ref.watch(
      desktopNotificationsProvider.select((state) => state.doNotDisturb),
    );

    final buttons = <Widget>[
      _QuickActionButton(
        icon: Icons.screenshot_monitor_rounded,
        label: l10n.quickSettingsScreenshot,
        onPressed: () =>
            unawaited(ref.read(quickSettingsProvider.notifier).takeScreenshot()),
      ),
      _QuickActionButton(
        icon: dndActive
            ? Icons.do_not_disturb_on_rounded
            : Icons.do_not_disturb_off_rounded,
        label: dndActive
            ? l10n.notificationsDisableDoNotDisturb
            : l10n.notificationsEnableDoNotDisturb,
        active: dndActive,
        onPressed: () =>
            ref.read(desktopNotificationsProvider.notifier).toggleDoNotDisturb(),
      ),
      _QuickActionButton(
        icon: Icons.lock_rounded,
        label: l10n.powerActionLock,
        onPressed: () => unawaited(
          ref
              .read(sessionPowerProvider.notifier)
              .request(SessionPowerAction.lock),
        ),
      ),
      _QuickActionButton(
        icon: Icons.settings_outlined,
        label: l10n.settingsApplicationTitle,
        onPressed: () => launchSettingsPage(ref, context, null),
      ),
      _QuickActionButton(
        icon: Icons.power_settings_new_rounded,
        label: l10n.powerSessionTitle,
        onPressed: () => showPowerSessionSurface(ref),
      ),
    ];

    return Semantics(
      label: l10n.widgetQuickActionsLabel,
      container: true,
      child: DesktopWidgetEntrance(
        child: Center(
          child: DesktopWidgetSurface(
            shape: RoundedRectangleBorder(
              borderRadius: theme.borderRadius(ShellShapeScale.full),
            ),
            color: colors.surfaceContainerHigh,
            padding: const EdgeInsets.symmetric(
              horizontal: ShellSpacing.md,
              vertical: ShellSpacing.sm,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < buttons.length; i += 1) ...[
                  if (i > 0) const SizedBox(width: ShellSpacing.sm),
                  buttons[i],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One Ø40 tonal circle inside the pill; `ShellExpressiveSurface` supplies
/// the press spring, focus ring, and keyboard activation (§D7).
class _QuickActionButton extends StatelessWidget {
  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final palette = context.shellTheme.accentPalette;
    final background = active
        ? palette.primary
        : palette.secondaryContainer;
    final foreground = active
        ? palette.onPrimary
        : palette.onSecondaryContainer;
    return ShellExpressiveSurface(
      onPressed: onPressed,
      shape: ShellShapeScale.full,
      color: background,
      width: 40,
      height: 40,
      semanticLabel: label,
      tooltip: label,
      child: Icon(icon, size: 20, color: foreground),
    );
  }
}
