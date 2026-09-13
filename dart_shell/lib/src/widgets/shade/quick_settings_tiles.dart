import 'dart:async';

import 'package:flutter/material.dart'
    show CircularProgressIndicator, Icons, IconData, Tooltip;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../localization/denial_localizations.dart';
import '../../services/power_profile_service.dart';
import '../../state/desktop_power_modes.dart';
import '../../theme/motion.dart';
import '../../theme/shell_color_scheme.dart';
import '../../theme/shell_theme.dart';
import '../../theme/tokens.dart';
import '../shell_expressive_surface.dart';

/// Where a tile sits inside a segmented row (02-VISUAL-SPEC §2): the row's
/// outer corners keep `extraLarge` while corners that touch a sibling
/// collapse to `small`, with a 2 dp seam between siblings.
enum QuickTileSegment { standalone, leading, middle, trailing }

/// The grid of quick-settings tiles: a 2×2 block of wide tiles over a third
/// row of one wide and two compact tiles. Purely presentational: every value
/// and callback is supplied by the panel.
class QuickSettingsTiles extends StatelessWidget {
  const QuickSettingsTiles({
    super.key,
    required this.wifi,
    required this.wifiSubtitle,
    required this.wifiEnabled,
    required this.wifiBusy,
    required this.bluetooth,
    required this.bluetoothSubtitle,
    required this.bluetoothEnabled,
    required this.bluetoothBusy,
    required this.dnd,
    required this.dndReady,
    required this.profile,
    required this.rotationLock,
    required this.darkTheme,
    required this.onToggleWifi,
    required this.onOpenWifi,
    required this.onToggleBluetooth,
    required this.onOpenBluetooth,
    required this.onToggleDnd,
    required this.onCycleProfile,
    required this.onScreenshot,
    required this.onToggleRotation,
    required this.onToggleDarkTheme,
    this.screenshotBusy = false,
  });

  final bool wifi;
  final String wifiSubtitle;
  final bool wifiEnabled;
  final bool wifiBusy;
  final bool bluetooth;
  final String bluetoothSubtitle;
  final bool bluetoothEnabled;
  final bool bluetoothBusy;
  final bool rotationLock;
  final bool darkTheme;
  final bool dnd;
  final bool dndReady;
  final String profile;
  final bool screenshotBusy;
  final VoidCallback onToggleWifi;
  final VoidCallback onOpenWifi;
  final VoidCallback onToggleBluetooth;
  final VoidCallback onOpenBluetooth;
  final VoidCallback onToggleRotation;
  final VoidCallback onToggleDarkTheme;
  final VoidCallback onToggleDnd;
  final VoidCallback onCycleProfile;
  final VoidCallback onScreenshot;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Segmented seams are 2 dp; the rows themselves sit 8 dp apart and
        // every tile is 56 dp tall (02-VISUAL-SPEC §4).
        const seam = 2.0;
        const rowGap = ShellSpacing.sm;
        const tileHeight = 56.0;
        final wide = (constraints.maxWidth - seam) / 2;
        final compact = (wide - seam * 2) / 2;

