part of 'desktop_shell.dart';

@immutable
class _DesktopLauncherEntry {
  _DesktopLauncherEntry._({
    required this.navigationId,
    required this.id,
    required this.name,
    required this.categories,
    required this.iconPath,
    required this.icon,
    required this.desktopApp,
    required this.localApp,
  }) : sortName = name.toLowerCase(),
       searchableText = <String>[
         id,
         name,
         ...categories,
       ].join(' ').toLowerCase();

  factory _DesktopLauncherEntry.desktop(DesktopApp app) {
    return _DesktopLauncherEntry._(
      navigationId: 'desktop:${app.id}',
      id: app.id,
      name: app.name,
      categories: app.categories,
      iconPath: app.iconPath,
      icon: null,
      desktopApp: app,
      localApp: null,
    );
  }

  factory _DesktopLauncherEntry.local(
    LocalFlutterApplication app,
    BuildContext context,
  ) {
    return _DesktopLauncherEntry._(
      navigationId: 'local:${app.id}',
      id: app.id,
      name: app.titleFor(context),
      categories: app.categoriesFor(context),
      iconPath: null,
      icon: app.icon,
      desktopApp: null,
      localApp: app,
    );
  }

  final String navigationId;
  final String id;
  final String name;
  final List<String> categories;
  final String? iconPath;
  final IconData? icon;
  final DesktopApp? desktopApp;
  final LocalFlutterApplication? localApp;
  final String sortName;
  final String searchableText;
}

@immutable
class _DesktopLauncherTarget {
  const _DesktopLauncherTarget({
    required this.entry,
    required this.selectionId,
    required this.row,
    required this.column,
    required this.scrollTop,
    required this.scrollExtent,
  });

  final _DesktopLauncherEntry entry;
  final String selectionId;
  final int row;
  final int column;
  final double scrollTop;
  final double scrollExtent;
}

String _catalogLauncherTargetId(String entryId) => 'catalog:$entryId';

String _suggestedLauncherTargetId(String entryId) => 'suggested:$entryId';

class DesktopApplicationLauncher extends ConsumerStatefulWidget {
  const DesktopApplicationLauncher({
    super.key,
    required this.searchFocusNode,
    required this.onEnter,
    required this.onExit,
    required this.onDismiss,
    required this.onLaunch,
    required this.onLaunchLocal,
    this.visible,
  });

  final FocusNode searchFocusNode;
  final VoidCallback onEnter;
  final VoidCallback onExit;

  /// Immediately closes the launcher and releases its keyboard capture.
  final VoidCallback onDismiss;
  final ValueChanged<DesktopApp> onLaunch;
  final ValueChanged<LocalFlutterApplication> onLaunchLocal;
  final bool? visible;

  @override
  ConsumerState<DesktopApplicationLauncher> createState() =>
      _DesktopApplicationLauncherState();
}

