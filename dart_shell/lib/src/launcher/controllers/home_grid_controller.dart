import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../local_apps/local_flutter_application.dart';
import '../../settings/settings_controller.dart';
import '../../state/shell_controller.dart';
import '../../state/system_status.dart';
import '../launcher_providers.dart';
import '../models/home_battery_discharge_info.dart';
import '../models/desktop_app.dart';
import '../models/home_drag_session.dart';
import '../models/home_clock_info.dart';
import '../models/home_grid_item.dart';
import '../repositories/desktop_apps_repository.dart';
import '../repositories/home_layout_repository.dart';
import '../services/app_launcher.dart';
import 'home_grid_layout.dart';

const Object _unset = Object();

final desktopAppsRepositoryProvider = Provider<DesktopAppsRepository>((ref) {
  return DesktopAppsRepository(
    paths: ref.watch(runtimePathsProvider),
    iconThemeName: ref.watch(
      shellSettingsProvider.select((s) => s.appearance.iconThemeName),
    ),
  );
});

final homeLayoutRepositoryProvider = Provider<HomeLayoutRepository>((ref) {
  return HomeLayoutRepository(paths: ref.watch(runtimePathsProvider));
});

final appLauncherProvider = Provider<AppLauncher>((ref) {
  return AppLauncher(bridge: ref.watch(denialBridgeProvider));
});

final homeGridControllerProvider =
    AsyncNotifierProvider<HomeGridController, HomeGridState>(
      HomeGridController.new,
    );

final homeDragSessionProvider =
    NotifierProvider<HomeDragSessionController, HomeDragSession?>(
      HomeDragSessionController.new,
    );

final homeClockProvider = Provider<HomeClockInfo>((ref) {
  final locale = HomeClockInfo.localeFromEnvironment(
    ref.watch(runtimePathsProvider).environment,
  );
  return HomeClockInfo.fromShell(
    now: ref.watch(clockProvider).value ?? DateTime.now(),
    locale: locale,
    power: ref.watch(effectivePowerStatusProvider),
  );
}, isAutoDispose: true);

final homeBatteryDischargeProvider = StreamProvider<HomeBatteryDischargeSeries>(
  (ref) {
    final reader = HomeBatteryDischargeTailReader();
    ref.onDispose(() => unawaited(reader.dispose()));
    return reader.snapshots;
  },
  isAutoDispose: true,
);

class HomeDragSessionController extends Notifier<HomeDragSession?> {
  @override
  HomeDragSession? build() => null;

  void setSession(HomeDragSession? session) {
    state = session;
  }

  void clear() {
    state = null;
  }
}

class HomeGridState {
  HomeGridState({
    required List<HomeGridItem?> slots,
    this.page = 0,
    this.draggingSourceIndex,
  }) : slots = List.unmodifiable(slots);

  HomeGridState._({
    required this.slots,
    required this.page,
    required this.draggingSourceIndex,
  });

  final List<HomeGridItem?> slots;
  final int page;
  final int? draggingSourceIndex;

  HomeGridState copyWith({
    List<HomeGridItem?>? slots,
    int? page,
    Object? draggingSourceIndex = _unset,
  }) {
    return HomeGridState._(
      slots: slots == null ? this.slots : List.unmodifiable(slots),
      page: page ?? this.page,
      draggingSourceIndex: identical(draggingSourceIndex, _unset)
          ? this.draggingSourceIndex
          : draggingSourceIndex as int?,
    );
  }
}

class HomeGridController extends AsyncNotifier<HomeGridState> {
  static const Duration _periodicRefreshInterval = Duration(minutes: 5);
  static const Duration _filesystemRefreshDebounce = Duration(
    milliseconds: 200,
  );

  Timer? _desktopRefreshTimer;
  Timer? _filesystemRefreshTimer;
  DesktopAppsWatcher? _desktopAppsWatcher;
  String? _desktopAppsFingerprint;
  bool _desktopRefreshInFlight = false;
  bool _desktopRefreshTriggersStarted = false;
  bool _desktopAppsDirty = false;
  bool _launcherActive = true;
  int _buildGeneration = 0;

