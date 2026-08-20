import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../launcher/controllers/home_grid_controller.dart';
import '../launcher/launcher_providers.dart';
import '../launcher/models/desktop_app.dart';
import '../launcher/models/home_grid_item.dart';
import '../local_apps/local_flutter_application.dart';
import '../localization/denial_localizations.dart';
import '../state/shell_controller.dart';
import '../theme/shell_theme.dart';
import '../theme/tokens.dart';
import '../wallpaper/state/wallpaper_accent.dart';
import '../widgets/session/power_session_surface.dart';
import '../widgets/shell_cursor.dart';
import '../widgets/shell_surface_host.dart';
import 'controllers/desktop_tile_controller.dart';
import 'desktop_start_menu_app_list.dart';
import 'desktop_start_menu_rail.dart';
import 'desktop_tile_board.dart';
import 'desktop_tile_menu.dart';
import 'models/desktop_tile.dart';

/// Height of the full-width search strip along the bottom edge.
const double _searchStripHeight = 48;

/// Windows 10 style start menu: icon rail, letter-grouped all-apps list, and
/// tile area, over a full-width search strip.
///
/// The panel keeps Denial's chrome — blurred backdrop, panel radius, wallpaper
/// accent — because those are supplied by the mount point's panel transition
/// and by [shellAccentProvider]; only the interior structure is Windows 10's.
class DesktopStartMenu extends ConsumerStatefulWidget {
  const DesktopStartMenu({
    super.key,
    required this.searchFocusNode,
    required this.onEnter,
    required this.onExit,
    required this.onClose,
    required this.onLaunch,
    required this.onLaunchLocal,
    required this.onOpenSettings,
  });

  final FocusNode searchFocusNode;
  final VoidCallback onEnter;
  final VoidCallback onExit;
  final VoidCallback onClose;
  final ValueChanged<DesktopApp> onLaunch;
  final ValueChanged<LocalFlutterApplication> onLaunchLocal;
  final VoidCallback onOpenSettings;

  /// Width of the all-apps column.
  static const double appListWidth = 260;

  @override
  ConsumerState<DesktopStartMenu> createState() => _DesktopStartMenuState();
}

