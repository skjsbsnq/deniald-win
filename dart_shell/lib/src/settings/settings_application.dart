import 'dart:async';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/generated/app_localizations_en.dart';
import '../config/startup_environment.dart';
import '../desktop/desktop_workspace.dart';
import '../launcher/controllers/application_recents_controller.dart';
import '../local_apps/local_flutter_application.dart';
import '../launcher/controllers/home_grid_controller.dart';
import '../launcher/models/desktop_app.dart';
import '../localization/denial_localizations.dart';
import '../models/display_layout.dart';
import '../state/display_layout.dart';
import '../state/cursor_theme.dart';
import '../state/output_configuration.dart';
import '../state/shell_controller.dart';
import '../state/ui_development.dart';
import '../theme/motion.dart';
import '../theme/cursor_themes.dart';
import '../theme/shell_theme.dart';
import '../theme/tokens.dart';
import '../wallpaper/state/wallpaper_accent.dart';
import '../wallpaper/state/wallpaper_controller.dart';
import '../wallpaper/wallpaper.dart';
import '../widgets/shell_cursor.dart';
import 'settings_controller.dart';
import 'widgets/focused_border_color_picker.dart';
import 'widgets/settings_about_page.dart';
import 'widgets/settings_appearance_page.dart';
import 'widgets/settings_animations_page.dart';
import 'widgets/settings_developer_page.dart';
import 'widgets/settings_displays_page.dart';
import 'widgets/settings_environment_page.dart';
import 'widgets/settings_layout_page.dart';
import 'widgets/settings_keyboard_page.dart';
import 'widgets/settings_language_page.dart';
import 'widgets/settings_lock_screen_page.dart';
import 'widgets/settings_navigation.dart';
import 'widgets/settings_overlays_page.dart';
import 'widgets/settings_power_page.dart';
import 'widgets/settings_shortcuts_page.dart';
import 'widgets/settings_system_pages.dart';
import 'widgets/settings_touchpad_page.dart';
import 'widgets/settings_weather_page.dart';

final _englishSettings = AppLocalizationsEn();
final settingsDesktopApplicationsProvider = FutureProvider<List<DesktopApp>>(
  (ref) {
    final repository = ref.watch(desktopAppsRepositoryProvider);
    return Isolate.run(
      repository.loadApplications,
      debugName: 'denial-settings-desktop',
    );
  },
  isAutoDispose: true,
);
const denialSettingsApplicationId = 'dev.denial.settings';

/// Available width at which Settings switches to the two-column layout
/// (`02-VISUAL-SPEC.md` §2.1). Below it the surface drills down in one column.
const double settingsWideLayoutBreakpoint = 840;

/// Maximum width of a single Settings content column (§2.2).
const double settingsContentMaxWidth = 720;

/// Identifies the single-column back button for tests.
const settingsBackButtonKey = ValueKey<String>('settings-back-button');

/// Identifies the centred content column for layout asserts.
const settingsContentColumnKey = ValueKey<String>('settings-content-column');

bool isDenialSettingsApplicationId(String appId) =>
    appId.trim().toLowerCase() == denialSettingsApplicationId;

@immutable
class SettingsPageOpenRequest {
  const SettingsPageOpenRequest({required this.id, required this.page});

  final int id;
  final SettingsPageId page;
}

final settingsPageOpenRequestProvider =
    NotifierProvider<
      SettingsPageOpenRequestController,
      SettingsPageOpenRequest?
    >(SettingsPageOpenRequestController.new);

/// Carries one-shot navigation requests into the single-instance Settings app.
/// The request remains pending while the native local window is being created,
/// then the mounted Settings surface consumes it after selecting the page.
class SettingsPageOpenRequestController
    extends Notifier<SettingsPageOpenRequest?> {
  var _nextId = 0;

  @override
  SettingsPageOpenRequest? build() => null;

  void request(SettingsPageId page) {
    state = SettingsPageOpenRequest(id: ++_nextId, page: page);
  }

  void consume(int id) {
    if (state?.id == id) {
      state = null;
    }
  }
}