  @override
  Future<HomeGridState> build() async {
    final generation = ++_buildGeneration;
    // The previous generation's onDispose has already released these, but a
    // rebuild reuses this notifier instance — cancel defensively like the
    // sibling controllers so a skipped disposal can never leak a timer or
    // watch into the new generation.
    _desktopRefreshTimer?.cancel();
    _desktopRefreshTimer = null;
    _filesystemRefreshTimer?.cancel();
    _filesystemRefreshTimer = null;
    unawaited(_desktopAppsWatcher?.dispose());
    _desktopAppsWatcher = null;
    _desktopAppsFingerprint = null;
    _desktopRefreshInFlight = false;
    _desktopRefreshTriggersStarted = false;
    _desktopAppsDirty = false;
    // _launcherActive intentionally keeps its last known value across
    // dependency-driven rebuilds: Riverpod reuses this notifier instance and
    // HomeSurface only re-syncs on actual visibility changes, so resetting it
    // here would silently revive the periodic scan while the launcher is
    // still hidden.
    ref.onDispose(() {
      if (_buildGeneration == generation) {
        _buildGeneration++;
      }
      _desktopRefreshTimer?.cancel();
      _desktopRefreshTimer = null;
      _filesystemRefreshTimer?.cancel();
      _filesystemRefreshTimer = null;
      unawaited(_desktopAppsWatcher?.dispose());
      _desktopAppsWatcher = null;
      _desktopRefreshTriggersStarted = false;
    });
    final appsRepository = ref.watch(desktopAppsRepositoryProvider);
    final layoutRepository = ref.watch(homeLayoutRepositoryProvider);
    final localApps = ref
        .watch(localFlutterApplicationRegistryProvider)
        .applications
        .toList(growable: false);
    // On seamless rebuilds state still holds the previous AsyncData, so a
    // refreshDesktopApps call would otherwise slip past its guards and race
    // this isolate load. Hold the in-flight flag for the whole load; skipped
    // refreshes lose nothing because this result writes the newest data.
    _desktopRefreshInFlight = true;
    try {
      final loadResult = await _loadApplications(
        appsRepository,
        reason: 'initial',
      );
      // The fingerprint starts null, so the initial scan always parses.
      final apps = loadResult.apps!;
      final savedLayout = await layoutRepository.readSavedLayout();
      final slots = HomeGridLayout.initialSlotsForApps(
        apps,
        localApps,
        savedLayout,
      );
      if (!_isBuildActive(generation)) {
        return HomeGridState(slots: slots);
      }
      _desktopAppsFingerprint = loadResult.fingerprint;
      if (_savedLayoutNeedsRefresh(apps, localApps, savedLayout, slots)) {
        unawaited(layoutRepository.saveLayout(slots));
      }
      unawaited(_startDesktopRefreshTriggers(generation, appsRepository));
      return HomeGridState(slots: slots);
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(error, stackTrace);
    } finally {
      if (_isBuildActive(generation)) {
        _desktopRefreshInFlight = false;
        if (_desktopAppsDirty && _launcherActive) {
          _scheduleFilesystemRefresh();
        }
      }
    }
  }

  Future<void> refreshDesktopApps({String reason = 'manual'}) async {
    if (state.asData?.value == null) {
      return;
    }

    if (!_launcherActive && reason != 'manual') {
      return;
    }

    if (_desktopRefreshInFlight) {
      // Periodic ticks are droppable — the in-flight load supersedes them.
      // Other triggers (activation, manual, filesystem) must not be lost:
      // mark the set dirty so the in-flight side schedules a follow-up once
      // it finishes instead of silently dropping the refresh request.
      if (reason != 'timer') {
        _desktopAppsDirty = true;
      }
      return;
    }

    final generation = _buildGeneration;
    _desktopAppsDirty = false;
    _desktopRefreshInFlight = true;
    try {
      final loadResult = await _loadApplications(
        ref.read(desktopAppsRepositoryProvider),
        reason: reason,
      );
      if (!_isBuildActive(generation)) {
        return;
      }
      if (!_launcherActive && reason != 'manual') {
        // The launcher hid while the scan was in flight: drop the result
        // rather than write state nobody can see. The immediate refresh on
        // the next activation picks the change back up.
        return;
      }
      final apps = loadResult.apps;
      if (apps == null) {
        // The .desktop fingerprint still matches; the parsed list and the
        // layout derived from it remain current.
        return;
      }
      _desktopAppsFingerprint = loadResult.fingerprint;
      final current = state.asData?.value;
      if (current == null) {
        return;
      }

      final currentApps = _appsByGridId(current.slots);
      final refreshedApps = _appsByGridId([
        for (final app in apps) HomeGridItem.app(app),
      ]);

      final addedIds = refreshedApps.keys
          .where((id) => !currentApps.containsKey(id))
          .toList(growable: false);
      final removedIds = currentApps.keys
          .where((id) => !refreshedApps.containsKey(id))
          .toList(growable: false);
      final updatedIds = refreshedApps.keys
          .where(
            (id) =>
                currentApps.containsKey(id) &&
                !_sameDesktopApp(currentApps[id]!, refreshedApps[id]!),
          )
          .toList(growable: false);

      if (addedIds.isEmpty && removedIds.isEmpty && updatedIds.isEmpty) {
        return;
      }

      final localApps = ref
          .read(localFlutterApplicationRegistryProvider)
          .applications;
      final slots = HomeGridLayout.refreshSlotsForApps(
        current.slots,
        apps,
        localApps,
      );
      state = AsyncData(current.copyWith(slots: slots));
      unawaited(ref.read(homeLayoutRepositoryProvider).saveLayout(slots));
    } on Object catch (error) {
      // A failed scan keeps the previous grid and fingerprint. One debounced
      // retry is queued via the dirty flag unless this was already the
      // filesystem follow-up, in which case the next watcher event or
      // periodic tick retries — a persistent failure must not hot-loop.
      debugPrint('Desktop applications refresh failed: $error');
      if (reason != 'filesystem') {
        _desktopAppsDirty = true;
      }
    } finally {
      if (_isBuildActive(generation)) {
        _desktopRefreshInFlight = false;
        if (_desktopAppsDirty && _launcherActive) {
          _scheduleFilesystemRefresh();
        }
      }
    }
  }

