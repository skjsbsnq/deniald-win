import 'dart:math' as math;
import 'dart:ui' show SemanticsRole;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../localization/denial_localizations.dart';
import '../../models/shell_popup_placement.dart';
import '../../theme/motion.dart';
import '../../theme/shell_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/shell_cursor.dart';
import '../color_format.dart';
import 'settings_buttons.dart';
import 'settings_menu.dart';
import 'settings_page_header.dart';

/// Identifies the page's single scroll view, so tests can drive the header
/// collapse.
const settingsPageScrollKey = ValueKey<String>('settings-page-scroll');

/// Gap between the page header and the first group container (§3.1).
const double settingsPageContentGap = 16;

/// Page skeleton: a pinned large page header above the scrolling content
/// column (§3.1/§3.8).
///
/// The public API is unchanged — [eyebrow] is retained for accessibility and
/// logging call sites but is no longer painted as an all-caps eyebrow; the
/// page's colour now comes from the header's category hue circle (§3.2).
class SettingsPageLayout extends StatelessWidget {
  const SettingsPageLayout({
    required this.icon,
    required this.eyebrow,
    required this.title,
    this.subtitle,
    required this.children,
    this.onReset,
    super.key,
  });

  final IconData icon;
  final String eyebrow;
  final String title;
  final String? subtitle;
  final List<Widget> children;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    final trailing = onReset == null
        ? null
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const SettingsSavedBadge(),
              const SizedBox(width: 8),
              SettingsTextButton(
                label: context.l10n.settingsResetPage,
                onPressed: onReset,
              ),
            ],
          );
    return CustomScrollView(
      key: settingsPageScrollKey,
      slivers: <Widget>[
        SliverPersistentHeader(
          pinned: true,
          delegate: SettingsPageHeaderDelegate(
            icon: icon,
            title: title,
            subtitle: subtitle,
            trailing: trailing,
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.only(
            top: settingsPageContentGap,
            bottom: 24,
          ),
          // The children stay eagerly built (as the previous single-child
          // scroll view did) so in-page state is never recycled while
          // scrolling.
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (var index = 0; index < children.length; index++) ...[
                  if (index > 0)
                    const SizedBox(height: settingsPageContentGap),
                  children[index],
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class SettingsSavedBadge extends StatelessWidget {
  const SettingsSavedBadge({super.key});

  /// Badge height (§3.4).
  static const double height = 24;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Semantics(
      label: l10n.settingsLiveChangesSemanticsLabel,
      child: Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: context.shellColors.surfaceContainerHigh,
          borderRadius: context.shellTheme.borderRadius(ShellShapeScale.full),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: context.shellColors.gestureArmed,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 7),
            Text(
              l10n.settingsLiveBadge,
              style: ShellText.settingsBadgeLabel.copyWith(
                color: context.shellColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Indent applied to card row dividers when indented to align with content text (§3.3).
const double settingsRowDividerIndent = 56;

/// One-device-pixel separator painted with `hairlineSoft` (§1.2 dividers use
/// `outlineVariant`-class hairlines).
///
/// Shared replacement for Material's `Divider` so no Material list/divider
/// widget leaks into the settings surface.
class SettingsHairline extends StatelessWidget {
  const SettingsHairline({this.indent = 0, super.key});

  /// Leading inset aligning the line with row content (see
  /// [settingsRowDividerIndent]).
  final double indent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsetsDirectional.only(start: indent),
      child: SizedBox(
        height: 1,
        child: ColoredBox(color: context.shellColors.hairlineSoft),
      ),
    );
  }
}

class SettingsCardGroup extends StatelessWidget {
  const SettingsCardGroup({
    required this.children,
    this.dividerIndent,
    this.indentDividers = false,
    super.key,
  });

  final List<Widget> children;
  final double? dividerIndent;
  final bool indentDividers;

  @override
  Widget build(BuildContext context) {
    final theme = ShellTheme.of(context);
    final radius = theme.borderRadius(ShellShapeScale.extraLarge);
    final effectiveIndent =
        dividerIndent ?? (indentDividers ? settingsRowDividerIndent : 0.0);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.cardColor(context.shellColors.surfaceContainerLow),
        borderRadius: radius,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var index = 0; index < children.length; index++) ...[
              if (index > 0) SettingsHairline(indent: effectiveIndent),
              children[index],
            ],
          ],
        ),
      ),
    );
  }
}

/// External section header and card container (Android 16 tablet style, §3.1 / 2-A).
class SettingsSectionContainer extends StatelessWidget {
  const SettingsSectionContainer({
    this.title,
    this.trailing,
    required this.child,
    super.key,
  });

  final String? title;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (title == null) {
      return child;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title!,
                  style: ShellText.settingsSectionHeader.copyWith(
                    color: context.shellColors.textSecondary,
                  ),
                ),
              ),
              if (trailing case final trailing?) trailing,
            ],
          ),
        ),
        child,
      ],
    );
  }
}

class SettingsSection extends StatelessWidget {
  const SettingsSection({
    required this.title,
    required this.child,
    this.leading,
    this.status,
    this.trailing,
    super.key,
  });

  final String title;
  final Widget child;

  /// Optional section guide mark.
  ///
  /// Existing pages hand in functional marks (battery glyphs, status dots,
  /// thumbnails). Those keep their own rendering — the §4.3 hue circle only
  /// applies to decorative page glyphs and is therefore owned by the page
  /// header (§3.2), not re-derived here where the page hue is unknown.
  final Widget? leading;
  final String? status;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (leading case final leading?) ...[
                leading,
                const SizedBox(width: 11),
              ],
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ShellText.settingsSectionHeader.copyWith(
                    color: context.shellColors.textPrimary,
                  ),
                ),
              ),
              if (status case final status?) ...[
                const SizedBox(width: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 180),
                  child: Text(
                    status,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: ShellText.settingsRowSupport.copyWith(
                      color: context.shellColors.textSecondary,
                    ),
                  ),
                ),
              ],
              if (trailing case final trailing?) ...[
                const SizedBox(width: 12),
                trailing,
              ],
            ],
          ),
          const SizedBox(height: 13),
          child,
        ],
      ),
    );
  }
}

/// M3E slider geometry (`02-VISUAL-SPEC.md` §3.5).
const double settingsSliderTrackHeight = 16;
const double settingsSliderHandleWidth = 4;
const double settingsSliderHandleHeight = 44;
const double settingsSliderHandleGap = 6;
const double settingsSliderTickDiameter = 4;
const double settingsSliderMinimumTrackWidth = 144;

/// Key for the slider's [SliderTheme], so tests can assert its geometry.
const Key settingsSliderThemeKey = ValueKey<String>('settings_slider_theme');

class SettingsSlider extends StatelessWidget {
  const SettingsSlider({
    required this.label,
    required this.value,
    required this.minimum,
    required this.maximum,
    required this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
    this.divisions,
    this.valueLabel,
    this.enabled = true,
    super.key,
  });

