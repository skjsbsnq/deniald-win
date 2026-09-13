import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../localization/denial_localizations.dart';
import '../../theme/motion.dart';
import '../../theme/shell_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/denial_wordmark.dart';
import '../../widgets/shell_cursor.dart';
import '../settings_category_colors.dart';
import 'settings_search_bar.dart';

const settingsNavigationListKey = ValueKey<String>('settings-navigation-list');

// Layout geometry (02-VISUAL-SPEC.md §2.2 / §3.2).
const double settingsSidebarWidth = 288;
const double settingsSidebarPadding = 16;
const double settingsNavItemHeight = 64;
const double settingsNavItemRadius = ShellShapeScale.large;
const double settingsNavItemInset = 12;
const double settingsNavIconDiameter = 40;
const double settingsNavIconGlyphSize = 20;
const double settingsNavIconSpacing = 16;
const double settingsNavIndicatorSize = 12;
const double settingsNavGroupSpacing = 16;
const double settingsNavGroupHeaderGap = 8;
const double settingsNavGroupHeaderInset = 12;

/// Vertical gap between navigation cards.
///
/// §2.2 fixes the group spacing (16) and the header gap (8) but not the item
/// gap; 4 keeps the cards distinct without turning the rail into a loose list
/// (confirmed with the user 2026-09-10).
const double settingsNavItemGap = 4;

/// Alpha applied to the sidebar backing surface (§3.1 allows 0.45–0.65).
const double settingsSidebarSurfaceAlpha = 0.55;

/// The two presentations of the navigation list (§2.1).
enum SettingsNavigationForm {
  /// Fixed-width rail pinned to the left edge of the two-column layout.
  sidebar,

  /// Full-width navigation home shown when the window is narrower than 840.
  home,
}

enum SettingsPageId {
  appearance,
  language,
  keyboard,
  touchpad,
  shortcuts,
  environment,
  animations,
  layout,
  overlays,
  lockScreen,
  audio,
  displays,
  network,
  bluetooth,
  weather,
  power,
  developer,
  about,
}

/// Navigation groups in render order (§3.3). The order and membership are the
/// single source of truth and must not be changed outside a task card that
/// updates the specification first.
const Map<SettingsNavGroup, List<SettingsPageId>> settingsNavigationGroups =
    <SettingsNavGroup, List<SettingsPageId>>{
      SettingsNavGroup.connectivity: <SettingsPageId>[
        SettingsPageId.network,
        SettingsPageId.bluetooth,
        SettingsPageId.displays,
        SettingsPageId.audio,
      ],
      SettingsNavGroup.personalization: <SettingsPageId>[
        SettingsPageId.appearance,
        SettingsPageId.animations,
        SettingsPageId.layout,
        SettingsPageId.overlays,
        SettingsPageId.lockScreen,
        SettingsPageId.weather,
      ],
      SettingsNavGroup.input: <SettingsPageId>[
        SettingsPageId.keyboard,
        SettingsPageId.touchpad,
        SettingsPageId.shortcuts,
      ],
      SettingsNavGroup.system: <SettingsPageId>[
        SettingsPageId.power,
        SettingsPageId.language,
        SettingsPageId.environment,
        SettingsPageId.developer,
        SettingsPageId.about,
      ],
    };

enum SettingsNavGroup { connectivity, personalization, input, system }

extension SettingsNavGroupPresentation on SettingsNavGroup {
  String label(BuildContext context) => switch (this) {
    SettingsNavGroup.connectivity => context.l10n.settingsNavGroupConnectivity,
    SettingsNavGroup.personalization =>
      context.l10n.settingsNavGroupPersonalization,
    SettingsNavGroup.input => context.l10n.settingsNavGroupInput,
    SettingsNavGroup.system => context.l10n.settingsNavGroupSystem,
  };
}

