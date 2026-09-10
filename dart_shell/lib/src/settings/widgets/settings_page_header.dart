import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../localization/denial_localizations.dart';
import '../../theme/motion.dart';
import '../../theme/shell_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/shell_cursor.dart';
import '../settings_category_colors.dart';
import 'settings_navigation.dart';

/// Expanded height of the page header (§3.8 / §2.2).
const double settingsPageHeaderExpandedHeight = 120;

/// Collapsed, pinned height of the page header (§3.8).
const double settingsPageHeaderCollapsedHeight = 64;

/// Diameter of the page's category hue circle in the header (§3.2).
const double settingsPageHeaderIconDiameter = 32;

/// Glyph size inside the header category circle (§4.3).
const double settingsPageHeaderIconGlyphSize = 18;

/// Fixed height of the header's title row, kept constant so collapsing never
/// reflows the leading icon or the trailing actions.
const double settingsPageHeaderTitleRowHeight = 40;

/// Identifies the single-column back affordance. Re-exported from
/// `settings_application.dart` so drill-down tests keep one import surface.
const settingsBackButtonKey = ValueKey<String>('settings-back-button');

/// Resolves the category hue pair behind a page glyph.
///
/// Pages hand [SettingsPageLayout] their [IconData] rather than a
/// [SettingsPageId]; the glyphs are unique per page (verified in
/// `settings_navigation.dart`), so the page — and therefore its hue — can be
/// recovered from the icon. Unknown glyphs fall back to the neutral treatment
/// used by the About page (§4.3).
SettingsCategoryHue settingsCategoryHueForIcon(
  BuildContext context,
  IconData icon,
) {
  for (final page in SettingsPageId.values) {
    if (page.icon == icon) {
      return SettingsCategoryColors.of(context, page);
    }
  }
  return (
    container: context.shellColors.surfaceContainerHigh,
    onContainer: context.shellColors.textSecondary,
  );
}

/// Makes the drill-down back affordance available to the page header (§2.3).
///
/// Only the single-column detail stage installs this scope, so the wide
/// two-column layout never renders a back button.
class SettingsPageBackScope extends InheritedWidget {
  const SettingsPageBackScope({
    required this.onBack,
    required super.child,
    super.key,
  });

  final VoidCallback onBack;

  static VoidCallback? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<SettingsPageBackScope>()
      ?.onBack;

  @override
  bool updateShouldNotify(SettingsPageBackScope oldWidget) =>
      oldWidget.onBack != onBack;
}

/// M3E large flexible page header (§3.8).
///
/// Rendered by [SettingsPageHeaderDelegate] inside a pinned
/// [SliverPersistentHeader]; [collapse] interpolates 0 (expanded) → 1
/// (collapsed) and is driven by the page's scroll offset, so the header stops
/// moving the instant scrolling stops.
class SettingsPageHeader extends StatelessWidget {
  const SettingsPageHeader({
    required this.icon,
    required this.title,
    required this.collapse,
    required this.overlapsContent,
    this.trailing,
    super.key,
  });

  final IconData icon;
  final String title;
  final double collapse;

  /// Whether the scrolling content currently passes behind the pinned header.
  /// The backing fill only appears then, so the top of the page never shows a
  /// double-composited band.
  final bool overlapsContent;