  final String label;
  final double value;
  final double minimum;
  final double maximum;
  final int? divisions;
  final String? valueLabel;
  final bool enabled;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeStart;
  final ValueChanged<double>? onChangeEnd;

  /// Fixed width of the label, gap and value columns in the three-column form.
  static const double _fixedRowWidth = 150 + 10 + 10 + 58;

  @override
  Widget build(BuildContext context) {
    final theme = ShellTheme.of(context);
    final palette = theme.accentPalette;
    final displayValue = valueLabel ?? value.toStringAsFixed(0);
    final valueStyle = ShellText.cardTitle.copyWith(
      fontFamily: ShellText.systemBarFontFamily,
    );
    return Semantics(
      slider: true,
      enabled: enabled,
      label: label,
      value: displayValue,
      child: AnimatedOpacity(
        duration: Motion.tile,
        opacity: enabled ? 1 : 0.46,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final available = constraints.maxWidth;
            // Three columns need room for the fixed label/value columns plus
            // the spec's 144dp minimum track (§3.5); below that the heading
            // and slider stack vertically.
            final threeColumn =
                available >= 430 &&
                (available - _fixedRowWidth) >=
                    settingsSliderMinimumTrackWidth;
            final heading = Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: ShellText.cardTitle.copyWith(
                      color: context.shellColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(displayValue, textAlign: TextAlign.right, style: valueStyle),
              ],
            );
            final slider = SliderTheme(
              key: settingsSliderThemeKey,
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: palette.primary,
                inactiveTrackColor: context.shellColors.surfaceContainerHighest,
                activeTickMarkColor: palette.onPrimary.withValues(alpha: 0.6),
                inactiveTickMarkColor: context.shellColors.hairline,
                thumbColor: palette.primary,
                overlayColor: palette.primary.withValues(alpha: 0.12),
                trackHeight: settingsSliderTrackHeight,
                trackShape: const _SettingsSliderTrackShape(
                  handleGap: settingsSliderHandleGap,
                ),
                thumbShape: _SettingsSliderHandleShape(
                  cornerRadiusScale: theme.cornerRadiusScale,
                ),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
                tickMarkShape: const RoundSliderTickMarkShape(
                  tickMarkRadius: settingsSliderTickDiameter / 2,
                ),
              ),
              child: Slider(
                value: value.clamp(minimum, maximum).toDouble(),
                min: minimum,
                max: maximum,
                divisions: divisions,
                onChanged: enabled ? onChanged : null,
                onChangeStart: enabled ? onChangeStart : null,
                onChangeEnd: enabled ? onChangeEnd : null,
              ),
            );
            if (!threeColumn) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [heading, const SizedBox(height: 3), slider],
              );
            }
            return Row(
              children: [
                SizedBox(
                  width: 150,
                  child: Text(
                    label,
                    style: ShellText.cardTitle.copyWith(
                      color: context.shellColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: slider),
                const SizedBox(width: 10),
                SizedBox(
                  width: 58,
                  child: Text(
                    displayValue,
                    textAlign: TextAlign.right,
                    style: valueStyle,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Draws the M3E track as two segments separated from the 4dp handle by the
/// spec's 6dp `ActiveHandleLeading/TrailingSpace` (§3.5).
class _SettingsSliderTrackShape extends SliderTrackShape
    with BaseSliderTrackShape {
  const _SettingsSliderTrackShape({required this.handleGap});

  final double handleGap;

  @override
  bool get isRounded => true;

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isEnabled = false,
    bool isDiscrete = false,
    required TextDirection textDirection,
  }) {
    final trackHeight = sliderTheme.trackHeight;
    if (trackHeight == null || trackHeight <= 0) {
      return;
    }
    final trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    final activeColor = ColorTween(
      begin: sliderTheme.disabledActiveTrackColor,
      end: sliderTheme.activeTrackColor,
    ).evaluate(enableAnimation)!;
    final inactiveColor = ColorTween(
      begin: sliderTheme.disabledInactiveTrackColor,
      end: sliderTheme.inactiveTrackColor,
    ).evaluate(enableAnimation)!;
    final canvas = context.canvas;
    final inset = handleGap + settingsSliderHandleWidth / 2;
    final thumbX = thumbCenter.dx.clamp(trackRect.left, trackRect.right);

    void drawSegment(double start, double end, Color color) {
      final left = math.min(start, end);
      final right = math.max(start, end);
      if (right - left <= 0.01) {
        return;
      }
      final radius = math.min(trackRect.height / 2, (right - left) / 2);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(left, trackRect.top, right, trackRect.bottom),
          Radius.circular(radius),
        ),
        Paint()..color = color,
      );
    }

    if (textDirection == TextDirection.ltr) {
      drawSegment(thumbX + inset, trackRect.right, inactiveColor);
      drawSegment(trackRect.left, thumbX - inset, activeColor);
    } else {
      drawSegment(trackRect.left, thumbX - inset, inactiveColor);
      drawSegment(thumbX + inset, trackRect.right, activeColor);
    }
  }
}

/// 4×44 full-rounded slider handle (§3.5).
class _SettingsSliderHandleShape extends SliderComponentShape {
  const _SettingsSliderHandleShape({required this.cornerRadiusScale});

  final double cornerRadiusScale;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(
    settingsSliderHandleWidth,
    settingsSliderHandleHeight,
  );

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final color = ColorTween(
      begin: sliderTheme.disabledThumbColor,
      end: sliderTheme.thumbColor,
    ).evaluate(enableAnimation)!;
    final rect = Rect.fromCenter(
      center: center,
      width: settingsSliderHandleWidth,
      height: settingsSliderHandleHeight,
    );
    final maximum = settingsSliderHandleWidth / 2;
    final radius = (maximum * cornerRadiusScale).clamp(0.0, maximum);
    context.canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(radius)),
      Paint()..color = color,
    );
  }
}

/// Key for the 52×32 M3E switch track, so tests can assert its geometry.
const Key settingsToggleTrackKey = ValueKey<String>('settings_toggle_track');

/// Key for the 40dp switch state layer, so tests can assert its presence.
const Key settingsToggleStateLayerKey = ValueKey<String>(
  'settings_toggle_state_layer',
);