        return Column(
          children: [
            Row(
              children: [
                SizedBox(
                  width: wide,
                  height: tileHeight,
                  child: QuickTile(
                    icon: Icons.wifi_rounded,
                    title: l10n.commonWifi,
                    subtitle: wifiSubtitle,
                    active: wifi,
                    enabled: wifiEnabled,
                    busy: wifiBusy,
                    onTap: onToggleWifi,
                    onDetails: onOpenWifi,
                    wide: true,
                    segment: QuickTileSegment.leading,
                  ),
                ),
                const SizedBox(width: seam),
                SizedBox(
                  width: wide,
                  height: tileHeight,
                  child: QuickTile(
                    icon: Icons.bluetooth_rounded,
                    title: l10n.commonBluetooth,
                    subtitle: bluetoothSubtitle,
                    active: bluetooth,
                    enabled: bluetoothEnabled,
                    busy: bluetoothBusy,
                    onTap: onToggleBluetooth,
                    onDetails: onOpenBluetooth,
                    wide: true,
                    segment: QuickTileSegment.trailing,
                  ),
                ),
              ],
            ),
            const SizedBox(height: rowGap),
            Row(
              children: [
                SizedBox(
                  width: wide,
                  height: tileHeight,
                  child: QuickTile(
                    icon: darkTheme
                        ? Icons.dark_mode_rounded
                        : Icons.light_mode_rounded,
                    title: l10n.qsDarkTheme,
                    subtitle: darkTheme ? l10n.commonOn : l10n.commonOff,
                    active: darkTheme,
                    onTap: onToggleDarkTheme,
                    wide: true,
                    segment: QuickTileSegment.leading,
                  ),
                ),
                const SizedBox(width: seam),
                SizedBox(
                  width: wide,
                  height: tileHeight,
                  child: QuickTile(
                    icon: rotationLock
                        ? Icons.screen_lock_rotation_rounded
                        : Icons.screen_rotation_rounded,
                    title: l10n.quickSettingsRotation,
                    subtitle: rotationLock
                        ? l10n.quickSettingsLocked
                        : l10n.quickSettingsAutomatic,
                    active: rotationLock,
                    onTap: onToggleRotation,
                    wide: true,
                    segment: QuickTileSegment.trailing,
                  ),
                ),
              ],
            ),
            const SizedBox(height: rowGap),
            Row(
              children: [
                SizedBox(
                  width: wide,
                  height: tileHeight,
                  child: QuickTile(
                    icon: _profileIcon(profile),
                    title: l10n.quickSettingsPerformance,
                    subtitle: _profileLabel(profile, l10n),
                    active: profile != PowerProfile.balanced,
                    onTap: onCycleProfile,
                    wide: true,
                    segment: QuickTileSegment.leading,
                  ),
                ),
                const SizedBox(width: seam),
                SizedBox(
                  width: compact,
                  height: tileHeight,
                  child: QuickTile(
                    icon: Icons.notifications_off_rounded,
                    title: l10n.quickSettingsSilent,
                    active: dnd,
                    enabled: dndReady,
                    onTap: onToggleDnd,
                    wide: false,
                    segment: QuickTileSegment.middle,
                  ),
                ),
                const SizedBox(width: seam),
                SizedBox(
                  width: compact,
                  height: tileHeight,
                  child: QuickTile(
                    icon: Icons.screenshot_monitor_rounded,
                    title: l10n.quickSettingsScreenshot,
                    active: false,
                    busy: screenshotBusy,
                    onTap: onScreenshot,
                    wide: false,
                    segment: QuickTileSegment.trailing,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// A single quick-settings tile.
///
/// Resting shape is the tile's segmented slot ([segment]); activation and
/// press morph the corners toward `ShellShapeScale.full` on
/// `Motion.expressiveEffectsFast` while the fill lerps between
/// `surfaceContainerHigh` and `primary` on `Motion.expressiveEffectsDefault`
/// (02-VISUAL-SPEC §2/§5 — the shape switch is animated, never instant).
class QuickTile extends StatefulWidget {
  const QuickTile({
    super.key,
    required this.icon,
    required this.title,
    required this.active,
    required this.onTap,
    this.subtitle,
    this.wide = false,
    this.enabled = true,
    this.busy = false,
    this.onDetails,
    this.segment = QuickTileSegment.standalone,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool active;
  final VoidCallback onTap;
  final bool wide;
  final bool enabled;
  final bool busy;
  final VoidCallback? onDetails;
  final QuickTileSegment segment;

  @override
  State<QuickTile> createState() => _QuickTileState();
}

class _QuickTileState extends State<QuickTile> with TickerProviderStateMixin {
  bool _focused = false;
  bool _hovered = false;
  bool _pressed = false;
  late final AnimationController _hoverController;
  late final AnimationController _pressController;
  late final AnimationController _shapeController;
  late final AnimationController _colorController;

  @override
  void initState() {
    super.initState();
    _hoverController = AnimationController.unbounded(vsync: this, value: 0.0);
    _pressController = AnimationController.unbounded(vsync: this, value: 0.0);
    _shapeController = AnimationController.unbounded(
      vsync: this,
      value: widget.active ? 1.0 : 0.0,
    );
    _colorController = AnimationController.unbounded(
      vsync: this,
      value: widget.active ? 1.0 : 0.0,
    );
  }

  @override
  void didUpdateWidget(covariant QuickTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) {
      _drive(
        _colorController,
        widget.active ? 1.0 : 0.0,
        Motion.expressiveEffectsDefault,
        'quick_tile_active_color',
      );
      _updateShapeTarget();
    }
  }

  @override
  void dispose() {
    _hoverController.dispose();
    _pressController.dispose();
    _shapeController.dispose();
    _colorController.dispose();
    super.dispose();
  }

  void _updateHover(bool hovered) {
    if (_hovered == hovered || !widget.enabled) {
      return;
    }
    setState(() => _hovered = hovered);
    _drive(
      _hoverController,
      hovered ? 1.0 : 0.0,
      Motion.expressiveSpatialFast,
      'quick_tile_hover',
    );
  }

  void _updatePress(bool pressed) {
    if (_pressed == pressed || !widget.enabled) {
      return;
    }
    setState(() => _pressed = pressed);
    _drive(
      _pressController,
      pressed ? 1.0 : 0.0,
      Motion.expressiveSpatialFast,
      'quick_tile_press',
    );
    _updateShapeTarget();
  }

  /// Activation and press both morph the corners toward `full`; the shape
  /// settles back to the segmented slot once neither applies.
  void _updateShapeTarget() {
    _drive(
      _shapeController,
      (widget.active || _pressed) ? 1.0 : 0.0,
      Motion.expressiveEffectsFast,
      'quick_tile_shape',
    );
  }

  void _drive(
    AnimationController controller,
    double target,
    SpringDescription spring,
    String label,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) {
      controller.value = target;
      return;
    }
    springTo(
      controller,
      target,
      velocity: controller.velocity,
      spring: spring,
      telemetryLabel: label,
    );
  }

  /// The resting corner radii for this tile's slot in the segmented row:
  /// `extraLarge` on the row's outer edge, `small` against siblings.
  BorderRadius _segmentRadius(BuildContext context, QuickTileSegment segment) {
    final theme = context.shellTheme;
    final outer = theme.borderRadius(ShellShapeScale.extraLarge).topLeft;
    final inner = theme.borderRadius(ShellShapeScale.small).topLeft;
    final directional = switch (segment) {
      QuickTileSegment.leading => BorderRadiusDirectional.only(
        topStart: outer,
        bottomStart: outer,
        topEnd: inner,
        bottomEnd: inner,
      ),
      QuickTileSegment.trailing => BorderRadiusDirectional.only(
        topStart: inner,
        bottomStart: inner,
        topEnd: outer,
        bottomEnd: outer,
      ),
      QuickTileSegment.middle => BorderRadiusDirectional.all(inner),
      QuickTileSegment.standalone => BorderRadiusDirectional.all(outer),
    };
    return directional.resolve(Directionality.of(context));
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShellTheme.of(context);
    final accent = theme.accentPalette;
    final colors = context.shellColors;

    return Semantics(
      button: true,
      explicitChildNodes: widget.onDetails != null,
      enabled: widget.enabled,
      toggled: widget.active,
      label: widget.subtitle == null
          ? widget.title
          : context.l10n.commonTitleAndSubtitle(widget.title, widget.subtitle!),
      child: FocusableActionDetector(
        enabled: widget.enabled,
        mouseCursor: widget.enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onShowFocusHighlight: (focused) => setState(() => _focused = focused),
        onShowHoverHighlight: (hovered) => _updateHover(hovered),
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              if (widget.enabled) {
                widget.onTap();
              }
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => _updatePress(true),
          onTapUp: (_) => _updatePress(false),
          onTapCancel: () => _updatePress(false),
          onTap: widget.enabled ? widget.onTap : null,
          child: AnimatedBuilder(
            animation: Listenable.merge([
              _hoverController,
              _pressController,
              _shapeController,
              _colorController,
            ]),
            builder: (context, _) {
              final hoverT = _hoverController.value.clamp(0.0, 1.0);
              final pressT = _pressController.value.clamp(0.0, 1.0);
              final shapeT = _shapeController.value.clamp(0.0, 1.0);
              final colorT = _colorController.value.clamp(0.0, 1.0);

              // Inactive tiles sit on surfaceContainerHigh; activation fills
              // the tile with primary/onPrimary (02-VISUAL-SPEC §1.2).
              var background = Color.lerp(
                Color.lerp(
                  colors.surfaceContainerHigh,
                  colors.panelHighlight,
                  hoverT,
                )!,
                accent.primary,
                colorT,
              )!;
              if (pressT > 0) {
                background = Color.lerp(background, accent.subtle, pressT)!;
              }

              final radius = BorderRadius.lerp(
                _segmentRadius(context, widget.segment),
                theme.borderRadius(ShellShapeScale.full),
                shapeT,
              )!;
              final foreground = Color.lerp(
                colors.textPrimary,
                accent.onPrimary,
                colorT,
              )!;
              final secondary = Color.lerp(
                colors.textSecondary,
                accent.onPrimary.withValues(alpha: 0.82),
                colorT,
              )!;

              // The press reads as a spring-loaded dip, matching the shelf
              // icons these tiles sit next to.
              final scale = 1.0 - 0.06 * _pressController.value;

              return Transform.scale(
                scale: scale,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: background,
                    borderRadius: radius,
                    // Tiles are tonal surfaces with no resting outline; only
                    // the keyboard focus ring draws a border.
                    border: _focused
                        ? Border.all(
                            color: Color.lerp(
                              accent.primary,
                              accent.onPrimary,
                              colorT,
                            )!,
                            width: 1.5,
                          )
                        : null,
                  ),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: widget.wide ? ShellSpacing.md : 6,
                    ),
                    child: widget.wide
                        ? _buildWide(
                            foreground,
                            secondary,
                            colorT,
                            accent.primary,
                            colors,
                          )
                        : _buildSmall(foreground),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildWide(
    Color foreground,
    Color secondary,
    double colorT,
    Color activeColor,
    ShellColorScheme colors,
  ) {
    return Row(
      children: [
        _TileIcon(
          icon: widget.icon,
          busy: widget.busy,
          foreground: foreground,
          size: 32,
          iconSize: 20,
          // The disc reads on inactive tiles and dissolves into the primary
          // fill once the tile activates.
          discColor: Color.lerp(
            colors.surfaceContainerHighest,
            activeColor,
            colorT,
          )!,
        ),
        const SizedBox(width: ShellSpacing.sm),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ShellText.titleSmall.copyWith(color: foreground),
              ),
              if (widget.subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  widget.subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ShellText.bodySmall.copyWith(color: secondary),
                ),
              ],
            ],
          ),
        ),
        if (widget.onDetails != null) ...[
          const SizedBox(width: ShellSpacing.xs),
          _TileDetailsButton(
            label: context.l10n.quickSettingsOpenDetails(widget.title),
            foreground: foreground,
            onPressed: widget.onDetails!,
          ),
        ],
      ],
    );
  }

  Widget _buildSmall(Color foreground) {
    return Center(
      child: widget.busy
          ? Padding(
              padding: const EdgeInsets.all(14),
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: foreground,
              ),
            )
          : Icon(widget.icon, size: 24, color: foreground),
    );
  }
}

class _TileIcon extends StatelessWidget {
  const _TileIcon({
    required this.icon,
    required this.busy,
    required this.foreground,
    required this.size,
    required this.iconSize,
    this.discColor,
  });

  final IconData icon;
  final bool busy;
  final Color foreground;
  final double size;
  final double iconSize;

  /// Optional tonal disc behind the glyph (02-VISUAL-SPEC §4: the wide-tile
  /// icon sits on a Ø32 circle).
  final Color? discColor;

  @override
  Widget build(BuildContext context) {
    final discColor = this.discColor;
    final content = busy
        ? Padding(
            padding: EdgeInsets.all(size * 0.27),
            child: CircularProgressIndicator(strokeWidth: 2, color: foreground),
          )
        : Icon(icon, color: foreground, size: iconSize);
    return SizedBox(
      width: size,
      height: size,
      child: discColor == null
          ? Center(child: content)
          : DecoratedBox(
              decoration: BoxDecoration(
                color: discColor,
                shape: BoxShape.circle,
              ),
              child: Center(child: content),
            ),
    );
  }
}

class _TileDetailsButton extends StatefulWidget {
  const _TileDetailsButton({
    required this.label,
    required this.foreground,
    required this.onPressed,
  });

  final String label;
  final Color foreground;
  final VoidCallback onPressed;

  @override
  State<_TileDetailsButton> createState() => _TileDetailsButtonState();
}

class _TileDetailsButtonState extends State<_TileDetailsButton> {
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final accent = ShellTheme.of(context).accent;
    return Semantics(
      button: true,
      label: widget.label,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowFocusHighlight: (focused) => setState(() => _focused = focused),
        onShowHoverHighlight: (hovered) => setState(() => _hovered = hovered),
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onPressed();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: (_focused || _hovered)
                  ? widget.foreground.withValues(alpha: 0.14)
                  : ShellMediaColors.transparentDark,
              borderRadius: context.shellTheme.borderRadius(
                ShellShapeScale.full,
              ),
              border: _focused ? Border.all(color: accent) : null,
            ),
            child: SizedBox.square(
              dimension: 26,
              child: Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: widget.foreground,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The power-modes row from the §0.3 reference panel: a leading icon, a
/// "Power modes" label, and a column of Ø36 round buttons — one per system
/// profile — where the selected mode fills with `primary`.
///
/// This is the consumer-facing wrapper: it reads `desktopPowerModesProvider`
/// read-only and renders nothing while the host exposes no switchable system
/// profile.
class QuickSettingsModesSection extends ConsumerWidget {
  const QuickSettingsModesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modes = ref.watch(
      desktopPowerModesProvider.select(
        (state) => (
          available: state.systemAvailable,
          profile: state.systemProfile,
          changing: state.systemChanging,
        ),
      ),
    );
    if (!modes.available) {
      return const SizedBox.shrink();
    }
    final controller = ref.read(desktopPowerModesProvider.notifier);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: ShellSpacing.sm),
        QuickSettingsModesRow(
          profile: modes.profile,
          changing: modes.changing,
          onSelect: (profile) =>
              unawaited(controller.selectSystemProfile(profile)),
        ),
      ],
    );
  }
}

/// Presentational modes row: icon + label + Ø36 round mode buttons.
class QuickSettingsModesRow extends StatelessWidget {
  const QuickSettingsModesRow({
    super.key,
    required this.profile,
    required this.changing,
    required this.onSelect,
  });

  /// The currently selected `PowerProfile` value.
  final String profile;

  /// Whether a profile change is in flight; buttons stay disabled while it
  /// applies.
  final bool changing;

  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.shellColors;
    final l10n = context.l10n;
    final modes = <(String, IconData, String)>[
      (
        PowerProfile.powerSave,
        Icons.energy_savings_leaf_rounded,
        l10n.desktopSystemProfilePowerSaver,
      ),
      (
        PowerProfile.balanced,
        Icons.balance_rounded,
        l10n.desktopSystemProfileBalanced,
      ),
      (
        PowerProfile.performance,
        Icons.speed_rounded,
        l10n.desktopSystemProfilePerformance,
      ),
    ];
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          Icon(Icons.tune_rounded, size: 20, color: colors.textSecondary),
          const SizedBox(width: ShellSpacing.sm),
          Expanded(
            child: Text(
              l10n.desktopPowerModesTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ShellText.labelLarge.copyWith(color: colors.textPrimary),
            ),
          ),
          for (var i = 0; i < modes.length; i++) ...[
            if (i != 0) const SizedBox(width: ShellSpacing.sm),
            _ModeButton(
              icon: modes[i].$2,
              label: modes[i].$3,
              selected: profile == modes[i].$1,
              busy: changing && profile == modes[i].$1,
              enabled: !changing,
              onTap: () => onSelect(modes[i].$1),
            ),
          ],
        ],
      ),
    );
  }
}