class _DesktopApplicationLauncherState
    extends ConsumerState<DesktopApplicationLauncher>
    with SingleTickerProviderStateMixin {
  static const double _tileExtent = 112;
  static const double _suggestedTileExtent = 96;
  static const double _tileSpacing = 8;

  late final TextEditingController _searchController;
  final ScrollController _gridController = ScrollController();
  late final AnimationController _expandController;
  bool _isOpen = false;
  bool _hasInflated = false;
  String _lastSearchText = '';
  String? _selectedTargetId;
  bool _hasCachedDesktopApps = false;
  List<HomeGridItem?>? _cachedHomeSlots;
  List<_DesktopLauncherEntry>? _cachedDesktopApps;
  LocalFlutterApplicationRegistry? _cachedLocalRegistry;
  Locale? _cachedLocale;
  List<_DesktopLauncherEntry>? _cachedLocalApps;
  List<_DesktopLauncherEntry>? _cachedInstalledApps;
  List<_DesktopLauncherEntry>? _cachedFilteredSource;
  String? _cachedNormalizedQuery;
  List<_DesktopLauncherEntry>? _cachedFilteredApps;
  List<_DesktopLauncherTarget> _visibleTargets =
      const <_DesktopLauncherTarget>[];
  final Map<String, GlobalKey<_DesktopAppTileState>> _tileKeys =
      <String, GlobalKey<_DesktopAppTileState>>{};
  late final ProviderSubscription<bool> _visibilitySubscription;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController()
      ..addListener(_handleQueryChanged);
    final initialOpen =
        widget.visible ?? ref.read(desktopWorkspaceProvider).launcherOpen;
    _isOpen = initialOpen;
    _hasInflated = initialOpen;
    _expandController = AnimationController.unbounded(
      vsync: this,
      value: initialOpen ? 1.0 : 0.0,
    );
    _visibilitySubscription = ref.listenManual<bool>(
      desktopWorkspaceProvider.select((state) => state.launcherOpen),
      _handleVisibilityChanged,
    );
  }

  @override
  void didUpdateWidget(covariant DesktopApplicationLauncher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible != null && widget.visible != oldWidget.visible) {
      _updateVisibility(widget.visible!);
    }
  }

  @override
  void dispose() {
    _visibilitySubscription.close();
    _expandController.dispose();
    _searchController
      ..removeListener(_handleQueryChanged)
      ..dispose();
    _gridController.dispose();
    super.dispose();
  }

  void _handleQueryChanged() {
    final searchText = _searchController.text;
    if (searchText == _lastSearchText) {
      return;
    }
    _lastSearchText = searchText;
    setState(() => _selectedTargetId = null);
    _resetGridScroll();
  }

  void _handleVisibilityChanged(bool? previous, bool visible) {
    _updateVisibility(visible);
    final targets = _visibleTargets;
    final previousIndex = _selectedIndexFor(targets);
    final previousSelection = previousIndex < 0
        ? null
        : targets[previousIndex].selectionId;
    _selectedTargetId = null;
    if (previousSelection != null &&
        targets.isNotEmpty &&
        previousSelection != targets.first.selectionId) {
      _setTileSelected(previousSelection, false);
      _setTileSelected(targets.first.selectionId, true);
    }
  }

  void _updateVisibility(bool visible) {
    if (_isOpen == visible) return;
    _isOpen = visible;
    final settle = springTo(
      _expandController,
      visible ? 1.0 : 0.0,
      spring: Motion.expressiveSpatialDefault,
      telemetryLabel: 'launcher_bubble_toggle',
    );
    if (visible) {
      _hasInflated = true;
      return;
    }
    // The kept-alive grid keeps its scroll controller attached, so the
    // fresh-state reset can run once the collapse settles instead of one
    // frame into the next reopen. Running it while the bubble is still
    // visible would snap the grid mid-collapse.
    settle.whenCompleteOrCancel(() {
      if (mounted && !_isOpen && _expandController.value <= 0.001) {
        _resetForNextOpen();
      }
    });
  }

  /// Restores the launcher to a fresh state for the next show.
  ///
  /// The kept-alive grid keeps its scroll offset and search text while the
  /// bubble collapses, so the reset waits until the collapse settles and the
  /// subtree is parked off stage. The scroll controller stays attached, so no
  /// post-frame scroll hop into the open animation is needed anymore.
  void _resetForNextOpen() {
    if (_searchController.text.isNotEmpty) {
      _searchController.clear();
    }
    _resetGridScroll();
  }

  void _clearSearch() {
    _searchController.clear();
    widget.searchFocusNode.requestFocus();
  }

  void _launch(_DesktopLauncherEntry entry) {
    final desktopApp = entry.desktopApp;
    if (desktopApp != null) {
      widget.onLaunch(desktopApp);
      return;
    }
    widget.onLaunchLocal(entry.localApp!);
  }

  int _selectedIndexFor(List<_DesktopLauncherTarget> targets) {
    if (targets.isEmpty) {
      return -1;
    }
    final selectedTargetId = _selectedTargetId;
    if (selectedTargetId == null) {
      return 0;
    }
    final index = targets.indexWhere(
      (target) => target.selectionId == selectedTargetId,
    );
    return index < 0 ? 0 : index;
  }

  void _selectIndex(List<_DesktopLauncherTarget> targets, int index) {
    if (targets.isEmpty) {
      return;
    }
    assert(index >= 0 && index < targets.length);
    final previousIndex = _selectedIndexFor(targets);
    final previousTargetId = previousIndex < 0
        ? null
        : targets[previousIndex].selectionId;
    final selectedTarget = targets[index];
    if (_selectedTargetId != selectedTarget.selectionId) {
      _selectedTargetId = selectedTarget.selectionId;
      if (previousTargetId != null) {
        _setTileSelected(previousTargetId, false);
      }
      _setTileSelected(selectedTarget.selectionId, true);
    }
    _revealSelected(selectedTarget);
  }

  void _setTileSelected(String targetId, bool selected) {
    _tileKeys[targetId]?.currentState?.setSelected(selected);
  }

  GlobalKey<_DesktopAppTileState> _tileKey(String targetId) {
    return _tileKeys.putIfAbsent(
      targetId,
      () => GlobalKey<_DesktopAppTileState>(
        debugLabel: 'desktop-app-tile-$targetId',
      ),
    );
  }

  void _moveSelection(List<_DesktopLauncherTarget> targets, int delta) {
    if (targets.isEmpty) {
      return;
    }
    final current = _selectedIndexFor(targets);
    _selectIndex(targets, (current + delta) % targets.length);
  }

  void _moveSelectionVertically(
    List<_DesktopLauncherTarget> targets,
    int direction,
  ) {
    if (targets.isEmpty) {
      return;
    }
    assert(direction == -1 || direction == 1);
    final current = targets[_selectedIndexFor(targets)];
    final rowCount = targets.last.row + 1;
    final targetRow = (current.row + direction) % rowCount;
    final rowTargets = targets
        .where((target) => target.row == targetRow)
        .toList(growable: false);
    final targetColumn = current.column.clamp(0, rowTargets.length - 1).toInt();
    _selectIndex(targets, targets.indexOf(rowTargets[targetColumn]));
  }

  void _launchSelected(List<_DesktopLauncherTarget> targets) {
    final selectedIndex = _selectedIndexFor(targets);
    if (selectedIndex >= 0) {
      _launch(targets[selectedIndex].entry);
    }
  }

  void _resetGridScroll() {
    if (!_gridController.hasClients) {
      return;
    }
    final position = _gridController.position;
    if (position.pixels != position.minScrollExtent) {
      _gridController.jumpTo(position.minScrollExtent);
    }
  }

  List<_DesktopLauncherEntry> _resolveInstalledApps(
    BuildContext context,
    List<HomeGridItem?>? slots,
    LocalFlutterApplicationRegistry registry,
  ) {
    final locale = Localizations.localeOf(context);
    var changed = false;
    var desktopApps = _cachedDesktopApps;
    if (!_hasCachedDesktopApps || !identical(slots, _cachedHomeSlots)) {
      desktopApps = _installedDesktopApps(slots);
      _hasCachedDesktopApps = true;
      _cachedHomeSlots = slots;
      _cachedDesktopApps = desktopApps;
      changed = true;
    }
    var localApps = _cachedLocalApps;
    if (localApps == null ||
        !identical(registry, _cachedLocalRegistry) ||
        locale != _cachedLocale) {
      localApps = _installedLocalApps(context, registry.applications);
      _cachedLocalRegistry = registry;
      _cachedLocale = locale;
      _cachedLocalApps = localApps;
      changed = true;
    }
    final cached = _cachedInstalledApps;
    if (!changed && cached != null) {
      return cached;
    }

    final apps = _mergeInstalledApps(desktopApps!, localApps);
    final activeIds = <String>{for (final app in apps) app.navigationId};
    final activeTargetIds = <String>{
      for (final id in activeIds) _catalogLauncherTargetId(id),
      for (final id in activeIds) _suggestedLauncherTargetId(id),
    };
    _tileKeys.removeWhere((id, _) => !activeTargetIds.contains(id));
    if (!activeTargetIds.contains(_selectedTargetId)) {
      _selectedTargetId = null;
    }
    _cachedInstalledApps = apps;
    _cachedFilteredSource = null;
    _cachedNormalizedQuery = null;
    _cachedFilteredApps = null;
    return apps;
  }

  List<_DesktopLauncherEntry> _resolveSuggestedApps(
    List<_DesktopLauncherEntry> apps,
    List<String> recentEntryIds,
    int maximumCount,
  ) {
    if (apps.isEmpty || recentEntryIds.isEmpty || maximumCount <= 0) {
      return const <_DesktopLauncherEntry>[];
    }

    final appsById = <String, _DesktopLauncherEntry>{
      for (final app in apps) app.navigationId: app,
    };
    final suggested = <_DesktopLauncherEntry>[];
    for (final entryId in recentEntryIds) {
      final app = appsById[entryId];
      if (app == null) {
        continue;
      }
      suggested.add(app);
      if (suggested.length == maximumCount) {
        break;
      }
    }
    return suggested;
  }

  List<_DesktopLauncherTarget> _resolveNavigationTargets(
    List<_DesktopLauncherEntry> suggestedApps,
    List<_DesktopLauncherEntry> catalogApps,
    int columnCount,
  ) {
    final catalogRowOffset = suggestedApps.isEmpty ? 0 : 1;
    final catalogScrollOffset = suggestedApps.isEmpty
        ? 0.0
        : _suggestedTileExtent + _tileSpacing * 2 + 1;
    return <_DesktopLauncherTarget>[
      for (var index = 0; index < suggestedApps.length; index += 1)
        _DesktopLauncherTarget(
          entry: suggestedApps[index],
          selectionId: _suggestedLauncherTargetId(
            suggestedApps[index].navigationId,
          ),
          row: 0,
          column: index,
          scrollTop: 0,
          scrollExtent: _suggestedTileExtent,
        ),
      for (var index = 0; index < catalogApps.length; index += 1)
        _DesktopLauncherTarget(
          entry: catalogApps[index],
          selectionId: _catalogLauncherTargetId(
            catalogApps[index].navigationId,
          ),
          row: catalogRowOffset + (index ~/ columnCount),
          column: index % columnCount,
          scrollTop:
              catalogScrollOffset +
              (index ~/ columnCount) * (_tileExtent + _tileSpacing),
          scrollExtent: _tileExtent,
        ),
    ];
  }

  List<_DesktopLauncherEntry> _resolveFilteredApps(
    List<_DesktopLauncherEntry> apps,
    String query,
  ) {
    final normalizedQuery = query.trim().toLowerCase();
    final cached = _cachedFilteredApps;
    if (cached != null &&
        identical(apps, _cachedFilteredSource) &&
        normalizedQuery == _cachedNormalizedQuery) {
      return cached;
    }
    final filtered = _filterInstalledApps(apps, normalizedQuery);
    _cachedFilteredSource = apps;
    _cachedNormalizedQuery = normalizedQuery;
    _cachedFilteredApps = filtered;
    return filtered;
  }

  void _revealSelected(_DesktopLauncherTarget target) {
    if (!_gridController.hasClients) {
      return;
    }
    final position = _gridController.position;
    final itemTop = target.scrollTop;
    final itemBottom = itemTop + target.scrollExtent;
    final viewport = position.viewportDimension;
    final current = position.pixels;
    final double scrollTarget;
    if (itemBottom > current + viewport) {
      scrollTarget = itemBottom - viewport + _tileSpacing;
    } else if (itemTop < current) {
      scrollTarget = itemTop - _tileSpacing;
    } else {
      return;
    }
    final clampedTarget = scrollTarget
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if (MediaQuery.disableAnimationsOf(context)) {
      _gridController.jumpTo(clampedTarget);
      return;
    }
    unawaited(
      _gridController.animateTo(
        clampedTarget,
        duration: const Duration(milliseconds: 200),
        curve: Motion.standard,
      ),
    );
  }

  int _crossAxisCountFor(double width) {
    final count = (width / (_tileExtent + _tileSpacing)).ceil();
    return count < 1 ? 1 : count;
  }

  @override
  Widget build(BuildContext context) {
    final slots = ref.watch(
      homeGridControllerProvider.select((state) => state.asData?.value.slots),
    );
    final localRegistry = ref.watch(localFlutterApplicationRegistryProvider);
    final recentEntryIds = ref.watch(applicationRecentsProvider);
    final allApps = _resolveInstalledApps(context, slots, localRegistry);
    final apps = _resolveFilteredApps(allApps, _searchController.text);
    final useChromeOsShelf = ref.watch(
      shellSettingsProvider.select((s) => s.layout.useChromeOsShelf),
    );
    final theme = ShellTheme.of(context);
    final l10n = context.l10n;
    final bubbleRadius = theme.borderRadius(ShellShapeScale.large);
    return MouseRegion(
      onEnter: (_) => widget.onEnter(),
      onExit: (_) => widget.onExit(),
      child: FocusTraversalGroup(
        child: CallbackShortcuts(
          bindings: <ShortcutActivator, VoidCallback>{
            const SingleActivator(LogicalKeyboardKey.escape): widget.onDismiss,
            const SingleActivator(LogicalKeyboardKey.tab): () =>
                _moveSelection(_visibleTargets, 1),
            const SingleActivator(LogicalKeyboardKey.tab, shift: true): () =>
                _moveSelection(_visibleTargets, -1),
            const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                _moveSelectionVertically(_visibleTargets, 1),
            const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                _moveSelectionVertically(_visibleTargets, -1),
            const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
                _moveSelection(_visibleTargets, 1),
            const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
                _moveSelection(_visibleTargets, -1),
          },
          child: AnimatedBuilder(
            animation: _expandController,
            builder: (context, child) {
              final progress = _expandController.value;
              final hidden = useChromeOsShelf && progress <= 0.001 && !_isOpen;
              if (hidden && !_hasInflated) {
                // Stay unmounted until the first open so shell startup does
                // not pay the bubble's inflate.
                return const SizedBox.shrink();
              }
              final clampedProgress = progress.clamp(0.0, 1.0);
              final scale = math.max(0.0, 0.85 + 0.15 * progress);

              Widget content = DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.panelColor(context.shellColors.panelBackground),
                  borderRadius: bubbleRadius,
                  border: Border.all(
                    color: context.shellColors.hairlineSoft,
                    width: 1.0,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: child,
                ),
              );

              if (!useChromeOsShelf) {
                return content;
              }

              content = SizedBox(
                width: _LauncherBubbleMetrics.width(MediaQuery.sizeOf(context)),
                child: ShellBackdropBlur(
                  strength: clampedProgress,
                  borderRadius: bubbleRadius,
                  child: content,
                ),
              );
              // The wrapper keeps one shape for the shown and hidden states,
              // so parking the collapsed bubble flips the Offstage flag
              // instead of re-inflating the subtree on every reopen. TickerMode
              // parks the subtree's animations while it is hidden.
              return TickerMode(
                enabled: !hidden,
                child: Offstage(
                  offstage: hidden,
                  child: Transform.scale(
                    scale: scale,
                    alignment: Alignment.bottomLeft,
                    child: content,
                  ),
                ),
              );
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DesktopAppSearchField(
                  controller: _searchController,
                  focusNode: widget.searchFocusNode,
                  onClear: _clearSearch,
                  onSubmit: () => _launchSelected(_visibleTargets),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final columnCount = _crossAxisCountFor(
                        constraints.maxWidth,
                      );
                      final suggestedApps = _resolveSuggestedApps(
                        apps,
                        recentEntryIds,
                        columnCount,
                      );
                      final navigationTargets = _resolveNavigationTargets(
                        suggestedApps,
                        apps,
                        columnCount,
                      );
                      _visibleTargets = navigationTargets;
                      return CustomScrollView(
                        controller: _gridController,
                        scrollCacheExtent: const ScrollCacheExtent.pixels(0),
                        slivers: <Widget>[
                          if (suggestedApps.isNotEmpty) ...<Widget>[
                            SliverToBoxAdapter(
                              child: _DesktopApplicationSuggestionsRow(
                                apps: suggestedApps,
                                selectedTargetId: _selectedTargetId,
                                tileKeyFor: _tileKey,
                                onLaunch: _launch,
                              ),
                            ),
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: _tileSpacing,
                                ),
                                child: Divider(
                                  key: desktopApplicationSuggestionsDividerKey,
                                  height: 1,
                                  thickness: 1,
                                  color: context.shellColors.hairlineSoft
                                      .withValues(alpha: 0.55),
                                ),
                              ),
                            ),
                          ],
                          if (allApps.isEmpty)
                            SliverFillRemaining(
                              hasScrollBody: false,
                              child: Center(
                                child: Text(l10n.desktopLoadingApplications),
                              ),
                            )
                          else if (apps.isEmpty)
                            const SliverFillRemaining(
                              hasScrollBody: false,
                              child: _DesktopAppSearchEmptyState(),
                            )
                          else
                            SliverGrid(
                              gridDelegate:
                                  const SliverGridDelegateWithMaxCrossAxisExtent(
                                    maxCrossAxisExtent: _tileExtent,
                                    mainAxisExtent: _tileExtent,
                                    crossAxisSpacing: _tileSpacing,
                                    mainAxisSpacing: _tileSpacing,
                                  ),
                              delegate: SliverChildBuilderDelegate((
                                context,
                                index,
                              ) {
                                final app = apps[index];
                                final targetId = _catalogLauncherTargetId(
                                  app.navigationId,
                                );
                                return KeyedSubtree(
                                  key: ValueKey<String>(
                                    'desktop-app-${app.navigationId}',
                                  ),
                                  child: _DesktopAppTile(
                                    key: _tileKey(targetId),
                                    app: app,
                                    selected: _selectedTargetId == null
                                        ? suggestedApps.isEmpty && index == 0
                                        : targetId == _selectedTargetId,
                                    onTap: () => _launch(app),
                                  ),
                                );
                              }, childCount: apps.length),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
