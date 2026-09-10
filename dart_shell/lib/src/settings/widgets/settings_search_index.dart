import 'package:flutter/foundation.dart';

import 'settings_navigation.dart';

/// Rank of a destination against a query (`02-VISUAL-SPEC` has no values for
/// search; the ordering is fixed by the S07 card §3.1).
///
/// Declared in descending priority so [SettingsSearchMatchTier.values] is the
/// sort order.
enum SettingsSearchMatchTier {
  /// The destination title starts with the query.
  titlePrefix,

  /// The destination title contains the query.
  titleContains,

  /// One of the destination's bilingual synonyms contains the query.
  keyword,
}

/// One result group of the search view, in first-appearance order (§3.2).
@immutable
class SettingsSearchGroup {
  const SettingsSearchGroup({required this.group, required this.pages});

  final SettingsNavGroup group;
  final List<SettingsPageId> pages;
}

/// Central, purely static index over the eighteen Settings destinations (§3.1).
///
/// The index stores only synonyms; destination labels and group membership are
/// read from the navigation's single source of truth
/// ([settingsNavigationGroups]) so the two can never drift, and no setting
/// value or dynamic content is indexed.
@immutable
class SettingsSearchIndexData {
  const SettingsSearchIndexData(this.keywords);

  /// Synonyms per destination. Each page carries at least four entries, split
  /// across zh and en, so a query in either language resolves it.
  final Map<SettingsPageId, List<String>> keywords;

  /// The shipped index. Every [SettingsPageId] must appear here; the coverage
  /// is asserted by `settings_search_test.dart`.
  static const SettingsSearchIndexData standard = SettingsSearchIndexData(
    <SettingsPageId, List<String>>{
      SettingsPageId.appearance: <String>[
        '外观',
        '主题',
        '配色',
        '颜色',
        'appearance',
        'theme',
        'color',
        'dark',
        'light',
      ],
      SettingsPageId.language: <String>[
        '语言',
        '区域',
        '语言设置',
        'language',
        'locale',
        'region',
      ],
      SettingsPageId.keyboard: <String>[
        '键盘',
        '按键',
        '重复延迟',
        'keyboard',
        'key',
        'repeat',
        'layout',
      ],
      SettingsPageId.touchpad: <String>[
        '触控板',
        '触摸板',
        '手势',
        '滚动',
        'touchpad',
        'trackpad',
        'gesture',
        'scroll',
      ],
      SettingsPageId.shortcuts: <String>[
        '快捷键',
        '快捷方式',
        '键位',
        'shortcuts',
        'shortcut',
        'hotkey',
        'keybinding',
      ],
      SettingsPageId.environment: <String>[
        '环境变量',
        '环境',
        '变量',
        '覆盖',
        'environment',
        'env',
        'variable',
        'override',
      ],
      SettingsPageId.animations: <String>[
        '动画',
        '动效',
        '过渡',
        '时长',
        'animation',
        'animations',
        'motion',
        'transition',
      ],
      SettingsPageId.layout: <String>[
        '布局',
        '系统栏',
        '工作区',
        '桌面',
        '最大化',
        'shelf',
        'layout',
        'desktop',
        'workspace',
        'maximize',
      ],
      SettingsPageId.overlays: <String>[
        '浮层',
        '覆盖层',
        '面板',
        '启动器',
        '仪表板',
        'overlay',
        'overlays',
        'panel',
        'launcher',
        'dashboard',
      ],
      SettingsPageId.lockScreen: <String>[
        '锁屏',
        '密码',
        '超时',
        '锁定',
        'lock',
        'lock screen',
        'password',
        'timeout',
      ],
      SettingsPageId.audio: <String>[
        '音频',
        '声音',
        '音量',
        '输出',
        'audio',
        'sound',
        'volume',
        'output',
      ],
      SettingsPageId.displays: <String>[
        '显示器',
        '分辨率',
        '刷新率',
        '缩放',
        '屏幕',
        'display',
        'resolution',
        'scale',
        'monitor',
        'refresh rate',
      ],
      SettingsPageId.network: <String>[
        '网络',
        '无线',
        '以太网',
        'wifi',
        'network',
        'wireless',
        'ethernet',
        'wi-fi',
      ],
      SettingsPageId.bluetooth: <String>[
        '蓝牙',
        '配对',
        '设备',
        'bluetooth',
        'pair',
        'device',
      ],
      SettingsPageId.weather: <String>[
        '天气',
        '位置',
        '温度',
        '城市',
        'weather',
        'location',
        'temperature',
        'city',
      ],
      SettingsPageId.power: <String>[
        '电源',
        '睡眠',
        '待机',
        '空闲',
        'power',
        'sleep',
        'suspend',
        'idle',
        'battery',
      ],
      SettingsPageId.developer: <String>[
        '开发者',
        '调试',
        '日志',
        '开发',
        'developer',
        'debug',
        'log',
        'development',
      ],
      SettingsPageId.about: <String>[
        '关于',
        '版本',
        '信息',
        '系统',
        'about',
        'version',
        'info',
        'system',
      ],
    },
  );