extension SettingsPageIdPresentation on SettingsPageId {
  String label(BuildContext context) => switch (this) {
    SettingsPageId.about => context.l10n.settingsNavigationAbout,
    SettingsPageId.appearance => context.l10n.settingsNavigationAppearance,
    SettingsPageId.language => context.l10n.settingsNavigationLanguage,
    SettingsPageId.keyboard => context.l10n.settingsNavigationKeyboard,
    SettingsPageId.touchpad => context.l10n.settingsNavigationTouchpad,
    SettingsPageId.shortcuts => context.l10n.settingsNavigationShortcuts,
    SettingsPageId.environment => context.l10n.settingsNavigationEnvironment,
    SettingsPageId.animations => context.l10n.settingsNavigationAnimations,
    SettingsPageId.layout => context.l10n.settingsNavigationDesktopLayout,
    SettingsPageId.overlays => context.l10n.settingsNavigationOverlays,
    SettingsPageId.lockScreen => context.l10n.settingsNavigationLockScreen,
    SettingsPageId.audio => context.l10n.settingsNavigationAudio,
    SettingsPageId.displays => context.l10n.settingsNavigationDisplays,
    SettingsPageId.network => context.l10n.settingsNavigationNetwork,
    SettingsPageId.bluetooth => context.l10n.settingsNavigationBluetooth,
    SettingsPageId.weather => context.l10n.settingsNavigationWeather,
    SettingsPageId.power => context.l10n.settingsNavigationPower,
    SettingsPageId.developer => context.l10n.settingsNavigationDeveloper,
  };

  IconData get icon => switch (this) {
    SettingsPageId.about => Icons.info_outline_rounded,
    SettingsPageId.appearance => Icons.palette_outlined,
    SettingsPageId.language => Icons.translate_rounded,
    SettingsPageId.keyboard => Icons.keyboard_rounded,
    SettingsPageId.touchpad => Icons.mouse_rounded,
    SettingsPageId.shortcuts => Icons.keyboard_command_key_rounded,
    SettingsPageId.environment => Icons.terminal_rounded,
    SettingsPageId.animations => Icons.animation_rounded,
    SettingsPageId.layout => Icons.space_dashboard_outlined,
    SettingsPageId.overlays => Icons.picture_in_picture_alt_outlined,
    SettingsPageId.power => Icons.power_settings_new_rounded,
    SettingsPageId.lockScreen => Icons.lock_outline_rounded,
    SettingsPageId.audio => Icons.volume_up_rounded,
    SettingsPageId.displays => Icons.monitor_rounded,
    SettingsPageId.network => Icons.wifi_rounded,
    SettingsPageId.bluetooth => Icons.bluetooth_rounded,
    SettingsPageId.weather => Icons.cloud_outlined,
    SettingsPageId.developer => Icons.code_rounded,
  };
}

/// Grouped, card-style Settings navigation (§3.3/§3.4).
///
/// [SettingsNavigationForm.sidebar] renders the fixed 288 rail used by the
/// two-column layout; [SettingsNavigationForm.home] renders the drill-down home
/// list. Both share the same search capsule, grouped ordering, and cards.
///
/// [search] carries the application-owned search state (§3.2). While it is
/// active and supplies [SettingsSearchBinding.results], the result view stands
/// in for the navigation list; the capsule and its position never move.
class SettingsNavigation extends StatelessWidget {
  const SettingsNavigation({
    required this.selected,
    required this.onSelected,
    required this.form,
    required this.search,
    this.showTouchpad = true,
    super.key,
  });

  final SettingsPageId selected;
  final ValueChanged<SettingsPageId> onSelected;
  final SettingsNavigationForm form;
  final SettingsSearchBinding search;
  final bool showTouchpad;