class _DesktopStartMenuState extends ConsumerState<DesktopStartMenu> {
  late final TextEditingController _searchController;
  bool _railExpanded = false;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController()
      ..addListener(_handleSearchChanged);
    widget.searchFocusNode.addListener(_handleSearchChanged);
  }

  @override
  void dispose() {
    widget.searchFocusNode.removeListener(_handleSearchChanged);
    _searchController
      ..removeListener(_handleSearchChanged)
      ..dispose();
    super.dispose();
  }

  void _handleSearchChanged() {
    setState(() {});
  }

  void _clearSearch() {
    _searchController.clear();
    widget.searchFocusNode.requestFocus();
  }

  void _launch(DesktopStartMenuEntry entry) {
    final desktopApp = entry.desktopApp;
    if (desktopApp != null) {
      widget.onLaunch(desktopApp);
      return;
    }
    widget.onLaunchLocal(entry.localApp!);
  }

  void _openPower() {
    showPowerSessionSurface(ref);
    widget.onClose();
  }

  /// The panel closes 220ms after the pointer leaves it, and a context menu
  /// opened from inside the panel covers the whole scene — which the mouse
  /// tracker reports as the pointer leaving. Letting that through would close
  /// the panel, and the menu with it, before anything in the menu could be
  /// clicked. While one of the panel's own menus is up the exit is treated as
  /// the pointer still being inside, and any close already scheduled is called
  /// off.
  void _handlePointerExit() {
    if (desktopTileMenuIsOpen(ref.read(shellSurfaceControllerProvider))) {
      widget.onEnter();
      return;
    }
    widget.onExit();
  }

  /// Offers to pin or unpin the application an entry stands for.
  ///
  /// The board is the only place a tile can come from, so this menu is what
  /// makes the tile area reachable at all.
  void _showEntryMenu(DesktopStartMenuEntry entry, Offset position) {
    final controller = ref.read(desktopTileControllerProvider.notifier);
    final board =
        ref.read(desktopTileControllerProvider).asData?.value ??
        DesktopTileState.empty;
    final desktopApp = entry.desktopApp;
    final localApp = entry.localApp;
    final itemId = desktopApp != null
        ? 'app:${desktopApp.id}'
        : 'local:${localApp!.id}';
    final pinned = board.contains(itemId);

    showDesktopTileMenu(
      ref: ref,
      // A list row and the tile it created are two different targets, so they
      // must not share a key: the surface host reuses a live surface by key and
      // would show the row's menu on the tile.
      keySuffix: 'list-$itemId',
      position: position,
      entries: <DesktopTileMenuEntry>[
        DesktopTileMenuEntry.item(
          label: pinned
              ? context.l10n.desktopTileUnpinFromStart
              : context.l10n.desktopTilePinToStart,
          icon: pinned ? Icons.remove_circle_outline : Icons.push_pin_outlined,
          onPressed: () {
            if (pinned) {
              controller.unpin(itemId);
            } else if (desktopApp != null) {
              controller.pinApp(desktopApp);
            } else {
              controller.pinLocalApp(localApp!);
            }
          },
        ),
      ],
    );
  }

  /// Hands a well-known user directory to whatever handles directories.
  ///
  /// The path is resolved when the entry is pressed rather than while building,
  /// because `user-dirs.dirs` has to be read from disk to honour a localised
  /// home (this machine's Documents is `文档`).
  Future<void> _openUserDirectory(_StartMenuUserDirectory directory) async {
    final paths = ref.read(runtimePathsProvider);
    final bridge = ref.read(denialBridgeProvider);
    widget.onClose();
    final resolved = await paths.xdgUserDirectory(
      directory.xdgKey,
      fallback: directory.fallbackName,
    );
    bridge.launchApplication(<String>['xdg-open', resolved]);
  }

  @override
  Widget build(BuildContext context) {
    final allApps = startMenuEntries(
      context,
      ref.watch(homeGridControllerProvider),
      ref.watch(localFlutterApplicationRegistryProvider).applications,
    );
    final apps = filterStartMenuEntries(allApps, _searchController.text);
    final searching = _searchController.text.trim().isNotEmpty;
    final theme = ShellTheme.of(context);
    final accent = ref.watch(shellAccentProvider);
    final l10n = context.l10n;

    return MouseRegion(
      onEnter: (_) => widget.onEnter(),
      onExit: (_) => _handlePointerExit(),
      child: FocusTraversalGroup(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.panelColor(ShellColors.panelBackground),
            borderRadius: BorderRadius.circular(theme.panelRadius),
            border: Border.all(color: ShellColors.hairline),
            boxShadow: const [
              BoxShadow(
                color: ShellColors.shadow,
                blurRadius: 36,
                spreadRadius: 3,
                offset: Offset(0, 16),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(theme.panelRadius),
            child: Column(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Row(
                          children: [
                            const SizedBox(
                              width: DesktopStartMenuRail.collapsedWidth,
                            ),
                            SizedBox(
                              width: DesktopStartMenu.appListWidth,
                              child: allApps.isEmpty
                                  ? Center(
                                      child: Text(
                                        l10n.desktopLoadingApplications,
                                        textAlign: TextAlign.center,
                                        style: ShellText.cardTitle.copyWith(
                                          color: ShellColors.textSecondary,
                                        ),
                                      ),
                                    )
                                  : apps.isEmpty
                                  ? const _StartMenuSearchEmptyState()
                                  : DesktopStartMenuAppList(
                                      entries: apps,
                                      searching: searching,
                                      accent: accent,
                                      onLaunch: _launch,
                                      onShowMenu: _showEntryMenu,
                                    ),
                            ),
                            Expanded(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  minWidth: DesktopStartMenuTileArea.minWidth,
                                ),
                                child: DesktopStartMenuTileArea(
                                  accent: accent,
                                  onLaunch: widget.onLaunch,
                                  onLaunchLocal: widget.onLaunchLocal,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        child: DesktopStartMenuRail(
                          expanded: _railExpanded,
                          accent: accent,
                          onToggleExpanded: () =>
                              setState(() => _railExpanded = !_railExpanded),
                          onOpenDocuments: () => unawaited(
                            _openUserDirectory(
                              _StartMenuUserDirectory.documents,
                            ),
                          ),
                          onOpenPictures: () => unawaited(
                            _openUserDirectory(
                              _StartMenuUserDirectory.pictures,
                            ),
                          ),
                          onOpenSettings: widget.onOpenSettings,
                          onOpenPower: _openPower,
                        ),
                      ),
                    ],
                  ),
                ),
                _StartMenuSearchField(
                  controller: _searchController,
                  focusNode: widget.searchFocusNode,
                  onClear: _clearSearch,
                  onSubmit: () {
                    if (searching && apps.isNotEmpty) {
                      _launch(apps.first);
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _StartMenuUserDirectory {
  documents('DOCUMENTS', 'Documents'),
  pictures('PICTURES', 'Pictures');

  const _StartMenuUserDirectory(this.xdgKey, this.fallbackName);

  final String xdgKey;
  final String fallbackName;
}

/// Everything the start menu can launch, ordered by name.
///
/// [HomeGridState.desktopApps] is the full installed set; the tile slots are a
/// user-curated subset of it, so a list built from slots alone would hide most
/// applications. Slots are still folded in so a tiled application survives even
/// if the installed scan misses it.
List<DesktopStartMenuEntry> startMenuEntries(
  BuildContext context,
  AsyncValue<HomeGridState> state,
  Iterable<LocalFlutterApplication> localApps,
) {
  final byId = <String, DesktopStartMenuEntry>{};
  if (state.asData?.value case final grid?) {
    for (final app in grid.desktopApps) {
      byId['desktop:${app.id}'] = DesktopStartMenuEntry.desktop(app);
    }
    for (final item in grid.slots.whereType<HomeGridItem>()) {
      if (item.app case final app?) {
        byId['desktop:${app.id}'] = DesktopStartMenuEntry.desktop(app);
      }
    }
  }
  for (final app in localApps) {
    byId['local:${app.id}'] = DesktopStartMenuEntry.local(app, context);
  }
  return byId.values.toList(growable: false)
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
}

List<DesktopStartMenuEntry> filterStartMenuEntries(
  List<DesktopStartMenuEntry> entries,
  String query,
) {
  final normalizedQuery = query.trim().toLowerCase();
  if (normalizedQuery.isEmpty) {
    return entries;
  }

  return entries
      .where((entry) {
        final searchable = <String>[
          entry.name,
          entry.id,
          ...entry.categories,
        ].join(' ').toLowerCase();
        return searchable.contains(normalizedQuery);
      })
      .toList(growable: false);
}

/// The tile area: the pin board, or the hint that explains how tiles get there.
///
/// The width floor stays here because it is a three-column budget concern: an
/// unconstrained [Expanded] holding an empty board would collapse to zero and
/// let the other two columns spread out.
class DesktopStartMenuTileArea extends ConsumerWidget {
  const DesktopStartMenuTileArea({
    super.key,
    required this.accent,
    required this.onLaunch,
    required this.onLaunchLocal,
  });

  static const double minWidth = 360;

  final WallpaperAccent accent;
  final ValueChanged<DesktopApp> onLaunch;
  final ValueChanged<LocalFlutterApplication> onLaunchLocal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DesktopTileBoard(
      accent: accent,
      onLaunch: onLaunch,
      onLaunchLocal: onLaunchLocal,
    );
  }
}

class _StartMenuSearchEmptyState extends StatelessWidget {
  const _StartMenuSearchEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.search_off_rounded,
            size: 34,
            color: ShellColors.textTertiary,
          ),
          const SizedBox(height: 10),
          Text(
            context.l10n.desktopNoApplicationsFound,
            style: ShellText.cardTitle.copyWith(
              color: ShellColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// The search strip, spanning the panel's full width along its bottom edge.
///
/// Windows 10 puts this box in the taskbar rather than the menu; keeping it
/// inside the panel is what lets the menu own its own focus and dismissal.
class _StartMenuSearchField extends StatelessWidget {
  const _StartMenuSearchField({
    required this.controller,
    required this.focusNode,
    required this.onClear,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onClear;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final hasQuery = controller.text.isNotEmpty;
    final accent = ShellTheme.of(context).accentPalette;
    final l10n = context.l10n;
    return Semantics(
      textField: true,
      label: l10n.desktopSearchApplications,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: ShellColors.surfaceContainerHigh,
          border: const Border(top: BorderSide(color: ShellColors.hairline)),
        ),
        child: SizedBox(
          height: _searchStripHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                const Icon(
                  Icons.search_rounded,
                  size: 20,
                  color: ShellColors.textSecondary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      if (!hasQuery)
                        IgnorePointer(
                          child: Text(
                            l10n.desktopStartMenuSearchHint,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: ShellColors.textTertiary,
                              fontSize: 14,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ),
                      EditableText(
                        controller: controller,
                        focusNode: focusNode,
                        mouseCursor: ShellMouseCursors.text,
                        autofocus: true,
                        maxLines: 1,
                        keyboardType: TextInputType.text,
                        textInputAction: TextInputAction.search,
                        onEditingComplete: () {},
                        onSubmitted: (_) => onSubmit(),
                        style: ShellText.base,
                        cursorColor: accent.primary,
                        backgroundCursorColor: ShellColors.textSecondary,
                        selectionColor: accent.selection,
                      ),
                    ],
                  ),
                ),
                if (hasQuery) ...[
                  const SizedBox(width: 8),
                  Semantics(
                    button: true,
                    label: l10n.desktopClearApplicationSearch,
                    child: MouseRegion(
                      cursor: ShellMouseCursors.link,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: onClear,
                        child: const SizedBox.square(
                          dimension: 28,
                          child: Icon(
                            Icons.close_rounded,
                            size: 18,
                            color: ShellColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