  void setLauncherActive(bool active) {
    if (_launcherActive == active) {
      return;
    }

    _launcherActive = active;
    if (!active) {
      // While the launcher is hidden the periodic scan stops entirely; the
      // watcher keeps marking _desktopAppsDirty so the next activation knows
      // whether anything changed underneath.
      _desktopRefreshTimer?.cancel();
      _desktopRefreshTimer = null;
      _filesystemRefreshTimer?.cancel();
      _filesystemRefreshTimer = null;
      return;
    }
    _restartDesktopRefreshTimer();
    // Becoming visible refreshes immediately: the fingerprint check keeps an
    // unchanged scan cheap and the in-flight gate deduplicates rapid
    // hide/show toggles. A pending filesystem debounce is superseded by it.
    _filesystemRefreshTimer?.cancel();
    _filesystemRefreshTimer = null;
    unawaited(refreshDesktopApps(reason: 'launcher-visible'));
  }

  Future<void> _startDesktopRefreshTriggers(
    int generation,
    DesktopAppsRepository repository,
  ) async {
    try {
      // The generation check guards against a stale call: an invalidated
      // build must never mark triggers started or a newer build would
      // return early and lose its timer and watcher.
      if (_desktopRefreshTriggersStarted || !_isBuildActive(generation)) {
        return;
      }
      DesktopAppsWatcher? watcher;
      try {
        watcher = await repository.watchApplications(
          onChanged: () {
            if (!_isBuildActive(generation)) {
              return;
            }
            _desktopAppsDirty = true;
            if (_launcherActive) {
              _scheduleFilesystemRefresh();
            }
          },
        );
      } on Object {
        // Filesystem notifications are best effort. The periodic timer below
        // is the fallback when the platform cannot establish a watcher.
      }
      if (!_isBuildActive(generation)) {
        // A newer build took over during the await: dispose only the watcher
        // this call obtained and leave the flag and timers to that build.
        await watcher?.dispose();
        return;
      }
      // Commit flag, watcher and periodic timer only after the generation is
      // confirmed, so a superseded call can never half-establish state.
      _desktopAppsWatcher = watcher;
      _desktopRefreshTriggersStarted = true;
      _restartDesktopRefreshTimer();
    } on Object {
      // Trigger setup is best effort; a later activation or rebuild retries.
    }
  }

  void _restartDesktopRefreshTimer() {
    _desktopRefreshTimer?.cancel();
    _desktopRefreshTimer = null;
    if (!_launcherActive || !_desktopRefreshTriggersStarted) {
      return;
    }
    final generation = _buildGeneration;
    _desktopRefreshTimer = Timer.periodic(_periodicRefreshInterval, (_) {
      if (!_isBuildActive(generation) || !_launcherActive) {
        return;
      }
      unawaited(refreshDesktopApps(reason: 'timer'));
    });
  }