final denialSettingsApplication = LocalFlutterApplication(
  id: denialSettingsApplicationId,
  title: _englishSettings.settingsApplicationTitle,
  defaultSize: const Size(1080, 720),
  minimumSize: const Size(420, 400),
  translucent: true,
  icon: Icons.settings_rounded,
  categories: <String>[
    _englishSettings.settingsApplicationTitle,
    _englishSettings.settingsApplicationCategorySystem,
    _englishSettings.settingsApplicationCategoryAppearance,
    _englishSettings.settingsApplicationCategoryPreferences,
  ],
  localizedTitle: _localizedSettingsTitle,
  localizedCategories: _localizedSettingsCategories,
  builder: _buildSettingsApplication,
);

/// Opens the Settings application on [page], or its front page when null.
///
/// Both hosting modes are covered: embedded shells reuse the in-process
/// single-instance window via [settingsPageOpenRequestProvider], while
/// stand-alone shells launch (or activate) the external binary with a
/// `--page` argument. The optional [onActivated] hook lets surface hosts
/// dismiss themselves once the request is dispatched.
void launchSettingsPage(
  WidgetRef ref,
  BuildContext context,
  SettingsPageId? page, {
  VoidCallback? onDispatched,
}) {
  final environment = ref.read(startupEnvironmentProvider);
  if (environment.flag('DENIA_EMBED_SETTINGS')) {
    if (page != null) {
      ref.read(settingsPageOpenRequestProvider.notifier).request(page);
    }
    _launchSettingsLocalApp(ref, context);
    onDispatched?.call();
    return;
  }
  for (final window in ref.read(shellControllerProvider).openAppWindows) {
    if (isDenialSettingsApplicationId(window.appId)) {
      ref.read(desktopWorkspaceProvider.notifier).activate(window.objectId);
      ref.read(shellControllerProvider.notifier).focusWindow(window);
      if (page == null) {
        onDispatched?.call();
        return;
      }
      break;
    }
  }
  final binary = environment['DENIAL_SETTINGS_BINARY']?.trim();
  final executable = binary == null || binary.isEmpty
      ? '/usr/bin/denial-settings'
      : binary;
  ref.read(denialBridgeProvider).launchApplication(<String>[
    executable,
    if (page != null) '--page=${page.name}',
  ]);
  onDispatched?.call();
}

void _launchSettingsLocalApp(WidgetRef ref, BuildContext context) {
  ref
      .read(applicationRecentsProvider.notifier)
      .record(localApplicationRecentId(denialSettingsApplication.id));
  final displayLayout = ref.read(displayLayoutProvider);
  final mainOutput = displayLayout?.mainOutput;
  final workspace = ref.read(desktopWorkspaceProvider);
  final viewSize = workspace.viewSize.isEmpty
      ? MediaQuery.sizeOf(context)
      : workspace.viewSize;
  final availableBounds = mainOutput == null
      ? Offset.zero & viewSize
      : displayLayout!.workAreaOf(mainOutput);
  ref
      .read(localFlutterApplicationLauncherProvider)
      .launch(
        denialSettingsApplication.id,
        availableBounds: availableBounds,
        title: denialSettingsApplication.titleFor(context),
      );
}

String _localizedSettingsTitle(BuildContext context) {
  return context.l10n.settingsApplicationTitle;
}

List<String> _localizedSettingsCategories(BuildContext context) {
  final l10n = context.l10n;
  return <String>[
    l10n.settingsApplicationTitle,
    l10n.settingsApplicationCategorySystem,
    l10n.settingsApplicationCategoryAppearance,
    l10n.settingsApplicationCategoryPreferences,
  ];
}

Widget _buildSettingsApplication(
  BuildContext context,
  LocalFlutterWindowHandle window,
) {
  return const DenialSettingsApplication();
}