  /// Synonyms for [page]; empty when the page is not indexed.
  List<String> keywordsFor(SettingsPageId page) =>
      keywords[page] ?? const <String>[];

  /// Navigation group that owns [page], or null when [page] is ungrouped.
  SettingsNavGroup? groupOf(SettingsPageId page) {
    for (final entry in settingsNavigationGroups.entries) {
      if (entry.value.contains(page)) {
        return entry.key;
      }
    }
    return null;
  }
}

/// Matches [query] against the destination titles and [data] (§3.1).
///
/// Normalisation is `trim` + `toLowerCase`; Chinese matches by substring.
/// Results are ordered by [SettingsSearchMatchTier] and keep navigation order
/// within a tier. An empty or whitespace-only query returns no results.
List<SettingsPageId> search(
  String query,
  SettingsSearchIndexData data,
  String Function(SettingsPageId) labelOf,
) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) {
    return const <SettingsPageId>[];
  }
  final buckets = <SettingsSearchMatchTier, List<SettingsPageId>>{
    for (final tier in SettingsSearchMatchTier.values)
      tier: <SettingsPageId>[],
  };
  // Navigation order is the tie-breaker, so iterate the groups in render order.
  for (final pages in settingsNavigationGroups.values) {
    for (final page in pages) {
      final tier = _tierFor(page, needle, data, labelOf);
      if (tier != null) {
        buckets[tier]!.add(page);
      }
    }
  }
  return <SettingsPageId>[
    for (final tier in SettingsSearchMatchTier.values) ...buckets[tier]!,
  ];
}

/// Buckets a ranked result list into sections for display (§3.2).
///
/// Sections are ordered by the rank of their best member (the first
/// appearance in [ranked]); within a section the ranked order is preserved.
List<SettingsSearchGroup> groupSearchResults(
  List<SettingsPageId> ranked,
  SettingsSearchIndexData data,
) {
  final buckets = <SettingsNavGroup, List<SettingsPageId>>{};
  for (final page in ranked) {
    final group = data.groupOf(page);
    if (group == null) {
      continue;
    }
    (buckets[group] ??= <SettingsPageId>[]).add(page);
  }
  return <SettingsSearchGroup>[
    for (final entry in buckets.entries)
      SettingsSearchGroup(group: entry.key, pages: entry.value),
  ];
}

SettingsSearchMatchTier? _tierFor(
  SettingsPageId page,
  String needle,
  SettingsSearchIndexData data,
  String Function(SettingsPageId) labelOf,
) {
  final label = labelOf(page).toLowerCase();
  if (label.startsWith(needle)) {
    return SettingsSearchMatchTier.titlePrefix;
  }
  if (label.contains(needle)) {
    return SettingsSearchMatchTier.titleContains;
  }
  for (final keyword in data.keywordsFor(page)) {
    if (keyword.toLowerCase().contains(needle)) {
      return SettingsSearchMatchTier.keyword;
    }
  }
  return null;
}