  void _scheduleFilesystemRefresh() {
    _filesystemRefreshTimer?.cancel();
    _filesystemRefreshTimer = Timer(_filesystemRefreshDebounce, () {
      _filesystemRefreshTimer = null;
      unawaited(refreshDesktopApps(reason: 'filesystem'));
    });
  }

  bool _isBuildActive(int generation) =>
      ref.mounted && generation == _buildGeneration;

  Future<DesktopAppsLoadResult> _loadApplications(
    DesktopAppsRepository repository, {
    required String reason,
  }) {
    final fingerprint = _desktopAppsFingerprint;
    return Isolate.run(
      () => repository.loadApplicationsIfChanged(fingerprint),
      debugName: 'denia-launcher-desktop-$reason',
    );
  }

  void setPage(int page) {
    final current = state.asData?.value;
    if (current == null || current.page == page) {
      return;
    }

    state = AsyncData(current.copyWith(page: page));
  }

  void setDraggingSourceIndex(int? index) {
    final current = state.asData?.value;
    if (current == null || current.draggingSourceIndex == index) {
      return;
    }

    state = AsyncData(current.copyWith(draggingSourceIndex: index));
  }

  bool canMoveSlot(int fromIndex, int toIndex, int pageSize) {
    final current = state.asData?.value;
    if (current == null) {
      return false;
    }

    return HomeGridLayout.canMoveSlot(
      current.slots,
      fromIndex,
      toIndex,
      pageSize,
    );
  }

  int? moveSlot(int fromIndex, int toIndex, int pageSize) {
    final current = state.asData?.value;
    if (current == null) {
      return null;
    }

    final result = HomeGridLayout.moveSlot(
      current.slots,
      fromIndex,
      toIndex,
      pageSize,
    );
    if (result == null) {
      return null;
    }

    state = AsyncData(
      current.copyWith(
        slots: result.slots,
        draggingSourceIndex: result.movedToIndex,
      ),
    );
    unawaited(ref.read(homeLayoutRepositoryProvider).saveLayout(result.slots));
    return result.movedToIndex;
  }

  bool canResizeSlot(int index, int colSpan, int rowSpan, int pageSize) {
    final current = state.asData?.value;
    if (current == null) {
      return false;
    }

    return HomeGridLayout.canResizeSlot(
      current.slots,
      index,
      colSpan,
      rowSpan,
      pageSize,
    );
  }

  void resizeSlot(int index, int colSpan, int rowSpan, int pageSize) {
    final current = state.asData?.value;
    if (current == null) {
      return;
    }

    final result = HomeGridLayout.resizeSlot(
      current.slots,
      index,
      colSpan,
      rowSpan,
      pageSize,
    );
    if (result == null) {
      return;
    }

    state = AsyncData(current.copyWith(slots: result.slots));
    unawaited(ref.read(homeLayoutRepositoryProvider).saveLayout(result.slots));
  }
}

Map<String, DesktopApp> _appsByGridId(List<HomeGridItem?> slots) {
  final appsById = <String, DesktopApp>{};
  for (final item in slots) {
    final app = item?.app;
    if (app == null) {
      continue;
    }
    appsById[item!.id] = app;
  }
  return appsById;
}

bool _sameDesktopApp(DesktopApp a, DesktopApp b) {
  if (a.id != b.id ||
      a.name != b.name ||
      a.exec != b.exec ||
      a.desktopPath != b.desktopPath ||
      a.icon != b.icon ||
      a.iconPath != b.iconPath ||
      a.startupWmClass != b.startupWmClass ||
      a.categories.length != b.categories.length) {
    return false;
  }

  for (var index = 0; index < a.categories.length; index += 1) {
    if (a.categories[index] != b.categories[index]) {
      return false;
    }
  }
  return true;
}

bool _savedLayoutNeedsRefresh(
  List<DesktopApp> apps,
  Iterable<LocalFlutterApplication> localApps,
  List<HomeLayoutSlot?>? savedLayout,
  List<HomeGridItem?> slots,
) {
  if (savedLayout == null || savedLayout.length != slots.length) {
    return true;
  }

  final savedIds = <String>{for (final slot in savedLayout) ?slot?.id};
  if (savedIds.contains('widget:frame-time')) {
    return true;
  }

  final currentAppIds = <String>{
    for (final app in apps) 'app:${app.id}',
    for (final app in localApps) 'local:${app.id}',
  };
  if (!savedIds.containsAll(currentAppIds)) {
    return true;
  }

  return savedIds
      .where((id) => id.startsWith('app:') || id.startsWith('local:'))
      .any((id) => !currentAppIds.contains(id));
}
