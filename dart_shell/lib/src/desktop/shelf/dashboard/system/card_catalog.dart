/// Registry of the dashboard system cards: stable tile ids, grid spans, and
/// the default cell anchors used when no saved layout exists.
///
/// Ported from clavis `Modules/SystemCards/SystemCardCatalog.js`: the catalog
/// is the single source of truth for card metadata. The layout algorithms in
/// `card_grid_layout.dart` consume it and never keep a second card list.
///
/// GPU cards are dynamic in denial (one tile per [GpuLoad]), so their tile id
/// embeds the hardware id (`gpu:card0`) — clavis ships a single static `gpu`
/// entry instead.
class SystemCardCatalog {
  const SystemCardCatalog._();

  static const SystemCardCatalog instance = SystemCardCatalog._();

  /// Tile id prefix for the per-GPU sparkline cards.
  static const String gpuPrefix = 'gpu:';

  /// Tile id for one [GpuLoad.id] (`card2`, `nvml0`…), stable across polls.
  static String gpuTileId(String gpuId) => '$gpuPrefix$gpuId';

  static bool isGpuTileId(String id) => id.startsWith(gpuPrefix);

  static const Map<String, ({int columnSpan, int rowSpan})> _staticSpans =
      <String, ({int columnSpan, int rowSpan})>{
        'cpu': (columnSpan: 2, rowSpan: 1),
        'memory': (columnSpan: 1, rowSpan: 1),
        'network': (columnSpan: 2, rowSpan: 1),
        'storage': (columnSpan: 2, rowSpan: 1),
        'battery': (columnSpan: 1, rowSpan: 2),
      };

  // Placement priority when free positions compete. GPU tiles insert after
  // cpu, mirroring the clavis catalog order (cpu, gpu, memoryUsed, network,
  // storage…).
  static const List<String> _tailOrder = <String>[
    'memory',
    'network',
    'storage',
    'battery',
  ];

  /// Whether [id] names a card this catalog can size. Persisted layouts that
  /// reference unknown ids are rejected wholesale (clavis `hydrateSaved`).
  bool hasCard(String id) => isGpuTileId(id) || _staticSpans.containsKey(id);

  int columnSpanFor(String id) =>
      isGpuTileId(id) ? 2 : _staticSpans[id]!.columnSpan;

  int rowSpanFor(String id) => isGpuTileId(id) ? 1 : _staticSpans[id]!.rowSpan;

  /// [activeIds] in placement-priority order: cpu first, every gpu tile next
  /// (input order), then memory/network/storage/battery. Unknown ids are
  /// dropped, matching clavis `idsFor`.
  List<String> orderedIds(List<String> activeIds) {
    final active = activeIds.toSet();
    final ordered = <String>[
      if (active.contains('cpu')) 'cpu',
      for (final id in activeIds)
        if (isGpuTileId(id)) id,
      for (final id in _tailOrder)
        if (active.contains(id)) id,
    ];
    return ordered;
  }

  /// Default anchor in grid cells for [id] given the active id set.
  ///
  /// The default arrangement stacks the full-width sparkline cards on the
  /// left two columns with the narrow cards down the right column:
  /// `cpu+memory` on row 0, one row per gpu, then `network+battery` and
  /// `storage+battery`.
  ({int column, int row}) defaultAnchorFor(String id, List<String> activeIds) {
    final gpuIds = activeIds.where(isGpuTileId).toList(growable: false);
    final gpuRows = gpuIds.length;
    if (isGpuTileId(id)) {
      return (column: 0, row: 1 + gpuIds.indexOf(id));
    }
    return switch (id) {
      'cpu' => (column: 0, row: 0),
      'memory' => (column: 2, row: 0),
      'network' => (column: 0, row: 1 + gpuRows),
      'storage' => (column: 0, row: 2 + gpuRows),
      'battery' => (column: 2, row: 1 + gpuRows),
      _ => (column: 0, row: 0),
    };
  }
}