class DenialSettingsApplication extends ConsumerStatefulWidget {
  const DenialSettingsApplication({
    this.initialPage = SettingsPageId.appearance,
    this.onOpenWallpaperSelector,
    this.onPickCursorZip,
    super.key,
  });

  final SettingsPageId initialPage;
  final Future<void> Function()? onOpenWallpaperSelector;
  final Future<String?> Function()? onPickCursorZip;

  @override
  ConsumerState<DenialSettingsApplication> createState() =>
      _DenialSettingsApplicationState();
}

class _DenialSettingsApplicationState
    extends ConsumerState<DenialSettingsApplication> {
  late SettingsPageId _page;
  var _detailOpen = false;
  var _colorPickerOpen = false;
  int? _scheduledPageRequestId;

  @override
  void initState() {
    super.initState();
    _page = widget.initialPage;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_revealPendingDisplayConfirmation());
    });
  }

  Future<void> _revealPendingDisplayConfirmation() async {
    final outputController = ref.read(outputConfigurationProvider.notifier);
    await outputController.refresh();
    if (!mounted ||
        ref
                .read(outputConfigurationProvider)
                .configuration
                ?.pendingConfirmation ==
            null) {
      return;
    }
    _selectPage(SettingsPageId.displays);
  }

  void _selectPage(SettingsPageId page, {bool openDetail = true}) {
    if (_page == page) {
      if (openDetail && !_detailOpen) {
        setState(() => _detailOpen = true);
      }
      return;
    }
    setState(() {
      _page = page;
      if (openDetail) {
        _detailOpen = true;
      }
    });
  }

  void _closeDetail() {
    if (!_detailOpen) {
      return;
    }
    // A pending display confirmation owns the foreground until it is resolved;
    // leaving the detail would unmount its dialog, so the back affordance and
    // Escape stand down while it is open (§3.5).
    if (ref
            .read(outputConfigurationProvider)
            .configuration
            ?.pendingConfirmation !=
        null) {
      return;
    }
    setState(() => _detailOpen = false);
  }

  @override
  Widget build(BuildContext context) {
    _scheduleRequestedPage(ref.watch(settingsPageOpenRequestProvider));
    return Semantics(
      container: true,
      role: .main,
      label: context.l10n.settingsApplicationSemanticsLabel,
      child: Theme(
        data: context.shellTheme.toMaterialTheme(),
        child: Material(
          color: context.shellTheme.panelColor(
            context.shellColors.panelBackground,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide =
                  constraints.maxWidth >= settingsWideLayoutBreakpoint;
              return Stack(
                fit: StackFit.expand,
                children: [
                  wide ? _buildWideLayout(context) : _buildNarrowLayout(),
                  Positioned.fill(
                    child: AnimatedSwitcher(
                      duration: Motion.cardSettle,
                      reverseDuration: Motion.tile,
                      child: _buildColorPicker(),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// Two-column list-detail layout used at [settingsWideLayoutBreakpoint] and
  /// above: a fixed navigation rail beside the centred content column.
  Widget _buildWideLayout(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SettingsNavigation(
          selected: _page,
          form: SettingsNavigationForm.sidebar,
          onSelected: (page) => _selectPage(page, openDetail: false),
        ),
        Expanded(
          child: _SettingsContentColumn(child: _buildPageSwitcher()),
        ),
      ],
    );
  }

  Widget _buildNarrowLayout() {
    if (_detailOpen) {
      return _SettingsContentColumn(
        child: _SettingsDetailScaffold(
          onBack: _closeDetail,
          child: _buildPageSwitcher(),
        ),
      );
    }
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: settingsContentMaxWidth),
        child: SettingsNavigation(
          selected: _page,
          form: SettingsNavigationForm.home,
          onSelected: _selectPage,
        ),
      ),
    );
  }

  Widget _buildPageSwitcher() {
    return AnimatedSwitcher(
      duration: Motion.cardSettle,
      switchInCurve: Motion.md3EmphasizedDecelerate,
      switchOutCurve: Motion.md3EmphasizedAccelerate,
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          alignment: Alignment.topCenter,
          fit: StackFit.expand,
          children: [...previousChildren, ?currentChild],
        );
      },
      child: KeyedSubtree(
        key: ValueKey<SettingsPageId>(_page),
        child: _SettingsPageBody(
          page: _page,
          onOpenAccentPicker: () => setState(() => _colorPickerOpen = true),
          onOpenWallpaperSelector: () =>
              unawaited(_openWallpaperSelector()),
          onPickCursorZip: widget.onPickCursorZip,
        ),
      ),
    );
  }

  void _scheduleRequestedPage(SettingsPageOpenRequest? request) {
    if (request == null || request.id == _scheduledPageRequestId) {
      return;
    }
    _scheduledPageRequestId = request.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          ref.read(settingsPageOpenRequestProvider)?.id != request.id) {
        return;
      }
      _selectPage(request.page);
      ref.read(settingsPageOpenRequestProvider.notifier).consume(request.id);
    });
  }

  Widget _buildColorPicker() {
    if (!_colorPickerOpen) {
      return const SizedBox.shrink(
        key: ValueKey<String>('settings-color-picker-closed'),
      );
    }
    final settings = ref.watch(
      shellSettingsProvider.select((settings) => settings.appearance),
    );
    final controller = ref.read(shellSettingsProvider.notifier);
    return SettingsAccentColorPicker(
      key: settingsAccentColorPickerKey,
      color: settings.customAccentColor,
      title: context.l10n.settingsShellAccentTitle,
      routeLabel: context.l10n.settingsAccentPickerRouteLabel,
      wheelSemanticsLabel: context.l10n.settingsAccentPickerWheelLabel,
      onChanged: controller.setCustomAccentColor,
      onReset: () =>
          controller.setCustomAccentColor(ShellBrandColors.defaultAccent),
      onClose: () => setState(() => _colorPickerOpen = false),
    );
  }

  Future<void> _openWallpaperSelector() async {
    final externalLauncher = widget.onOpenWallpaperSelector;
    if (externalLauncher != null) {
      await externalLauncher();
      return;
    }
    var displayLayout = ref.read(displayLayoutProvider);
    displayLayout ??= await ref
        .read(displayLayoutProvider.notifier)
        .ensureLoaded();
    if (!mounted) {
      return;
    }
    final fallbackPixelSize =
        MediaQuery.sizeOf(context) * MediaQuery.devicePixelRatioOf(context);
    ref
        .read(wallpaperControllerProvider.notifier)
        .openSelector(
          targetPixelSize: displayLayout?.pixelSize ?? fallbackPixelSize,
        );
  }
}

