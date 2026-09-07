import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../launcher/controllers/home_grid_controller.dart';
import '../../launcher/models/desktop_app.dart';
import '../../launcher/models/home_grid_item.dart';
import '../../launcher/services/app_launcher.dart';
import '../../local_apps/local_flutter_application.dart';
import '../../localization/denial_localizations.dart';
import '../../models/denial_window.dart';
import '../../state/pinned_apps.dart';
import '../../state/shell_controller.dart';
import '../../widgets/shell_menu.dart';
import '../../state/display_layout.dart';
import '../desktop_workspace.dart';
import 'shelf_app_button.dart';

class _AppEntry {
  _AppEntry({
    required this.appId,
    required this.canonicalId,
    required this.windows,
    required this.isPinned,
    this.iconPath,
    this.icon,
    this.title,
    this.desktopApp,
    this.localApp,
  });

  final String appId;
  final String canonicalId;
  final List<DenialWindow> windows;
  final bool isPinned;
  final String? iconPath;
  final IconData? icon;
  final String? title;
  final DesktopApp? desktopApp;
  final LocalFlutterApplication? localApp;
}

/// Desktop application lookup tables the strip uses to resolve windows back
/// to their launching app.
class _DesktopAppIndex {
  const _DesktopAppIndex(this.byWindowId, this.byId);

  final Map<String, DesktopApp> byWindowId;
  final Map<String, DesktopApp> byId;
}

/// The horizontal strip of running and pinned application buttons on the shelf.
class ShelfAppStrip extends ConsumerStatefulWidget {
  const ShelfAppStrip({super.key});

  @override
  ConsumerState<ShelfAppStrip> createState() => _ShelfAppStripState();
}