/// One Ø36 round mode button: tonal when idle, `primary` + `onPrimary` when
/// selected.
class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.busy,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool busy;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final accent = theme.accentPalette;
    final colors = context.shellColors;
    return ShellExpressiveSurface(
      onPressed: enabled ? onTap : null,
      enabled: enabled,
      shape: ShellShapeScale.full,
      color: selected ? accent.primary : colors.surfaceContainerHigh,
      width: 36,
      height: 36,
      semanticLabel: label,
      tooltip: label,
      child: busy
          ? SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: selected ? accent.onPrimary : colors.textPrimary,
              ),
            )
          : Icon(
              icon,
              size: 18,
              color: selected ? accent.onPrimary : colors.textPrimary,
            ),
    );
  }
}

/// Compact shade actions. Application-count prose belongs in the overview,
/// not in quick settings.
class ShadeFooter extends StatelessWidget {
  const ShadeFooter({super.key, required this.onOpenPower});

  final VoidCallback onOpenPower;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        _RoundButton(
          label: context.l10n.quickSettingsSettingsUnavailable,
          icon: Icons.settings_rounded,
        ),
        const SizedBox(width: 12),
        _RoundButton(
          label: context.l10n.desktopOpenPowerControls,
          icon: Icons.power_settings_new_rounded,
          onPressed: onOpenPower,
        ),
      ],
    );
  }
}