class _SettingsPageBody extends ConsumerWidget {
  const _SettingsPageBody({
    required this.page,
    required this.onOpenAccentPicker,
    required this.onOpenWallpaperSelector,
    required this.onPickCursorZip,
  });

  final SettingsPageId page;
  final VoidCallback onOpenAccentPicker;
  final VoidCallback onOpenWallpaperSelector;
  final Future<String?> Function()? onPickCursorZip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(shellSettingsProvider.notifier);
    switch (page) {
      case SettingsPageId.appearance:
        final settings = ref.watch(
          shellSettingsProvider.select((settings) => settings.appearance),
        );
        final displayLayout = ref.watch(displayLayoutProvider);
        final assignment = ref.watch(
          wallpaperControllerProvider.select((state) => state.assignment),
        );
        final cursorThemes = ref.watch(availableShellCursorThemesProvider);
        final cursorCatalogLoading = ref
            .watch(cursorThemeCatalogProvider)
            .isLoading;
        return SettingsAppearancePage(
          settings: settings,
          extractedAccent: ref.watch(wallpaperAccentProvider).color,
          wallpaper: _wallpaperFor(assignment, displayLayout),
          onOpenWallpaperSelector: onOpenWallpaperSelector,
          onColorSchemePreferenceChanged: controller.setColorSchemePreference,
          onAccentSourceChanged: controller.setAccentSource,
          onOpenAccentPicker: onOpenAccentPicker,
          onCornerRadiusScaleChanged: controller.setCornerRadiusScale,
          onPanelOpacityChanged: controller.setPanelOpacity,
          onCardOpacityChanged: controller.setCardOpacity,
          onBackdropBlurEnabledChanged: controller.setBackdropBlurEnabled,
          onBackdropBlurLevelChanged: controller.setBackdropBlurLevel,
          onBackdropBlurOpacityThresholdChanged:
              controller.setBackdropBlurOpacityThreshold,
          onFocusedWindowBorderEnabledChanged:
              controller.setFocusedWindowBorderEnabled,
          onFocusedOpacityChanged: controller.setFocusedWindowOpacity,
          onUnfocusedOpacityChanged: controller.setUnfocusedWindowOpacity,
          onCursorSizeChanged: controller.setCursorSize,
          cursorThemes: cursorThemes,
          cursorCatalogLoading: cursorCatalogLoading,
          onCursorThemeChanged: controller.setCursorThemeId,
          onAllowClientCursorSurfacesChanged:
              controller.setAllowClientCursorSurfaces,
          onUiFontFamilyChanged: controller.setUiFontFamily,
          onIconThemeNameChanged: controller.setIconThemeName,
          onImportCursorZip: onPickCursorZip == null
              ? null
              : () async {
                  final path = await onPickCursorZip!();
                  if (path == null) {
                    return null;
                  }
                  final imported = await ref
                      .read(cursorThemeCatalogProvider.notifier)
                      .importZip(path);
                  controller.setCursorThemeId(imported.id);
                  await controller.flush();
                  return imported;
                },
          onRemoveCursorTheme: (theme) async {
            if (settings.cursorThemeId == theme.id) {
              controller.setCursorThemeId(ShellCursorThemes.bibataModernIce.id);
              await controller.flush();
            }
            await ref.read(cursorThemeCatalogProvider.notifier).remove(theme);
          },
          onReset: controller.resetAppearance,
        );
      case SettingsPageId.language:
        final settings = ref.watch(
          shellSettingsProvider.select((settings) => settings.localization),
        );
        return SettingsLanguagePage(
          settings: settings,
          onChanged: controller.setLocalePreference,
          onReset: controller.resetLocalization,
        );
      case SettingsPageId.keyboard:
        return const SettingsKeyboardPage();
      case SettingsPageId.touchpad:
        return const SettingsTouchpadPage();
      case SettingsPageId.shortcuts:
        final applications = ref.watch(settingsDesktopApplicationsProvider);
        return SettingsShortcutsPage(
          applications: applications.asData?.value ?? const <DesktopApp>[],
        );
      case SettingsPageId.environment:
        final settings = ref.watch(
          shellSettingsProvider.select(
            (settings) => settings.applicationEnvironment,
          ),
        );
        final applications = ref.watch(settingsDesktopApplicationsProvider);
        return SettingsEnvironmentPage(
          settings: settings,
          applications: applications.asData?.value ?? const <DesktopApp>[],
          applicationsLoading: applications.isLoading,
          applicationsUnavailable: applications.hasError,
          onSave: (desktopFileId, previousName, name, value) {
            controller.replaceApplicationEnvironmentOverride(
              desktopFileId: desktopFileId,
              previousName: previousName,
              name: name,
              value: value,
            );
          },
          onDelete: (desktopFileId, name) {
            controller.removeApplicationEnvironmentOverride(
              name,
              desktopFileId: desktopFileId,
            );
          },
          onReset: controller.resetApplicationEnvironment,
          onResetScope: controller.resetApplicationEnvironmentScope,
        );
      case SettingsPageId.layout:
        final settings = ref.watch(
          shellSettingsProvider.select((settings) => settings.layout),
        );
        final displayLayout = ref.watch(displayLayoutProvider);
        return SettingsLayoutPage(
          settings: settings,
          displayLayout: displayLayout,
          onWindowLayoutChanged: controller.setDesktopWindowLayout,
          onWorkspacesEnabledChanged: controller.setWorkspacesEnabled,
          onWorkspaceCountChanged: controller.setWorkspaceCount,
          onSystemBarChanged: (side, monitorIds) {
            final outputNames = <String>[
              for (final output
                  in displayLayout?.outputs ?? const <DisplayOutput>[])
                if (monitorIds.contains(output.monitorId)) output.name,
            ];
            controller.setSystemBarPlacement(
              side: side,
              outputNames: outputNames,
            );
            ref
                .read(displayLayoutProvider.notifier)
                .previewSystemBar(side: side, monitorIds: monitorIds);
          },
          onSystemBarThicknessChanged: controller.setSystemBarThickness,
          onMaximizePaddingChanged: controller.setMaximizePadding,
          onMinimizedWindowPlacementChanged:
              controller.setMinimizedWindowPlacement,
          onClipboardTrayEdgeChanged: controller.setClipboardTrayEdge,
          onClipboardTrayExtentChanged: controller.setClipboardTrayExtent,
          onUseChromeOsShelfChanged: controller.setUseChromeOsShelf,
          onReset: controller.resetLayout,
        );
      case SettingsPageId.animations:
        final settings = ref.watch(
          shellSettingsProvider.select((settings) => settings.animations),
        );
        return SettingsAnimationsPage(
          settings: settings,
          onCloseEffectChanged: controller.setWindowCloseEffect,
          onDurationScaleChanged: controller.setAnimationDurationScale,
          onPanelTravelChanged: controller.setPanelTravel,
          onLockAnimationChanged: controller.setLockScreenAnimationEnabled,
          onReset: controller.resetAnimations,
        );
      case SettingsPageId.overlays:
        final settings = ref.watch(
          shellSettingsProvider.select((settings) => settings.overlays),
        );
        return SettingsOverlaysPage(
          settings: settings,
          onChanged: controller.setOverlayPlacement,
          onReset: controller.resetOverlays,
        );
      case SettingsPageId.power:
        final settings = ref.watch(
          shellSettingsProvider.select((settings) => settings.power),
        );
        return SettingsPowerPage(
          settings: settings,
          onLockEnabledChanged: controller.setIdleLockEnabled,
          onLockTimeoutChanged: controller.setIdleLockTimeoutMinutes,
          onDpmsEnabledChanged: controller.setIdleDpmsEnabled,
          onDpmsTimeoutChanged: controller.setIdleDpmsTimeoutMinutes,
          onSuspendEnabledChanged: controller.setIdleSuspendEnabled,
          onSuspendTimeoutChanged: controller.setIdleSuspendTimeoutMinutes,
          onSuspendModeChanged: controller.setSuspendMode,
          onReset: controller.resetPower,
        );
      case SettingsPageId.lockScreen:
        final settings = ref.watch(
          shellSettingsProvider.select((settings) => settings.lockScreen),
        );
        final displayLayout = ref.watch(displayLayoutProvider);
        final assignment = ref.watch(
          wallpaperControllerProvider.select((state) => state.assignment),
        );
        return SettingsLockScreenPage(
          settings: settings,
          wallpaper: _wallpaperFor(assignment, displayLayout),
          onUseWallpaperChanged: (value) =>
              controller.setLockScreen(useSystemWallpaper: value),
          onDimChanged: (value) => controller.setLockScreen(dimAmount: value),
          onBlurChanged: (value) => controller.setLockScreen(blurRadius: value),
          onClockScaleChanged: (value) =>
              controller.setLockScreen(clockScale: value),
          onShowStatusChanged: (value) =>
              controller.setLockScreen(showSystemStatus: value),
          onReset: controller.resetLockScreen,
        );
      case SettingsPageId.audio:
        return const SettingsAudioPage();
      case SettingsPageId.displays:
        return const _SettingsDisplaysBody();
      case SettingsPageId.network:
        return const SettingsNetworkPage();
      case SettingsPageId.bluetooth:
        return const SettingsBluetoothPage();
      case SettingsPageId.weather:
        final settings = ref.watch(
          shellSettingsProvider.select((settings) => settings.weather),
        );
        return SettingsWeatherPage(
          settings: settings,
          onLocationModeChanged: controller.setWeatherLocationMode,
          onManualLocationChanged: controller.setWeatherManualLocation,
          onTemperatureUnitChanged: controller.setWeatherTemperatureUnit,
          onReset: controller.resetWeather,
        );
      case SettingsPageId.developer:
        return SettingsDeveloperPage(
          state: ref.watch(uiDevelopmentProvider),
          controller: ref.read(uiDevelopmentProvider.notifier),
          workspaceSetup: ref.watch(uiWorkspaceSetupProvider),
        );
      case SettingsPageId.about:
        return const SettingsAboutPage();
    }
  }
}