class _ShelfAppStripState extends ConsumerState<ShelfAppStrip> {
  final List<String> _stableAppOrder = [];
  late final ScrollController _scrollController;
  bool _userScrolled = false;
  int _lastEntryCount = 0;
  double _lastMaxWidth = 0.0;
  List<HomeGridItem?>? _cachedIndexSlots;
  AppLauncher? _cachedIndexLauncher;
  _DesktopAppIndex? _cachedIndex;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _checkAndCenterScroll(int entryCount, double maxWidth) {
    if (_lastEntryCount == entryCount && _lastMaxWidth == maxWidth) {
      return;
    }
    _lastEntryCount = entryCount;
    _lastMaxWidth = maxWidth;
    _userScrolled = false;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      if (!_userScrolled) {
        final maxScroll = _scrollController.position.maxScrollExtent;
        if (maxScroll > 0) {
          final target = maxScroll / 2.0;
          if ((_scrollController.offset - target).abs() > 1.0) {
            _scrollController.jumpTo(target);
          }
        }
      }
    });
  }

  void _onAppPressed(List<DenialWindow> windows, int? foregroundObjectId) {
    if (windows.isEmpty) return;

    final first = windows.first;
    if (windows.length == 1) {
      if (first.objectId == foregroundObjectId) {
        // Optimistic local minimize keeps the visual response immediate; the
        // native minimize through the bridge releases keyboard focus,
        // suspends the client and echoes the action event that clears the
        // stale foreground state which otherwise wedges the next press.
        ref.read(desktopWorkspaceProvider.notifier).minimize(first.objectId);
        ref.read(denialBridgeProvider).minimizeWindow(first);
      } else {
        ref.read(desktopWorkspaceProvider.notifier).activate(first.objectId);
        ref.read(shellControllerProvider.notifier).focusWindow(first);
      }
      return;
    }

    final activeIndex = windows.indexWhere(
      (w) => w.objectId == foregroundObjectId,
    );
    if (activeIndex != -1) {
      final next = windows[(activeIndex + 1) % windows.length];
      ref.read(desktopWorkspaceProvider.notifier).activate(next.objectId);
      ref.read(shellControllerProvider.notifier).focusWindow(next);
    } else {
      ref.read(desktopWorkspaceProvider.notifier).activate(first.objectId);
      ref.read(shellControllerProvider.notifier).focusWindow(first);
    }
  }

  void _launchApp(BuildContext context, _AppEntry entry) {
    if (entry.localApp != null) {
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
            entry.localApp!.id,
            availableBounds: availableBounds,
            title: entry.localApp!.titleFor(context),
          );
      return;
    }

    if (entry.desktopApp != null) {
      ref.read(appLauncherProvider).launch(entry.desktopApp!);
    }
  }

  _DesktopAppIndex _resolveDesktopAppIndex(
    List<HomeGridItem?>? slots,
    AppLauncher appLauncher,
  ) {
    final cached = _cachedIndex;
    if (cached != null &&
        identical(slots, _cachedIndexSlots) &&
        identical(appLauncher, _cachedIndexLauncher)) {
      return cached;
    }
    final byWindowId = <String, DesktopApp>{};
    final byId = <String, DesktopApp>{};
    if (slots != null) {
      for (final item in slots.whereType<HomeGridItem>()) {
        final app = item.app;
        if (app == null) continue;
        byId[app.id] = app;
        byId[_normalizeAppId(app.id)] = app;
        if (app.id.toLowerCase().endsWith('.desktop')) {
          final stripped = app.id.substring(
            0,
            app.id.length - '.desktop'.length,
          );
          byId[stripped] = app;
          byId[_normalizeAppId(stripped)] = app;
        }
        for (final id in appLauncher.expectedWindowAppIds(app)) {
          byWindowId.putIfAbsent(_normalizeAppId(id), () => app);
          byId.putIfAbsent(_normalizeAppId(id), () => app);
        }
      }
    }
    final index = _DesktopAppIndex(byWindowId, byId);
    _cachedIndexSlots = slots;
    _cachedIndexLauncher = appLauncher;
    _cachedIndex = index;
    return index;
  }

  List<Widget> _buildContextMenu(BuildContext context, _AppEntry entry) {
    final l10n = context.l10n;
    final pinnedController = ref.read(pinnedAppsProvider.notifier);
    final items = <Widget>[];

    if (entry.windows.isNotEmpty) {
      items.add(
        ShellMenuItem(
          label: l10n.shelfNewWindow,
          icon: Icons.add_to_photos_rounded,
          onPressed: () => _launchApp(context, entry),
        ),
      );

      if (entry.windows.length > 1) {
        items.add(
          ShellMenuItem(
            label: l10n.shelfCycleWindows,
            icon: Icons.view_carousel_rounded,
            onPressed: () {
              final foregroundObjectId = ref.read(
                shellControllerProvider.select((s) => s.foregroundObjectId),
              );
              _onAppPressed(entry.windows, foregroundObjectId);
            },
          ),
        );
      }
    } else {
      items.add(
        ShellMenuItem(
          label: l10n.shelfOpenApp,
          icon: Icons.launch_rounded,
          onPressed: () => _launchApp(context, entry),
        ),
      );
    }

    items.add(const ShellMenuDivider());

    if (entry.isPinned) {
      items.add(
        ShellMenuItem(
          label: l10n.shelfUnpinFromShelf,
          icon: Icons.push_pin_outlined,
          onPressed: () => pinnedController.unpin(entry.canonicalId),
        ),
      );
    } else {
      items.add(
        ShellMenuItem(
          label: l10n.shelfPinToShelf,
          icon: Icons.push_pin_rounded,
          onPressed: () => pinnedController.pin(entry.canonicalId),
        ),
      );
    }

    if (entry.windows.isNotEmpty) {
      items.add(const ShellMenuDivider());
      items.add(
        ShellMenuItem(
          label: entry.windows.length > 1
              ? l10n.shelfCloseAllWindows
              : l10n.shelfClose,
          icon: Icons.close_rounded,
          destructive: true,
          onPressed: () {
            for (final w in entry.windows) {
              ref.read(shellControllerProvider.notifier).closeWindow(w);
            }
          },
        ),
      );
    }

    return items;
  }

  @override
  Widget build(BuildContext context) {
    final pinnedAppIds = ref.watch(pinnedAppsProvider);
    final openWindows = ref.watch(
      shellControllerProvider.select((state) => state.openAppWindows),
    );
    final foregroundObjectId = ref.watch(
      shellControllerProvider.select((state) => state.foregroundObjectId),
    );
    final slots = ref.watch(
      homeGridControllerProvider.select((state) => state.asData?.value.slots),
    );
    final localRegistry = ref.watch(localFlutterApplicationRegistryProvider);
    final appLauncher = ref.watch(appLauncherProvider);

    // Rebuild the desktop application lookup index only when the grid slots
    // or the launcher change; window title and focus updates rebuild this
    // widget far more often and must not pay for the O(slots) rescan.
    final index = _resolveDesktopAppIndex(slots, appLauncher);
    final desktopAppsByWindowId = index.byWindowId;
    final desktopAppsById = index.byId;

    DesktopApp? findDesktopApp(String id) {
      final norm = _normalizeAppId(id);
      return desktopAppsByWindowId[norm] ??
          desktopAppsById[norm] ??
          desktopAppsById[id];
    }

    String resolveCanonicalId(String id) {
      final local = localRegistry[id];
      if (local != null) return local.id;
      final desktop = findDesktopApp(id);
      if (desktop != null) return desktop.id;
      return id;
    }

    bool checkIsPinned(String id) {
      final canon = _normalizeAppId(resolveCanonicalId(id));
      final norm = _normalizeAppId(id);
      return pinnedAppIds.any((p) {
        final pNorm = _normalizeAppId(p);
        final pCanon = _normalizeAppId(resolveCanonicalId(p));
        return pNorm == norm ||
            pCanon == canon ||
            pNorm == canon ||
            pCanon == norm;
      });
    }

    final appWindows = <String, List<DenialWindow>>{};
    for (final window in openWindows) {
      if (!window.isUserApp) continue;
      final key = window.appId.isNotEmpty
          ? window.appId
          : 'window:${window.objectId}';
      (appWindows[key] ??= <DenialWindow>[]).add(window);
    }

    final entries = <_AppEntry>[];
    final processedWindowKeys = <String>{};

    // 1. First add pinned applications in pinned order.
    for (final pinnedId in pinnedAppIds) {
      final canonicalId = resolveCanonicalId(pinnedId);
      final localApp = localRegistry[pinnedId] ?? localRegistry[canonicalId];
      final desktopApp =
          findDesktopApp(pinnedId) ?? findDesktopApp(canonicalId);

      final matchingWindows = <DenialWindow>[];
      for (final windowEntry in appWindows.entries) {
        final wKey = windowEntry.key;
        if (resolveCanonicalId(wKey) == canonicalId ||
            _normalizeAppId(wKey) == _normalizeAppId(pinnedId) ||
            _normalizeAppId(wKey) == _normalizeAppId(canonicalId)) {
          matchingWindows.addAll(windowEntry.value);
          processedWindowKeys.add(wKey);
        }
      }
      matchingWindows.sort((a, b) => a.objectId.compareTo(b.objectId));

      String? iconPath;
      IconData? icon;
      String? title;

      if (localApp != null) {
        icon = localApp.icon;
        title = localApp.titleFor(context);
      } else if (desktopApp != null) {
        iconPath = desktopApp.iconPath;
        title = desktopApp.name;
      } else if (matchingWindows.isNotEmpty) {
        final firstWindow = matchingWindows.first;
        title = firstWindow.title.isNotEmpty ? firstWindow.title : pinnedId;
      } else {
        title = pinnedId;
      }

      entries.add(
        _AppEntry(
          appId: pinnedId,
          canonicalId: canonicalId,
          windows: matchingWindows,
          isPinned: true,
          iconPath: iconPath,
          icon: icon,
          title: title,
          desktopApp: desktopApp,
          localApp: localApp,
        ),
      );
    }

    // 2. Add remaining unpinned running applications in stable insertion order.
    _stableAppOrder.removeWhere((id) => !appWindows.containsKey(id));
    for (final appId in appWindows.keys) {
      if (!_stableAppOrder.contains(appId)) {
        _stableAppOrder.add(appId);
      }
    }

    for (final appId in _stableAppOrder) {
      if (processedWindowKeys.contains(appId)) continue;
      if (checkIsPinned(appId)) continue;

      final windows = appWindows[appId];
      if (windows == null || windows.isEmpty) continue;
      windows.sort((a, b) => a.objectId.compareTo(b.objectId));

      final canonicalId = resolveCanonicalId(appId);
      final localApp = localRegistry[appId] ?? localRegistry[canonicalId];
      final desktopApp = findDesktopApp(appId) ?? findDesktopApp(canonicalId);

      String? iconPath;
      IconData? icon;
      String? title;

      if (localApp != null) {
        icon = localApp.icon;
        title = localApp.titleFor(context);
      } else if (desktopApp != null) {
        iconPath = desktopApp.iconPath;
        title = desktopApp.name;
      } else {
        final firstWindow = windows.first;
        title = firstWindow.title.isNotEmpty ? firstWindow.title : appId;
      }

      entries.add(
        _AppEntry(
          appId: appId,
          canonicalId: canonicalId,
          windows: windows,
          isPinned: false,
          iconPath: iconPath,
          icon: icon,
          title: title,
          desktopApp: desktopApp,
          localApp: localApp,
        ),
      );
    }

    if (entries.isEmpty) {
      return const SizedBox.shrink();
    }

    final stripContent = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < entries.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          ShelfAppButton(
            key: ValueKey('shelf-app-${entries[i].canonicalId}'),
            appId: entries[i].appId,
            iconPath: entries[i].iconPath,
            icon: entries[i].icon,
            title: entries[i].title,
            windowCount: entries[i].windows.length,
            isActive: entries[i].windows.any(
              (w) => w.objectId == foregroundObjectId,
            ),
            isPinned: entries[i].isPinned,
            onPressed: () {
              if (entries[i].windows.isEmpty) {
                _launchApp(context, entries[i]);
              } else {
                _onAppPressed(entries[i].windows, foregroundObjectId);
              }
            },
            menuBuilder: (menuContext) =>
                _buildContextMenu(menuContext, entries[i]),
          ),
        ],
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        _checkAndCenterScroll(entries.length, constraints.maxWidth);

        return NotificationListener<UserScrollNotification>(
          onNotification: (_) {
            _userScrolled = true;
            return false;
          },
          child: SingleChildScrollView(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: Center(child: stripContent),
            ),
          ),
        );
      },
    );
  }

  static String _normalizeAppId(String value) => value.trim().toLowerCase();
}
