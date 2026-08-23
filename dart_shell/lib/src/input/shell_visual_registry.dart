import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

@immutable
class ShellVisualSurface {
  const ShellVisualSurface({
    required this.id,
    required this.debugLabel,
    required this.bounds,
    required this.revision,
    required this.requiresClientSampling,
  });

  final int id;
  final String debugLabel;
  final Rect bounds;
  final int revision;
  final bool requiresClientSampling;

  @override
  bool operator ==(Object other) =>
      other is ShellVisualSurface &&
      other.id == id &&
      other.debugLabel == debugLabel &&
      other.bounds == bounds &&
      other.revision == revision &&
      other.requiresClientSampling == requiresClientSampling;

  @override
  int get hashCode =>
      Object.hash(id, debugLabel, bounds, revision, requiresClientSampling);
}

@immutable
class ShellVisualSnapshot {
  ShellVisualSnapshot(Map<int, ShellVisualSurface> surfaces)
    : surfaces = Map<int, ShellVisualSurface>.unmodifiable(surfaces);

  const ShellVisualSnapshot.empty()
    : surfaces = const <int, ShellVisualSurface>{};

  final Map<int, ShellVisualSurface> surfaces;

  Iterable<ShellVisualSurface> get orderedSurfaces {
    final result = surfaces.values.toList(growable: false)
      ..sort((left, right) => left.id.compareTo(right.id));
    return result;
  }

  bool get requiresClientSampling =>
      surfaces.values.any((surface) => surface.requiresClientSampling);

  int get revision => Object.hashAll(
    orderedSurfaces.map(
      (surface) => Object.hash(
        surface.id,
        surface.bounds,
        surface.revision,
        surface.requiresClientSampling,
      ),
    ),
  );
}

final shellVisualRegistryProvider =
    NotifierProvider<ShellVisualRegistry, ShellVisualSnapshot>(
      ShellVisualRegistry.new,
    );

class ShellVisualRegistry extends Notifier<ShellVisualSnapshot> {
  int _nextSurfaceId = 1;

  @override
  ShellVisualSnapshot build() => const ShellVisualSnapshot.empty();

  int reserveSurfaceId() => _nextSurfaceId++;

  void upsert(ShellVisualSurface surface) {
    if (state.surfaces[surface.id] == surface) {
      return;
    }
    state = ShellVisualSnapshot(
      Map<int, ShellVisualSurface>.of(state.surfaces)..[surface.id] = surface,
    );
  }

  void remove(int id) {
    if (!state.surfaces.containsKey(id)) {
      return;
    }
    state = ShellVisualSnapshot(
      Map<int, ShellVisualSurface>.of(state.surfaces)..remove(id),
    );
  }

  void removeIfMounted(int id) {
    if (ref.mounted) {
      remove(id);
    }
  }
}

class ShellVisualRegion extends ConsumerStatefulWidget {
  const ShellVisualRegion({
    required this.debugLabel,
    required this.child,
    required this.revision,
    super.key,
    this.active = true,
    this.requiresClientSampling = false,
  });

  final String debugLabel;
  final Widget child;
  final int revision;
  final bool active;
  final bool requiresClientSampling;

  @override
  ConsumerState<ShellVisualRegion> createState() => _ShellVisualRegionState();
}

class _ShellVisualRegionState extends ConsumerState<ShellVisualRegion> {
  late final ShellVisualRegistry _registry;
  late final int _surfaceId;
  Rect? _bounds;
  Rect? _pendingBounds;
  bool _scheduled = false;
  int _paintRevision = 0;

  @override
  void initState() {
    super.initState();
    _registry = ref.read(shellVisualRegistryProvider.notifier);
    _surfaceId = _registry.reserveSurfaceId();
    _schedulePublish();
  }

  @override
  void didUpdateWidget(covariant ShellVisualRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active ||
        oldWidget.debugLabel != widget.debugLabel ||
        oldWidget.revision != widget.revision ||
        oldWidget.requiresClientSampling != widget.requiresClientSampling) {
      _schedulePublish();
    }
  }

  void _handleBounds(Rect bounds) {
    if (_pendingBounds == bounds || _bounds == bounds) {
      return;
    }
    _paintRevision += 1;
    _pendingBounds = bounds;
    _schedulePublish();
  }

  void _schedulePublish() {
    if (_scheduled) {
      return;
    }
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) {
        return;
      }
      if (!widget.active) {
        _registry.remove(_surfaceId);
        return;
      }
      if (_pendingBounds case final bounds?) {
        _bounds = bounds;
        _pendingBounds = null;
      }
      final bounds = _bounds;
      if (bounds == null || bounds.isEmpty) {
        return;
      }
      _registry.upsert(
        ShellVisualSurface(
          id: _surfaceId,
          debugLabel: widget.debugLabel,
          bounds: bounds,
          revision: Object.hash(widget.revision, _paintRevision),
          requiresClientSampling: widget.requiresClientSampling,
        ),
      );
    });
  }

  @override
  void dispose() {
    final surfaceId = _surfaceId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _registry.removeIfMounted(surfaceId);
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _ShellVisualBoundsReporter(onBounds: _handleBounds, child: widget.child);
}

class _ShellVisualBoundsReporter extends SingleChildRenderObjectWidget {
  const _ShellVisualBoundsReporter({
    required this.onBounds,
    required super.child,
  });

  final ValueChanged<Rect> onBounds;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderShellVisualBoundsReporter(onBounds);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderShellVisualBoundsReporter renderObject,
  ) {
    renderObject.onBounds = onBounds;
  }
}

class _RenderShellVisualBoundsReporter extends RenderProxyBox {
  _RenderShellVisualBoundsReporter(this.onBounds);

  ValueChanged<Rect> onBounds;
  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    if (!hasSize || size.isEmpty) {
      return;
    }
    final bounds = MatrixUtils.transformRect(
      getTransformTo(null),
      Offset.zero & size,
    );
    onBounds(bounds);
  }
}