  @override
  Widget build(BuildContext context) {
    final list = _SettingsNavigationList(
      selected: selected,
      onSelected: onSelected,
      showTouchpad: showTouchpad,
    );
    final body = search.active && search.results != null
        ? search.results!
        : list;
    final capsule = SettingsSearchBar(
      query: search.query,
      active: search.active,
      onQueryChanged: search.onQueryChanged,
      onActivate: search.onActivate,
      onDismiss: search.onDismiss,
      onPrevious: search.onPrevious,
      onNext: search.onNext,
      onSubmit: search.onSubmit,
    );
    switch (form) {
      case SettingsNavigationForm.home:
        return Padding(
          padding: const EdgeInsets.all(settingsSidebarPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              capsule,
              const SizedBox(height: settingsNavGroupSpacing),
              Expanded(child: body),
            ],
          ),
        );
      case SettingsNavigationForm.sidebar:
        return SizedBox(
          width: settingsSidebarWidth,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: context.shellColors.surfaceContainerLow.withValues(
                alpha: settingsSidebarSurfaceAlpha,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(settingsSidebarPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  capsule,
                  const SizedBox(height: settingsNavGroupSpacing),
                  Expanded(child: body),
                  const SizedBox(height: settingsNavGroupHeaderGap),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: 72,
                      height: 20,
                      child: ColorFiltered(
                        colorFilter: ColorFilter.mode(
                          context.shellColors.textTertiary,
                          BlendMode.srcIn,
                        ),
                        child: DenialWordmark(
                          alignment: Alignment.centerLeft,
                          semanticsLabel:
                              context.l10n.settingsHeaderLogoSemanticsLabel,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: settingsNavGroupHeaderGap),
                  Text(
                    context.l10n.settingsStorageLocation,
                    style: ShellText.base.copyWith(
                      color: context.shellColors.textTertiary,
                      fontSize: 9,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
    }
  }
}

class _SettingsNavigationList extends StatelessWidget {
  const _SettingsNavigationList({
    required this.selected,
    required this.onSelected,
    required this.showTouchpad,
  });

  final SettingsPageId selected;
  final ValueChanged<SettingsPageId> onSelected;
  final bool showTouchpad;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    final groups = settingsNavigationGroups.entries.toList(growable: false);
    for (var groupIndex = 0; groupIndex < groups.length; groupIndex += 1) {
      if (groupIndex > 0) {
        children.add(const SizedBox(height: settingsNavGroupSpacing));
      }
      children.add(_GroupHeader(group: groups[groupIndex].key));
      children.add(const SizedBox(height: settingsNavGroupHeaderGap));
      final pages = groups[groupIndex].value
          .where(
            (page) => page != SettingsPageId.touchpad || showTouchpad,
          )
          .toList(growable: false);
      for (var index = 0; index < pages.length; index += 1) {
        if (index > 0) {
          children.add(const SizedBox(height: settingsNavItemGap));
        }
        final page = pages[index];
        children.add(
          SettingsNavItem(
            key: ValueKey<SettingsPageId>(page),
            page: page,
            selected: page == selected,
            onPressed: () => onSelected(page),
          ),
        );
      }
    }
    return ListView(
      key: settingsNavigationListKey,
      padding: EdgeInsets.zero,
      children: children,
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.group});

  final SettingsNavGroup group;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: settingsNavGroupHeaderInset),
      child: Semantics(
        header: true,
        child: Text(
          group.label(context),
          style: ShellText.settingsSectionHeader.copyWith(
            color: context.shellColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// One card-style navigation destination (§3.4).
///
/// The card carries the destination label alone: a single-line 64dp row whose
/// title is centred, so every rail entry and search result reads alike.
class SettingsNavItem extends StatefulWidget {
  const SettingsNavItem({
    required this.page,
    required this.selected,
    required this.onPressed,
    this.semanticsSupport,
    super.key,
  });

  final SettingsPageId page;
  final bool selected;
  final VoidCallback onPressed;

  /// Second line of the accessibility label; never painted (§3.3).
  ///
  /// Search results announce the destination's owning group this way without
  /// giving the card a visible supporting line.
  final String? semanticsSupport;

  @override
  State<SettingsNavItem> createState() => _SettingsNavItemState();
}

class _SettingsNavItemState extends State<SettingsNavItem>
    with TickerProviderStateMixin {
  var _hovered = false;
  var _focused = false;
  late final AnimationController _selectionController;
  late final AnimationController _indicatorController;

  @override
  void initState() {
    super.initState();
    _selectionController = AnimationController(
      vsync: this,
      value: widget.selected ? 1.0 : 0.0,
    );
    _indicatorController = AnimationController(
      vsync: this,
      value: widget.selected ? 1.0 : 0.0,
    );
  }

  @override
  void didUpdateWidget(covariant SettingsNavItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected == widget.selected) {
      return;
    }
    final target = widget.selected ? 1.0 : 0.0;
    if (MediaQuery.disableAnimationsOf(context)) {
      _selectionController.value = target;
      _indicatorController.value = target;
      return;
    }
    springTo(
      _selectionController,
      target,
      spring: Motion.expressiveEffectsDefault,
      telemetryLabel: 'settings_navigation_effects',
    );
    springTo(
      _indicatorController,
      target,
      spring: Motion.expressiveSpatialFast,
      telemetryLabel: 'settings_navigation_indicator',
    );
  }

  @override
  void dispose() {
    _selectionController.dispose();
    _indicatorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShellTheme.of(context);
    final palette = theme.accentPalette;
    final colors = context.shellColors;
    final selected = widget.selected;
    final pageLabel = widget.page.label(context);
    final semanticsLabel = widget.semanticsSupport == null
        ? pageLabel
        : '$pageLabel\n${widget.semanticsSupport}';
    final radius = theme.borderRadius(settingsNavItemRadius);
    final hoverDuration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : Motion.pill;
    return Semantics(
      button: true,
      selected: selected,
      label: semanticsLabel,
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
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: AnimatedBuilder(
            animation: Listenable.merge(<Listenable>[
              _selectionController,
              _indicatorController,
            ]),
            builder: (context, _) {
              final selection = _selectionController.value.clamp(0.0, 1.0);
              final indicator = _indicatorController.value.clamp(0.0, 1.0);
              return SizedBox(
                height: settingsNavItemHeight,
                child: Stack(
                  // The content row is the only non-positioned child, so the
                  // fit decides its height: expanding it to the full 64dp card
                  // lets the row centre the 40dp icon and the label instead of
                  // pinning them to the top edge (§3.4).
                  fit: StackFit.expand,
                  children: <Widget>[
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Color.lerp(
                            theme.cardColor(colors.surfaceContainerLow),
                            palette.container,
                            selection,
                          ),
                          borderRadius: radius,
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: AnimatedOpacity(
                          duration: hoverDuration,
                          opacity: _hovered ? 1 : 0,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: selected
                                  ? palette.primary.withValues(alpha: 0.12)
                                  : theme.cardColor(
                                      colors.surfaceContainerHigh,
                                    ),
                              borderRadius: radius,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: settingsNavItemInset,
                      ),
                      child: Row(
                        children: <Widget>[
                          SettingsNavIconDot(
                            hue: SettingsCategoryColors.of(
                              context,
                              widget.page,
                            ),
                            icon: widget.page.icon,
                          ),
                          const SizedBox(width: settingsNavIconSpacing),
                          Expanded(
                            // The painted label is the parent Semantics label,
                            // so it is excluded here rather than announced a
                            // second time.
                            child: ExcludeSemantics(
                              child: Text(
                                pageLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: ShellText.settingsNavLabel.copyWith(
                                  color: Color.lerp(
                                    colors.textPrimary,
                                    palette.onContainer,
                                    selection,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: settingsNavItemInset),
                          SizedBox(
                            width: settingsNavIndicatorSize,
                            height: settingsNavIndicatorSize,
                            child: Opacity(
                              opacity: indicator,
                              child: Transform.scale(
                                scale: 0.6 + 0.4 * indicator,
                                child: Icon(
                                  Icons.play_arrow_rounded,
                                  size: settingsNavIndicatorSize,
                                  color: palette.primary,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_focused)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: radius,
                              border: Border.all(
                                color: palette.primary,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// 40dp category-hue circle holding a 20dp page glyph (§3.4).
class SettingsNavIconDot extends StatelessWidget {
  const SettingsNavIconDot({required this.hue, required this.icon, super.key});

  final SettingsCategoryHue hue;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: settingsNavIconDiameter,
      height: settingsNavIconDiameter,
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
            size: settingsNavIconGlyphSize,
            color: hue.onContainer,
          ),
        ),
      ),
    );
  }
}