class _SettingsDisplaysBody extends ConsumerWidget {
  const _SettingsDisplaysBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(outputConfigurationProvider);
    final controller = ref.read(outputConfigurationProvider.notifier);
    final confirmation = state.configuration?.pendingConfirmation;
    return Stack(
      fit: StackFit.expand,
      children: [
        const SettingsDisplaysPage(),
        if (confirmation != null)
          SettingsDisplayConfirmationDialog(
            confirmation: confirmation,
            busy: state.applying,
            onKeep: () => unawaited(controller.keepChanges()),
            onRevert: () => unawaited(controller.rollbackChanges()),
            onExpired: () => unawaited(controller.refresh()),
          ),
      ],
    );
  }
}

WallpaperResource _wallpaperFor(
  WallpaperAssignment assignment,
  DisplayLayout? layout,
) {
  final outputName = layout?.mainOutput?.name;
  return outputName == null ? assignment.all : assignment.forOutput(outputName);
}

/// Centres a page in a content column capped at [settingsContentMaxWidth].
///
/// The horizontal inset follows §2.2: 24 when the column is at least 600 wide,
/// otherwise 16.
class _SettingsContentColumn extends StatelessWidget {
  const _SettingsContentColumn({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final inset = constraints.maxWidth >= 600 ? 24.0 : 16.0;
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: inset),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              key: settingsContentColumnKey,
              constraints: const BoxConstraints(
                maxWidth: settingsContentMaxWidth,
              ),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

/// Single-column detail stage: a back affordance above the page content plus an
/// Escape shortcut that exists only while the detail is open (§3.5).
///
/// The shortcut is registered above the page content, so any inner Escape
/// binding (display dropdown, shortcut editor) resolves first and keeps working.
class _SettingsDetailScaffold extends StatelessWidget {
  const _SettingsDetailScaffold({required this.onBack, required this.child});

  final VoidCallback onBack;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.escape):
            _DismissSettingsDetailIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _DismissSettingsDetailIntent:
              CallbackAction<_DismissSettingsDetailIntent>(
                onInvoke: (_) {
                  onBack();
                  return null;
                },
              ),
        },
        child: Focus(
          // The detail stage takes focus on open so Escape is dispatchable even
          // before the user tabs to a control. Page-level overlays that
          // autofocus (color picker, shortcut editor, display menu) become
          // deeper focus nodes and keep their own Escape handling.
          autofocus: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(top: 16, bottom: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _SettingsBackButton(onPressed: onBack),
                ),
              ),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

class _DismissSettingsDetailIntent extends Intent {
  const _DismissSettingsDetailIntent();
}

/// 40dp circular back affordance (§2.3).
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