/// Standalone M3E Switch component (`02-VISUAL-SPEC.md` §3.4).
class SettingsSwitch extends StatefulWidget {
  const SettingsSwitch({
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.pressed = false,
    this.hovered = false,
    this.focused = false,
    this.trackKey = settingsToggleTrackKey,
    this.stateLayerKey = settingsToggleStateLayerKey,
    super.key,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool enabled;
  final bool pressed;
  final bool hovered;
  final bool focused;
  final Key? trackKey;
  final Key? stateLayerKey;

  @override
  State<SettingsSwitch> createState() => _SettingsSwitchState();
}

class _SettingsSwitchState extends State<SettingsSwitch>
    with TickerProviderStateMixin {
  /// Track width / height (§3.4).
  static const double _trackWidth = 52;
  static const double _trackHeight = 32;
  static const double _thumbOff = 16;
  static const double _thumbOn = 24;
  static const double _thumbPressed = 28;
  static const double _stateLayerExtent = 40;

  late final AnimationController _positionController;
  late final AnimationController _colorController;

  @override
  void initState() {
    super.initState();
    _positionController = AnimationController.unbounded(
      vsync: this,
      value: widget.value ? 1.0 : 0.0,
    );
    _colorController = AnimationController(
      vsync: this,
      value: widget.value ? 1.0 : 0.0,
    );
  }

  @override
  void didUpdateWidget(covariant SettingsSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _animateTo(widget.value);
    }
  }

  @override
  void dispose() {
    _positionController.dispose();
    _colorController.dispose();
    super.dispose();
  }

  void _animateTo(bool value) {
    final target = value ? 1.0 : 0.0;
    if (MediaQuery.disableAnimationsOf(context)) {
      _positionController.value = target;
      _colorController.value = target;
      return;
    }
    springTo(
      _positionController,
      target,
      spring: Motion.expressiveSpatialFast,
      telemetryLabel: 'settings_toggle_spatial',
    );
    springTo(
      _colorController,
      target,
      spring: Motion.expressiveEffectsDefault,
      telemetryLabel: 'settings_toggle_effects',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShellTheme.of(context);
    final colors = context.shellColors;
    final palette = theme.accentPalette;
    final enabled = widget.enabled;
    final value = widget.value;
    final position = _positionController.value;
    final colorT = _colorController.value.clamp(0.0, 1.0);
    final alignment =
        Alignment.lerp(Alignment.centerLeft, Alignment.centerRight, position) ??
        Alignment.centerLeft;
    final baseThumb = _thumbOff + (_thumbOn - _thumbOff) * colorT;
    final thumbSize = widget.pressed && enabled ? _thumbPressed : baseThumb;
    final trackColor = Color.lerp(
      colors.surfaceContainerHighest,
      palette.primary,
      colorT,
    )!;
    final borderColor = Color.lerp(colors.hairline, palette.primary, colorT)!;
    final thumbColor = Color.lerp(colors.hairline, palette.onPrimary, colorT)!;
    final iconColor = Color.lerp(
      colors.surfaceContainerHighest,
      palette.onContainer,
      colorT,
    )!;
    final motionDuration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : Motion.tile;

    return AnimatedBuilder(
      animation: Listenable.merge([_positionController, _colorController]),
      builder: (context, _) => SizedBox(
        key: widget.trackKey,
        width: _trackWidth,
        height: _trackHeight,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: trackColor,
                  borderRadius: theme.borderRadius(ShellShapeScale.full),
                  border: Border.all(color: borderColor, width: 2),
                ),
              ),
            ),
            Align(
              alignment: alignment,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  key: widget.stateLayerKey,
                  duration: motionDuration,
                  opacity: widget.pressed || widget.hovered || widget.focused ? 1 : 0,
                  child: SizedBox.square(
                    dimension: _stateLayerExtent,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: palette.primary.withValues(
                          alpha: widget.pressed ? 0.12 : 0.08,
                        ),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(2),
              child: Align(
                alignment: alignment,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: thumbColor,
                    borderRadius: theme.borderRadius(ShellShapeScale.full),
                  ),
                  child: SizedBox.square(
                    dimension: thumbSize,
                    child: Center(
                      child: Icon(
                        value ? Icons.check_rounded : Icons.close_rounded,
                        size: 16,
                        color: iconColor,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SettingsToggle extends StatefulWidget {
  const SettingsToggle({
    required this.label,
    required this.description,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    super.key,
  });

  final String label;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  State<SettingsToggle> createState() => _SettingsToggleState();
}

class _SettingsToggleState extends State<SettingsToggle>
    with TickerProviderStateMixin {
  /// Track width / height (§3.4).
  static const double _trackWidth = 52;
  static const double _trackHeight = 32;
  static const double _thumbOff = 16;
  static const double _thumbOn = 24;
  static const double _thumbPressed = 28;
  static const double _stateLayerExtent = 40;

  late final AnimationController _positionController;
  late final AnimationController _colorController;
  var _pressed = false;
  var _hovered = false;
  var _focused = false;

  @override
  void initState() {
    super.initState();
    _positionController = AnimationController.unbounded(
      vsync: this,
      value: widget.value ? 1.0 : 0.0,
    );
    _colorController = AnimationController(
      vsync: this,
      value: widget.value ? 1.0 : 0.0,
    );
  }

  @override
  void didUpdateWidget(covariant SettingsToggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _animateTo(widget.value);
    }
  }

  @override
  void dispose() {
    _positionController.dispose();
    _colorController.dispose();
    super.dispose();
  }

  void _animateTo(bool value) {
    final target = value ? 1.0 : 0.0;
    if (MediaQuery.disableAnimationsOf(context)) {
      _positionController.value = target;
      _colorController.value = target;
      return;
    }
    springTo(
      _positionController,
      target,
      spring: Motion.expressiveSpatialFast,
      telemetryLabel: 'settings_toggle_spatial',
    );
    springTo(
      _colorController,
      target,
      spring: Motion.expressiveEffectsDefault,
      telemetryLabel: 'settings_toggle_effects',
    );
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled;
    final value = widget.value;
    final motionDuration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : Motion.tile;
    return Semantics(
      button: true,
      enabled: enabled,
      toggled: value,
      label: widget.label,
      child: FocusableActionDetector(
        enabled: enabled,
        mouseCursor: enabled
            ? ShellMouseCursors.link
            : SystemMouseCursors.basic,
        onShowHoverHighlight: (highlight) =>
            setState(() => _hovered = highlight),
        onShowFocusHighlight: (highlight) =>
            setState(() => _focused = highlight),
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              if (enabled) {
                widget.onChanged(!value);
              }
              return null;
            },
          ),
        },
        child: AnimatedOpacity(
          duration: motionDuration,
          opacity: enabled ? 1 : 0.46,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
            onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
            onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
            onTap: enabled ? () => widget.onChanged(!value) : null,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.label, style: ShellText.cardTitle),
                      const SizedBox(height: 4),
                      Text(
                        widget.description,
                        style: ShellText.base.copyWith(
                          color: context.shellColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 18),
                AnimatedBuilder(
                  animation: Listenable.merge([
                    _positionController,
                    _colorController,
                  ]),
                  builder: (context, _) => _buildSwitch(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSwitch(BuildContext context) {
    final theme = ShellTheme.of(context);
    final colors = context.shellColors;
    final palette = theme.accentPalette;
    final enabled = widget.enabled;
    final value = widget.value;
    final position = _positionController.value;
    final colorT = _colorController.value.clamp(0.0, 1.0);
    final alignment =
        Alignment.lerp(Alignment.centerLeft, Alignment.centerRight, position) ??
        Alignment.centerLeft;
    final baseThumb = _thumbOff + (_thumbOn - _thumbOff) * colorT;
    final thumbSize = _pressed && enabled ? _thumbPressed : baseThumb;
    final trackColor = Color.lerp(
      colors.surfaceContainerHighest,
      palette.primary,
      colorT,
    )!;
    final borderColor = Color.lerp(colors.hairline, palette.primary, colorT)!;
    final thumbColor = Color.lerp(colors.hairline, palette.onPrimary, colorT)!;
    final iconColor = Color.lerp(
      colors.surfaceContainerHighest,
      palette.onContainer,
      colorT,
    )!;
    final motionDuration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : Motion.tile;
    return SizedBox(
      key: settingsToggleTrackKey,
      width: _trackWidth,
      height: _trackHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: trackColor,
                borderRadius: theme.borderRadius(ShellShapeScale.full),
                border: Border.all(color: borderColor, width: 2),
              ),
            ),
          ),
          Align(
            alignment: alignment,
            child: IgnorePointer(
              child: AnimatedOpacity(
                key: settingsToggleStateLayerKey,
                duration: motionDuration,
                opacity: _pressed || _hovered || _focused ? 1 : 0,
                child: SizedBox.square(
                  dimension: _stateLayerExtent,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: palette.primary.withValues(
                        alpha: _pressed ? 0.12 : 0.08,
                      ),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(2),
            child: Align(
              alignment: alignment,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: thumbColor,
                  borderRadius: theme.borderRadius(ShellShapeScale.full),
                ),
                child: SizedBox.square(
                  dimension: thumbSize,
                  child: Center(
                    child: Icon(
                      value ? Icons.check_rounded : Icons.close_rounded,
                      size: 16,
                      color: iconColor,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Standard row heights defined by M3E specifications (`02-VISUAL-SPEC.md` §3.3).
const double settingsRowSingleLineHeight = 56;
const double settingsRowTwoLineHeight = 72;
const double settingsRowThreeLineHeight = 88;
const double settingsRowHorizontalPadding = 16;

/// M3E settings row family (`02-VISUAL-SPEC.md` §3.3).
///
/// Supports 56 (single-line), 72 (two-line) and 88dp (three-line/control) row heights,
/// leading icon or glyph circle, title/subtitle, trailing controls, and full-row
/// hover/press states with keyboard accessibility.
class SettingsRow extends StatefulWidget {
  const SettingsRow({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.enabled = true,
    this.selected = false,
    this.height,
    this.padding,
  });

  final Widget? leading;
  final Widget title;
  final Widget? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool enabled;

  /// Paints the row as the active selection: an `accentPalette.container`
  /// fill inside the `medium` list-item radius (§2), and `selected` in the
  /// accessibility semantics. Catalog pickers use this for the current value.
  final bool selected;
  final double? height;
  final EdgeInsetsGeometry? padding;

  /// Convenience constructor taking [String] texts with M3E typography roles.
  factory SettingsRow.text({
    Key? key,
    Widget? leading,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
    bool enabled = true,
    double? height,
    EdgeInsetsGeometry? padding,
  }) {
    return SettingsRow(
      key: key,
      leading: leading,
      title: Builder(
        builder: (context) => Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: ShellText.settingsRowTitle.copyWith(
            color: context.shellColors.textPrimary,
          ),
        ),
      ),
      subtitle: subtitle != null
          ? Builder(
              builder: (context) => Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ShellText.settingsRowSupport.copyWith(
                  color: context.shellColors.textSecondary,
                ),
              ),
            )
          : null,
      trailing: trailing,
      onTap: onTap,
      enabled: enabled,
      height: height,
      padding: padding,
    );
  }

  /// Full-row interactive switch row. Whole row tapping triggers the toggle.
  factory SettingsRow.toggle({
    Key? key,
    Widget? leading,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
    Key? toggleKey,
    bool enabled = true,
    EdgeInsetsGeometry? padding,
  }) {
    final effectiveHeight = subtitle != null
        ? settingsRowTwoLineHeight
        : settingsRowSingleLineHeight;
    return _SettingsToggleRow(
      key: key,
      leading: leading,
      toggleTitle: title,
      toggleSubtitle: subtitle,
      toggleValue: value,
      onToggleChanged: onChanged,
      toggleKey: toggleKey,
      enabled: enabled,
      height: effectiveHeight,
      padding: padding,
    );
  }

  /// Embedded slider row (88dp height) conforming to §3.3 and §3.5.
  factory SettingsRow.slider({
    Key? key,
    Widget? leading,
    required String title,
    String? subtitle,
    required double value,
    required ValueChanged<double>? onChanged,
    double minimum = 0.0,
    double maximum = 1.0,
    int? divisions,
    String? valueLabel,
    Key? sliderKey,
    bool enabled = true,
    EdgeInsetsGeometry? padding,
  }) {
    return SettingsRow(
      key: key,
      leading: leading,
      height: settingsRowThreeLineHeight,
      title: SettingsSlider(
        key: sliderKey,
        label: title,
        value: value,
        minimum: minimum,
        maximum: maximum,
        divisions: divisions,
        valueLabel: valueLabel,
        enabled: enabled,
        onChanged: onChanged ?? (_) {},
      ),
      subtitle: subtitle != null
          ? Builder(
              builder: (context) => Text(
                subtitle,
                style: ShellText.settingsRowSupport.copyWith(
                  color: context.shellColors.textSecondary,
                ),
              ),
            )
          : null,
      enabled: enabled,
      padding: padding,
    );
  }

  @override
  State<SettingsRow> createState() => _SettingsRowState();
}

class _SettingsRowState extends State<SettingsRow> {
  var _hovered = false;
  var _focused = false;
  var _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = ShellTheme.of(context);
    final colors = context.shellColors;
    final enabled = widget.enabled;
    final isInteractive = enabled && widget.onTap != null;

    final effectiveHeight = widget.height ??
        (widget.subtitle != null
            ? settingsRowTwoLineHeight
            : settingsRowSingleLineHeight);

    final Color backgroundColor;
    if (widget.selected) {
      // M3 state-layer values (hover 8%, pressed 12%) over the accent
      // container, matching the rest of the control family.
      var selectedColor = theme.cardColor(theme.accentPalette.container);
      if (_pressed && isInteractive) {
        selectedColor = Color.alphaBlend(
          theme.accentPalette.onContainer.withValues(alpha: 0.12),
          selectedColor,
        );
      } else if ((_hovered || _focused) && isInteractive) {
        selectedColor = Color.alphaBlend(
          theme.accentPalette.onContainer.withValues(alpha: 0.08),
          selectedColor,
        );
      }
      backgroundColor = selectedColor;
    } else if (_pressed && isInteractive) {
      backgroundColor = theme.cardColor(colors.surfaceContainerHighest);
    } else if ((_hovered || _focused) && isInteractive) {
      backgroundColor = theme.cardColor(colors.surfaceContainerHigh);
    } else {
      backgroundColor = Colors.transparent;
    }

    final motionDuration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : Motion.pill;

    Widget content = SizedBox(
      height: effectiveHeight,
      child: Padding(
        padding: widget.padding ??
            const EdgeInsets.symmetric(
              horizontal: settingsRowHorizontalPadding,
            ),
        child: Row(
          children: [
            if (widget.leading case final leading?) ...[
              leading,
              const SizedBox(width: 16),
            ],
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DefaultTextStyle.merge(
                    style: ShellText.settingsRowTitle.copyWith(
                      color: colors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    child: widget.title,
                  ),
                  if (widget.subtitle case final subtitle?) ...[
                    const SizedBox(height: 2),
                    DefaultTextStyle.merge(
                      style: ShellText.settingsRowSupport.copyWith(
                        color: colors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      child: subtitle,
                    ),
                  ],
                ],
              ),
            ),
            if (widget.trailing case final trailing?) ...[
              const SizedBox(width: 16),
              trailing,
            ],
          ],
        ),
      ),
    );

    return Semantics(
      button: isInteractive,
      enabled: enabled,
      selected: widget.selected ? true : null,
      child: FocusableActionDetector(
        enabled: isInteractive,
        mouseCursor: isInteractive
            ? ShellMouseCursors.link
            : SystemMouseCursors.basic,
        onShowHoverHighlight: (highlight) =>
            setState(() => _hovered = highlight),
        onShowFocusHighlight: (highlight) =>
            setState(() => _focused = highlight),
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              if (isInteractive) {
                widget.onTap?.call();
              }
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: isInteractive ? (_) => setState(() => _pressed = true) : null,
          onTapUp: isInteractive ? (_) => setState(() => _pressed = false) : null,
          onTapCancel: isInteractive ? () => setState(() => _pressed = false) : null,
          onTap: isInteractive ? widget.onTap : null,
          child: AnimatedContainer(
            duration: motionDuration,
            decoration: BoxDecoration(
              color: backgroundColor,
              // The selected card keeps the spec's medium list-item radius;
              // unselected rows stay rectangular so grouped hairlines and
              // card clipping are unchanged (§2 list-item radius).
              borderRadius: widget.selected
                  ? theme.borderRadius(ShellShapeScale.medium)
                  : null,
            ),
            child: content,
          ),
        ),
      ),
    );
  }
}

class _SettingsToggleRow extends SettingsRow {
  const _SettingsToggleRow({
    super.key,
    super.leading,
    required this.toggleTitle,
    this.toggleSubtitle,
    required this.toggleValue,
    required this.onToggleChanged,
    this.toggleKey,
    super.enabled = true,
    super.height,
    super.padding,
  }) : super(
         title: const SizedBox.shrink(),
       );

  final String toggleTitle;
  final String? toggleSubtitle;
  final bool toggleValue;
  final ValueChanged<bool>? onToggleChanged;
  final Key? toggleKey;

  @override
  State<SettingsRow> createState() => _SettingsToggleRowState();
}

class _SettingsToggleRowState extends State<_SettingsToggleRow> {
  var _hovered = false;
  var _focused = false;
  var _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = ShellTheme.of(context);
    final colors = context.shellColors;
    final enabled = widget.enabled;
    final isInteractive = enabled && widget.onToggleChanged != null;

    final effectiveHeight = widget.height ??
        (widget.toggleSubtitle != null
            ? settingsRowTwoLineHeight
            : settingsRowSingleLineHeight);

    final Color backgroundColor;
    if (_pressed && isInteractive) {
      backgroundColor = theme.cardColor(colors.surfaceContainerHighest);
    } else if ((_hovered || _focused) && isInteractive) {
      backgroundColor = theme.cardColor(colors.surfaceContainerHigh);
    } else {
      backgroundColor = Colors.transparent;
    }

    final motionDuration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : Motion.pill;

    final trailingSwitch = SettingsSwitch(
      key: widget.toggleKey,
      value: widget.toggleValue,
      onChanged: widget.onToggleChanged,
      enabled: enabled,
      pressed: _pressed,
      hovered: _hovered,
      focused: _focused,
    );

    Widget content = SizedBox(
      height: effectiveHeight,
      child: Padding(
        padding: widget.padding ??
            const EdgeInsets.symmetric(
              horizontal: settingsRowHorizontalPadding,
            ),
        child: Row(
          children: [
            if (widget.leading case final leading?) ...[
              leading,
              const SizedBox(width: 16),
            ],
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.toggleTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ShellText.settingsRowTitle.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                  if (widget.toggleSubtitle case final subtitle?) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ShellText.settingsRowSupport.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 16),
            trailingSwitch,
          ],
        ),
      ),
    );

    return Semantics(
      button: true,
      toggled: widget.toggleValue,
      enabled: enabled,
      label: widget.toggleTitle,
      child: FocusableActionDetector(
        enabled: isInteractive,
        mouseCursor: isInteractive
            ? ShellMouseCursors.link
            : SystemMouseCursors.basic,
        onShowHoverHighlight: (highlight) =>
            setState(() => _hovered = highlight),
        onShowFocusHighlight: (highlight) =>
            setState(() => _focused = highlight),
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              if (isInteractive) {
                widget.onToggleChanged!(!widget.toggleValue);
              }
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: isInteractive ? (_) => setState(() => _pressed = true) : null,
          onTapUp: isInteractive ? (_) => setState(() => _pressed = false) : null,
          onTapCancel: isInteractive ? () => setState(() => _pressed = false) : null,
          onTap: isInteractive
              ? () => widget.onToggleChanged!(!widget.toggleValue)
              : null,
          child: AnimatedContainer(
            duration: motionDuration,
            color: backgroundColor,
            child: content,
          ),
        ),
      ),
    );
  }
}

class SettingsChoice<T> {
  const SettingsChoice(this.value, this.label, {this.icon});

  final T value;
  final String label;

  /// Optional leading glyph painted by segmented-style presentations.
  final IconData? icon;
}

class SettingsSelect<T> extends StatelessWidget {
  const SettingsSelect({
    required this.label,
    required this.description,
    required this.value,
    required this.choices,
    required this.onChanged,
    this.enabled = true,
    super.key,
  });

  final String label;
  final String description;
  final T value;
  final List<SettingsChoice<T>> choices;
  final ValueChanged<T> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: ShellText.cardTitle),
        const SizedBox(height: 4),
        Text(
          description,
          style: ShellText.base.copyWith(
            color: context.shellColors.textSecondary,
            fontSize: 12,
          ),
        ),
      ],
    );
    final selector = SettingsMenu<T>(
      semanticsLabel: label,
      value: value,
      items: <SettingsMenuItem<T>>[
        for (final choice in choices)
          SettingsMenuItem<T>(choice.value, choice.label),
      ],
      onChanged: onChanged,
      enabled: enabled,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 560) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[heading, const SizedBox(height: 12), selector],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Expanded(child: heading),
            const SizedBox(width: 18),
            SizedBox(width: 260, child: selector),
          ],
        );
      },
    );
  }
}

/// M3E segmented control geometry (`02-VISUAL-SPEC.md` §3.7).
const double settingsSegmentHeight = 40;
const double settingsSegmentSpacing = 12;

class _MoveSegmentFocusIntent extends Intent {
  const _MoveSegmentFocusIntent(this.delta);