  /// Trailing actions (the live-changes badge and the page reset button).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = ShellTheme.of(context);
    final colors = context.shellColors;
    final hue = settingsCategoryHueForIcon(context, icon);
    final onBack = SettingsPageBackScope.maybeOf(context);
    final t = collapse.clamp(0.0, 1.0);
    // Row bottom inset moves 16 (expanded) → 12 (collapsed) so the 40dp row
    // centres inside the 64dp bar once fully collapsed.
    final bottomInset = 16 + (12 - 16) * t;
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          if (overlapsContent)
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(
                  color: theme.panelColor(colors.panelBackground),
                ),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: bottomInset,
            child: Row(
              children: <Widget>[
                if (onBack != null) ...<Widget>[
                  _SettingsBackButton(onPressed: onBack),
                  const SizedBox(width: 12),
                ],
                _PageHeaderIcon(hue: hue, icon: icon),
                const SizedBox(width: 12),
                Expanded(
                  child: _PageHeaderTitle(title: title, collapse: t),
                ),
                if (trailing case final trailing?) ...<Widget>[
                  const SizedBox(width: 12),
                  trailing,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Pinned sliver delegate driving [SettingsPageHeader] (§3.8).
class SettingsPageHeaderDelegate extends SliverPersistentHeaderDelegate {
  const SettingsPageHeaderDelegate({
    required this.icon,
    required this.title,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final Widget? trailing;

  @override
  double get minExtent => settingsPageHeaderCollapsedHeight;

  @override
  double get maxExtent => settingsPageHeaderExpandedHeight;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final span = maxExtent - minExtent;
    var collapse = span <= 0 ? 1.0 : (shrinkOffset / span).clamp(0.0, 1.0);
    if (MediaQuery.disableAnimationsOf(context)) {
      // The reduced-motion preference snaps the title between the two roles
      // instead of cross-fading it.
      collapse = collapse >= 0.5 ? 1.0 : 0.0;
    }
    return SettingsPageHeader(
      icon: icon,
      title: title,
      collapse: collapse,
      overlapsContent: overlapsContent,
      trailing: trailing,
    );
  }

  @override
  bool shouldRebuild(covariant SettingsPageHeaderDelegate oldDelegate) =>
      oldDelegate.icon != icon ||
      oldDelegate.title != title ||
      oldDelegate.trailing != trailing;
}

class _PageHeaderIcon extends StatelessWidget {
  const _PageHeaderIcon({required this.hue, required this.icon});

  final SettingsCategoryHue hue;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: settingsPageHeaderIconDiameter,
      height: settingsPageHeaderIconDiameter,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: hue.container,
          borderRadius: ShellTheme.of(
            context,
          ).borderRadius(ShellShapeScale.full),
        ),
        child: Center(
          child: Icon(
            icon,
            size: settingsPageHeaderIconGlyphSize,
            color: hue.onContainer,
          ),
        ),
      ),
    );
  }
}

class _PageHeaderTitle extends StatelessWidget {
  const _PageHeaderTitle({required this.title, required this.collapse});

  final String title;
  final double collapse;