class _RoundButton extends StatefulWidget {
  const _RoundButton({required this.label, required this.icon, this.onPressed});

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  State<_RoundButton> createState() => _RoundButtonState();
}

class _RoundButtonState extends State<_RoundButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final accent = ShellTheme.of(context).accent;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: Tooltip(
        message: widget.label,
        child: FocusableActionDetector(
          enabled: enabled,
          mouseCursor: enabled
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          onShowFocusHighlight: (focused) => setState(() => _focused = focused),
          shortcuts: const <ShortcutActivator, Intent>{
            SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
          },
          actions: <Type, Action<Intent>>{
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                widget.onPressed?.call();
                return null;
              },
            ),
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onPressed,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: context.shellColors.chip,
                borderRadius: context.shellTheme.borderRadius(
                  ShellRadii.roundButton,
                ),
                border: _focused ? Border.all(color: accent) : null,
              ),
              child: SizedBox(
                width: 42,
                height: 42,
                child: Icon(
                  widget.icon,
                  color: enabled
                      ? context.shellTheme.accentPalette.onMutedContainer
                      : context.shellColors.textTertiary,
                  size: 21,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

IconData _profileIcon(String profile) => switch (profile) {
  PowerProfile.powerSave => Icons.energy_savings_leaf_rounded,
  PowerProfile.performance => Icons.speed_rounded,
  _ => Icons.balance_rounded,
};

String _profileLabel(String profile, AppLocalizations l10n) =>
    switch (profile) {
      PowerProfile.powerSave => l10n.quickSettingsBatterySaver,
      PowerProfile.performance => l10n.quickSettingsHighPerformance,
      _ => l10n.quickSettingsBalanced,
    };