  final int delta;
}

class SettingsSegmentedControl<T> extends StatefulWidget {
  const SettingsSegmentedControl({
    required this.value,
    required this.choices,
    required this.onChanged,
    this.enabled = true,
    super.key,
  });

  final T value;
  final List<SettingsChoice<T>> choices;
  final ValueChanged<T> onChanged;
  final bool enabled;

  @override
  State<SettingsSegmentedControl<T>> createState() =>
      _SettingsSegmentedControlState<T>();
}

class _SettingsSegmentedControlState<T>
    extends State<SettingsSegmentedControl<T>> {
  late List<FocusNode> _focusNodes;

  @override
  void initState() {
    super.initState();
    _focusNodes = _createFocusNodes();
  }

  @override
  void didUpdateWidget(covariant SettingsSegmentedControl<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.choices.length != widget.choices.length) {
      for (final node in _focusNodes) {
        node.dispose();
      }
      _focusNodes = _createFocusNodes();
    }
  }

  @override
  void dispose() {
    for (final node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  List<FocusNode> _createFocusNodes() => <FocusNode>[
    for (var index = 0; index < widget.choices.length; index++)
      FocusNode(debugLabel: 'settings-segment-$index'),
  ];

  void _moveFocus(int index, int delta) {
    final next = (index + delta).clamp(0, widget.choices.length - 1);
    _focusNodes[next].requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      role: SemanticsRole.radioGroup,
      explicitChildNodes: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final children = <Widget>[
            for (var index = 0; index < widget.choices.length; index++)
              _SettingsSegment(
                label: widget.choices[index].label,
                icon: widget.choices[index].icon,
                selected: widget.choices[index].value == widget.value,
                enabled: widget.enabled,
                focusNode: _focusNodes[index],
                onSelect: () => widget.onChanged(widget.choices[index].value),
                onMove: (delta) => _moveFocus(index, delta),
              ),
          ];
          if (constraints.maxWidth < 430) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (var index = 0; index < children.length; index++) ...[
                  if (index > 0) const SizedBox(height: settingsSegmentSpacing),
                  children[index],
                ],
              ],
            );
          }
          return Row(
            children: <Widget>[
              for (var index = 0; index < children.length; index++) ...[
                if (index > 0) const SizedBox(width: settingsSegmentSpacing),
                Expanded(child: children[index]),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _SettingsSegment extends StatelessWidget {
  const _SettingsSegment({
    required this.label,
    required this.icon,
    required this.selected,
    required this.enabled,
    required this.focusNode,
    required this.onSelect,
    required this.onMove,
  });

  final String label;
  final IconData? icon;
  final bool selected;
  final bool enabled;
  final FocusNode focusNode;
  final VoidCallback onSelect;
  final ValueChanged<int> onMove;

  @override
  Widget build(BuildContext context) {
    final theme = ShellTheme.of(context);
    final colors = context.shellColors;
    final palette = theme.accentPalette;
    final motionDuration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : Motion.tile;
    return SettingsInteractiveSurface(
      height: settingsSegmentHeight,
      pressedRadius: ShellShapeScale.small,
      focusNode: focusNode,
      enabled: enabled,
      onPressed: enabled ? onSelect : null,
      semanticsButton: false,
      semanticsEnabled: enabled,
      semanticsChecked: selected,
      semanticsInMutuallyExclusiveGroup: true,
      semanticsLabel: label,
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.arrowLeft):
            _MoveSegmentFocusIntent(-1),
        SingleActivator(LogicalKeyboardKey.arrowRight):
            _MoveSegmentFocusIntent(1),
      },
      actions: <Type, Action<Intent>>{
        _MoveSegmentFocusIntent: CallbackAction<_MoveSegmentFocusIntent>(
          onInvoke: (intent) {
            onMove(intent.delta);
            return null;
          },
        ),
      },
      builder: (context, radius, state) {
        var foreground = selected ? palette.onContainer : colors.textPrimary;
        if (!enabled) {
          foreground = colors.textTertiary;
        }
        return Stack(
          alignment: Alignment.center,
          children: <Widget>[
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: selected
                        ? palette.container
                        : colors.surfaceContainerHigh,
                    borderRadius: radius,
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedOpacity(
                  duration: motionDuration,
                  opacity:
                      enabled &&
                          !selected &&
                          (state.hovered || state.pressed)
                      ? 1
                      : 0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: palette.primary.withValues(
                        alpha: state.pressed ? 0.12 : 0.08,
                      ),
                      borderRadius: radius,
                    ),
                  ),
                ),
              ),
            ),
            if (state.focused)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: radius,
                      border: Border.all(color: palette.primary, width: 2),
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  if (selected) ...[
                    Icon(
                      Icons.check_rounded,
                      size: 16,
                      color: palette.onContainer,
                    ),
                    const SizedBox(width: 8),
                  ] else if (icon != null) ...[
                    Icon(icon, size: 16, color: foreground),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ShellText.settingsButtonLabel.copyWith(
                        color: foreground,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class SettingsColorButton extends StatelessWidget {
  const SettingsColorButton({
    required this.color,
    required this.label,
    required this.onPressed,
    super.key,
  });

  final Color color;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = ShellTheme.of(context);
    final colors = context.shellColors;
    final palette = theme.accentPalette;
    final motionDuration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : Motion.tile;
    return SettingsInteractiveSurface(
      height: 40,
      pressedRadius: ShellShapeScale.small,
      onPressed: onPressed,
      semanticsLabel: label,
      semanticsValue: formatOpaqueColorHex(color),
      builder: (context, radius, state) {
        return Stack(
          alignment: Alignment.center,
          children: <Widget>[
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHigh,
                    borderRadius: radius,
                    border: Border.all(color: colors.hairline),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedOpacity(
                  duration: motionDuration,
                  opacity: state.hovered || state.pressed ? 1 : 0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: palette.primary.withValues(
                        alpha: state.pressed ? 0.12 : 0.08,
                      ),
                      borderRadius: radius,
                    ),
                  ),
                ),
              ),
            ),
            if (state.focused)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: radius,
                      border: Border.all(color: palette.primary, width: 2),
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(color: colors.panelHighlight),
                    ),
                    child: const SizedBox.square(dimension: 32),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      formatOpaqueColorHex(color),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ShellText.settingsButtonLabel.copyWith(
                        color: colors.textSecondary,
                        fontFamily: ShellText.systemBarFontFamily,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.expand_more_rounded,
                    size: 20,
                    color: colors.textSecondary,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class SettingsAnchorPicker extends StatelessWidget {
  const SettingsAnchorPicker({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final ShellPopupAnchor value;
  final ValueChanged<ShellPopupAnchor> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: context.l10n.settingsScreenAnchor,
      explicitChildNodes: true,
      child: SizedBox(
        width: 132,
        height: 132,
        child: GridView.count(
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 3,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          children: [
            for (final anchor in ShellPopupAnchor.values)
              _AnchorButton(
                anchor: anchor,
                selected: anchor == value,
                onPressed: () => onChanged(anchor),
              ),
          ],
        ),
      ),
    );
  }
}

class SettingsTextButton extends StatelessWidget {
  const SettingsTextButton({
    required this.label,
    required this.onPressed,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SettingsButton(
      label: label,
      onPressed: onPressed,
      variant: SettingsButtonVariant.text,
      size: SettingsButtonSize.small,
    );
  }
}

class _AnchorButton extends StatefulWidget {
  const _AnchorButton({
    required this.anchor,
    required this.selected,
    required this.onPressed,
  });

  final ShellPopupAnchor anchor;
  final bool selected;
  final VoidCallback onPressed;

  @override
  State<_AnchorButton> createState() => _AnchorButtonState();
}

class _AnchorButtonState extends State<_AnchorButton> {
  final _focusNode = FocusNode();
  var _hovered = false;
  var _focused = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShellTheme.of(context);
    final colors = context.shellColors;
    final palette = theme.accentPalette;
    final radius = theme.borderRadius(ShellShapeScale.medium);
    final motionDuration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : Motion.tile;
    return Semantics(
      button: true,
      selected: widget.selected,
      label: _anchorLabel(widget.anchor, context),
      child: FocusableActionDetector(
        focusNode: _focusNode,
        mouseCursor: ShellMouseCursors.link,
        onShowHoverHighlight: (highlight) =>
            setState(() => _hovered = highlight),
        onShowFocusHighlight: (highlight) =>
            setState(() => _focused = highlight),
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
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40),
            child: AnimatedContainer(
              duration: motionDuration,
              decoration: BoxDecoration(
                color: widget.selected
                    ? palette.container
                    : colors.surfaceContainerHigh,
                borderRadius: radius,
                border: Border.all(
                  color: widget.selected
                      ? palette.primary
                      : (_focused ? palette.primary : colors.hairline),
                ),
              ),
              child: Center(
                child: AnimatedContainer(
                  duration: motionDuration,
                  width: widget.selected ? 10 : 7,
                  height: widget.selected ? 10 : 7,
                  decoration: BoxDecoration(
                    color: widget.selected
                        ? palette.onContainer
                        : (_hovered || _focused
                              ? colors.textSecondary
                              : colors.textTertiary),
                    shape: BoxShape.circle,
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

String _anchorLabel(ShellPopupAnchor anchor, BuildContext context) {
  final l10n = context.l10n;
  return switch (anchor) {
    ShellPopupAnchor.topLeft => l10n.anchorTopLeft,
    ShellPopupAnchor.topCenter => l10n.anchorTopCenter,
    ShellPopupAnchor.topRight => l10n.anchorTopRight,
    ShellPopupAnchor.centerLeft => l10n.anchorCenterLeft,
    ShellPopupAnchor.center => l10n.anchorCenter,
    ShellPopupAnchor.centerRight => l10n.anchorCenterRight,
    ShellPopupAnchor.bottomLeft => l10n.anchorBottomLeft,
    ShellPopupAnchor.bottomCenter => l10n.anchorBottomCenter,
    ShellPopupAnchor.bottomRight => l10n.anchorBottomRight,
  };
}

/// M3E text field used across the settings pages in place of
/// `TextField`/`TextFormField` configured with `OutlineInputBorder`.
///
/// The filled container, `medium` corner radius, hairline border and accent
/// focus ring are painted by this widget; the inner field keeps
/// `InputBorder.none`, so the Material outline never appears. Floating
/// labels, hints, helper text, prefixes and `TextFormField` validation all
/// keep working through the standard [InputDecoration] parameters.
class SettingsTextField extends StatefulWidget {
  const SettingsTextField({
    this.controller,
    this.focusNode,
    this.label,
    this.hint,
    this.helperText,
    this.helperMaxLines,
    this.prefixIcon,
    this.enabled = true,
    this.readOnly = false,
    this.autofocus = false,
    this.monospace = false,
    this.floatingLabelAlways = false,
    this.minLines,
    this.maxLines = 1,
    this.keyboardType,
    this.textInputAction,
    this.inputFormatters,
    this.onChanged,
    this.onSubmitted,
    this.validator,
    this.semanticsLabel,
    this.fieldKey,
    this.borderRadius = ShellShapeScale.medium,
    super.key,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;

  /// Floating label inside the field; also the accessibility label.
  final String? label;
  final String? hint;
  final String? helperText;
  final int? helperMaxLines;
  final Widget? prefixIcon;
  final bool enabled;
  final bool readOnly;
  final bool autofocus;

  /// Uses the fixed-advance shell font for commands and variable names.
  final bool monospace;

  /// Keeps the label floating even before input (dense form rows).
  final bool floatingLabelAlways;
  final int? minLines;
  final int? maxLines;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FormFieldValidator<String>? validator;

  /// Accessibility label override; defaults to [label].
  final String? semanticsLabel;

  /// Key applied to the inner [TextFormField] for tests.
  final Key? fieldKey;

  /// Container corner radius on the [ShellShapeScale]; defaults to `medium`.
  final double borderRadius;

  @override
  State<SettingsTextField> createState() => _SettingsTextFieldState();
}

class _SettingsTextFieldState extends State<SettingsTextField> {
  late FocusNode _focusNode;
  var _focused = false;

  FocusNode get _effectiveFocusNode => widget.focusNode ?? _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _effectiveFocusNode.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(covariant SettingsTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      (oldWidget.focusNode ?? _focusNode).removeListener(_handleFocusChange);
      _effectiveFocusNode.addListener(_handleFocusChange);
    }
  }

  @override
  void dispose() {
    _effectiveFocusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    setState(() => _focused = _effectiveFocusNode.hasFocus);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShellTheme.of(context);
    final colors = context.shellColors;
    final palette = theme.accentPalette;
    final enabled = widget.enabled;
    final radius = theme.borderRadius(widget.borderRadius);
    final supportStyle = ShellText.settingsRowSupport.copyWith(
      color: colors.textSecondary,
      fontFamily: widget.monospace ? ShellText.systemBarFontFamily : null,
    );
    final motionDuration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : Motion.pill;
    return AnimatedContainer(
      duration: motionDuration,
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: radius,
        border: Border.all(
          color: _focused && enabled ? palette.primary : colors.hairline,
          width: _focused && enabled ? 2 : 1,
        ),
      ),
      child: Semantics(
        textField: true,
        label: widget.semanticsLabel,
        child: TextFormField(
          key: widget.fieldKey,
          controller: widget.controller,
          focusNode: _effectiveFocusNode,
          enabled: enabled,
          readOnly: widget.readOnly,
          autofocus: widget.autofocus,
          autocorrect: false,
          enableSuggestions: false,
          minLines: widget.minLines,
          maxLines: widget.maxLines,
          keyboardType: widget.keyboardType,
          textInputAction: widget.textInputAction,
          inputFormatters: widget.inputFormatters,
          onChanged: widget.onChanged,
          onFieldSubmitted: widget.onSubmitted,
          validator: widget.validator,
          cursorColor: palette.primary,
          style: ShellText.base.copyWith(
            color: enabled ? colors.textPrimary : colors.textTertiary,
            fontFamily: widget.monospace
                ? ShellText.systemBarFontFamily
                : null,
          ),
          decoration: InputDecoration(
            isDense: true,
            labelText: widget.label,
            hintText: widget.hint,
            helperText: widget.helperText,
            helperMaxLines: widget.helperMaxLines,
            helperStyle: supportStyle,
            labelStyle: supportStyle,
            floatingLabelStyle: supportStyle.copyWith(
              color: _focused ? palette.primary : colors.textSecondary,
            ),
            floatingLabelBehavior: widget.floatingLabelAlways
                ? FloatingLabelBehavior.always
                : null,
            hintStyle: supportStyle.copyWith(color: colors.textTertiary),
            prefixIcon: widget.prefixIcon,
            filled: false,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: ShellSpacing.lg,
              vertical: ShellSpacing.md,
            ),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
            errorBorder: InputBorder.none,
            focusedErrorBorder: InputBorder.none,
          ),
        ),
      ),
    );
  }
}

/// Linear progress/value bar replacing Material's `LinearProgressIndicator`
/// (determinate when [value] is set, indeterminate slide otherwise).
///
/// Geometry follows the slider track family: `full` radius ends, accent fill
/// over `surfaceContainerHighest`. The indeterminate cycle reuses
/// [Motion.wallpaperReveal], the same token the morphing loading indicator
/// uses, and respects `MediaQuery.disableAnimationsOf`.
class SettingsProgressBar extends StatefulWidget {
  const SettingsProgressBar({
    this.value,
    this.minHeight = 4,
    this.semanticsLabel,
    this.semanticsValue,
    super.key,
  });

  /// Progress in `[0, 1]`; `null` paints the indeterminate sliding segment.
  final double? value;

  /// Track height.
  final double minHeight;
  final String? semanticsLabel;
  final String? semanticsValue;

  @override
  State<SettingsProgressBar> createState() => _SettingsProgressBarState();
}

class _SettingsProgressBarState extends State<SettingsProgressBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  var _animationsDisabled = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Motion.wallpaperReveal,
    );
    if (widget.value == null) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant SettingsProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value == null && oldWidget.value != null) {
      _controller.repeat();
    } else if (widget.value != null && oldWidget.value == null) {
      _controller.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final disabled = MediaQuery.disableAnimationsOf(context);
    if (disabled == _animationsDisabled) {
      return;
    }
    _animationsDisabled = disabled;
    if (widget.value == null) {
      if (disabled) {
        _controller.stop();
      } else {
        _controller.repeat();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.shellColors;
    final accent = ShellTheme.of(context).accent;
    final radius = ShellTheme.of(
      context,
    ).borderRadius(ShellShapeScale.full);
    final value = widget.value;
    Widget bar;
    if (value != null) {
      bar = ClipRRect(
        borderRadius: radius,
        child: SizedBox(
          height: widget.minHeight,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              ColoredBox(color: colors.surfaceContainerHighest),
              FractionallySizedBox(
                widthFactor: value.clamp(0.0, 1.0),
                alignment: AlignmentDirectional.centerStart,
                child: ColoredBox(color: accent),
              ),
            ],
          ),
        ),
      );
    } else {
      bar = ClipRRect(
        borderRadius: radius,
        child: SizedBox(
          height: widget.minHeight,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              return CustomPaint(
                painter: _IndeterminateBarPainter(
                  progress: _controller.value,
                  trackColor: colors.surfaceContainerHighest,
                  barColor: accent,
                  static: _animationsDisabled,
                ),
              );
            },
          ),
        ),
      );
    }
    return Semantics(
      label: widget.semanticsLabel,
      value: widget.semanticsValue,
      child: bar,
    );
  }
}

class _IndeterminateBarPainter extends CustomPainter {
  const _IndeterminateBarPainter({
    required this.progress,
    required this.trackColor,
    required this.barColor,
    required this.static,
  });

  final double progress;
  final Color trackColor;
  final Color barColor;
  final bool static;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = trackColor);
    // A 40%-wide segment sweeping edge to edge; the ramp eases the middle of
    // the traversal so the pill feels like it accelerates through the track.
    const fraction = 0.4;
    final phase = static ? 0.5 : progress;
    final eased = Motion.md3Emphasized.transform(phase.clamp(0.0, 1.0));
    final barWidth = size.width * fraction;
    final left = eased * (size.width + barWidth) - barWidth;
    canvas.drawRect(
      Rect.fromLTWH(left, 0, barWidth, size.height),
      Paint()..color = barColor,
    );
  }

  @override
  bool shouldRepaint(covariant _IndeterminateBarPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.barColor != barColor ||
        oldDelegate.static != static;
  }
}

/// Shared modal backdrop for the settings overlays (`02-VISUAL-SPEC.md` §0
/// reference photo: scrim + centred panel).
///
/// Paints the `overviewScrim` dim, dismisses on outside tap and Escape, and
/// centres [child] inside [padding]. The scrim claims initial focus so key
/// events reach the overlay even when none of its descendants autofocus;
/// content focus nodes attach after the scrim's, so inner `autofocus` fields
/// still win. On dispose the node focused before the overlay opened is
/// restored, matching the menu's focus-return behaviour.
class SettingsModalScrim extends StatefulWidget {
  const SettingsModalScrim({
    required this.child,
    this.onDismiss,
    this.padding = const EdgeInsets.all(ShellSpacing.lg),
    super.key,
  });

  /// The centred modal content (surface, constraints and semantics stay the
  /// caller's responsibility).
  final Widget child;

  /// Called on barrier tap and as a fallback for Escape; `null` disables
  /// both. Content-level Escape handlers (catalog back navigation, busy
  /// guards) run first because key events bubble outward.
  final VoidCallback? onDismiss;
  final EdgeInsetsGeometry padding;

  @override
  State<SettingsModalScrim> createState() => _SettingsModalScrimState();
}

class _SettingsModalScrimState extends State<SettingsModalScrim> {
  final FocusNode _scrimFocus = FocusNode(
    debugLabel: 'settings-modal-scrim',
  );
  FocusNode? _returnFocus;

  @override
  void initState() {
    super.initState();
    _returnFocus = FocusManager.instance.primaryFocus;
  }

  @override
  void dispose() {
    _scrimFocus.dispose();
    final node = _returnFocus;
    _returnFocus = null;
    // Restoring focus during teardown asserts inside the focus manager; wait
    // one frame so the overlay is gone before the previous node refocuses.
    if (node != null && node.canRequestFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (node.canRequestFocus) {
          node.requestFocus();
        }
      });
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            widget.onDismiss?.call(),
      },
      child: Focus(
        focusNode: _scrimFocus,
        autofocus: true,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onDismiss,
              child: ColoredBox(color: context.shellColors.overviewScrim),
            ),
            Padding(
              padding: widget.padding,
              child: Center(child: widget.child),
            ),
          ],
        ),
      ),
    );
  }
}