  @override
  Widget build(BuildContext context) {
    final color = context.shellColors.textPrimary;
    // Both roles share the fixed row height, so cross-fading them cannot
    // reflow the header (constraint §D5 keeps letter spacing at zero).
    return SizedBox(
      height: settingsPageHeaderTitleRowHeight,
      child: Stack(
        alignment: Alignment.centerLeft,
        children: <Widget>[
          Opacity(
            opacity: 1 - collapse,
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ShellText.settingsPageTitle.copyWith(color: color),
            ),
          ),
          Opacity(
            opacity: collapse,
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ShellText.settingsPageTitleCollapsed.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// 40dp circular back affordance (§2.3), shown only in the single-column
/// detail stage via [SettingsPageBackScope].
class _SettingsBackButton extends StatefulWidget {
  const _SettingsBackButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<_SettingsBackButton> createState() => _SettingsBackButtonState();
}

class _SettingsBackButtonState extends State<_SettingsBackButton> {
  var _hovered = false;
  var _focused = false;

  @override
  Widget build(BuildContext context) {
    final theme = ShellTheme.of(context);
    final palette = theme.accentPalette;
    final highlighted = _hovered || _focused;
    final motionDuration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : Motion.tile;
    return Semantics(
      button: true,
      label: context.l10n.settingsBackAction,
      child: FocusableActionDetector(
        mouseCursor: ShellMouseCursors.link,
        onShowHoverHighlight: (value) => setState(() => _hovered = value),
        onShowFocusHighlight: (value) => setState(() => _focused = value),
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
          key: settingsBackButtonKey,
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: motionDuration,
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: highlighted
                  ? context.shellColors.surfaceContainerHighest
                  : context.shellColors.surfaceContainerHigh,
              borderRadius: theme.borderRadius(ShellShapeScale.full),
              border: Border.all(
                color: _focused
                    ? palette.primary
                    : context.shellColors.hairline,
                width: _focused ? 2 : 1,
              ),
            ),
            child: Icon(
              Icons.arrow_back,
              size: 20,
              color: palette.primary,
            ),
          ),
        ),
      ),
    );
  }
}

/// M3 fade-through page transition (§7).
///
/// The outgoing page fades out in place over [exitDuration]; the incoming page
/// fades in while travelling [enterOffset] pixels (up by default, down when
/// [reverse] is set for a single-column drill-down return). Durations scale
/// with the user's `animationDurationScale` and collapse to zero when the
/// system asks for reduced motion (constraint §D4).
class SettingsPageTransition extends StatelessWidget {
  const SettingsPageTransition({
    required this.child,
    this.durationScale = 1.0,
    this.reverse = false,
    super.key,
  });

  static const Duration enterDuration = Duration(milliseconds: 300);
  static const Duration exitDuration = Duration(milliseconds: 120);
  static const double enterOffset = 8;

  final Widget child;
  final double durationScale;

  /// Reverses the incoming travel so a drill-down return enters from above.
  final bool reverse;

  @override
  Widget build(BuildContext context) {
    final disabled = MediaQuery.disableAnimationsOf(context);
    Duration scaled(Duration base) {
      if (disabled || durationScale <= 0) {
        return Duration.zero;
      }
      return Duration(
        microseconds: (base.inMicroseconds * durationScale).round(),
      );
    }

    return AnimatedSwitcher(
      duration: scaled(enterDuration),
      reverseDuration: scaled(exitDuration),
      switchInCurve: Motion.md3EmphasizedDecelerate,
      switchOutCurve: Motion.md3EmphasizedAccelerate,
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: Alignment.topCenter,
        fit: StackFit.expand,
        children: <Widget>[...previousChildren, ?currentChild],
      ),
      transitionBuilder: (child, animation) =>
          _FadeThroughPage(animation: animation, reverse: reverse, child: child),
      child: child,
    );
  }
}

class _FadeThroughPage extends StatefulWidget {
  const _FadeThroughPage({
    required this.animation,
    required this.reverse,
    required this.child,
  });

  final Animation<double> animation;
  final bool reverse;
  final Widget child;

  @override
  State<_FadeThroughPage> createState() => _FadeThroughPageState();
}

class _FadeThroughPageState extends State<_FadeThroughPage> {
  @override
  void initState() {
    super.initState();
    widget.animation.addStatusListener(_onStatusChanged);
  }

  @override
  void didUpdateWidget(covariant _FadeThroughPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation != widget.animation) {
      oldWidget.animation.removeStatusListener(_onStatusChanged);
      widget.animation.addStatusListener(_onStatusChanged);
    }
  }

  @override
  void dispose() {
    widget.animation.removeStatusListener(_onStatusChanged);
    super.dispose();
  }

  void _onStatusChanged(AnimationStatus status) {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.animation.status;
    // An outgoing page only fades: it must not slide back out.
    final exiting =
        status == AnimationStatus.reverse || status == AnimationStatus.dismissed;
    final progress = widget.animation.value.clamp(0.0, 1.0);
    final slide = exiting ? 0.0 : (1 - progress);
    final direction = widget.reverse ? -1.0 : 1.0;
    return FadeTransition(
      opacity: widget.animation,
      child: Transform.translate(
        offset: Offset(0, direction * SettingsPageTransition.enterOffset * slide),
        child: widget.child,
      ),
    );
  }
}
