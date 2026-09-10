import 'package:flutter/material.dart';

import '../../localization/denial_localizations.dart';
import '../../theme/motion.dart';
import '../../theme/shell_theme.dart';
import '../../theme/tokens.dart';
import 'settings_navigation.dart';
import 'settings_search_index.dart';

/// Identifies the search result region (list or empty state) for tests.
const settingsSearchResultsKey = ValueKey<String>('settings-search-results');

/// Identifies the "no matching settings" empty state.
const settingsSearchEmptyKey = ValueKey<String>('settings-search-empty');

/// Grouped search results shown in place of the navigation list while the
/// search is active (§3.2).
///
/// Result rows reuse [SettingsNavItem] so the search matches the navigation
/// exactly — same 64dp card, 40dp hue circle, and selected accent fill — with
/// the group name carried as the supporting line. [highlighted] drives both the
/// visual highlight and the `selected` semantics; the highlighted row scrolls
/// itself into view when it changes.
class SettingsSearchResults extends StatelessWidget {
  const SettingsSearchResults({
    required this.groups,
    required this.highlighted,
    required this.onSelected,
    super.key,
  });

  final List<SettingsSearchGroup> groups;
  final SettingsPageId? highlighted;
  final ValueChanged<SettingsPageId> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Semantics(
      key: settingsSearchResultsKey,
      container: true,
      explicitChildNodes: true,
      label: l10n.settingsSearchResults,
      child: groups.isEmpty
          ? Padding(
              key: settingsSearchEmptyKey,
              padding: const EdgeInsets.all(16),
              child: Center(
                child: Text(
                  l10n.settingsSearchNoResults,
                  textAlign: TextAlign.center,
                  style: ShellText.settingsRowSupport.copyWith(
                    color: context.shellColors.textSecondary,
                  ),
                ),
              ),
            )
          : ListView(
              padding: EdgeInsets.zero,
              children: _buildChildren(context),
            ),
    );
  }

  List<Widget> _buildChildren(BuildContext context) {
    final children = <Widget>[];
    for (var groupIndex = 0; groupIndex < groups.length; groupIndex += 1) {
      if (groupIndex > 0) {
        children.add(const SizedBox(height: settingsNavGroupSpacing));
      }
      children.add(_SearchGroupHeader(group: groups[groupIndex].group));
      children.add(const SizedBox(height: settingsNavGroupHeaderGap));
      final pages = groups[groupIndex].pages;
      for (var index = 0; index < pages.length; index += 1) {
        if (index > 0) {
          children.add(const SizedBox(height: settingsNavItemGap));
        }
        final page = pages[index];
        children.add(
          _SearchResultItem(
            key: ValueKey<SettingsPageId>(page),
            page: page,
            support: groups[groupIndex].group.label(context),
            selected: page == highlighted,
            onPressed: () => onSelected(page),
          ),
        );
      }
    }
    return children;
  }
}

class _SearchGroupHeader extends StatelessWidget {
  const _SearchGroupHeader({required this.group});

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

/// A navigation-style result card that keeps itself visible while highlighted.
class _SearchResultItem extends StatefulWidget {
  const _SearchResultItem({
    required this.page,
    required this.support,
    required this.selected,
    required this.onPressed,
    super.key,
  });

  final SettingsPageId page;
  final String support;
  final bool selected;
  final VoidCallback onPressed;

  @override
  State<_SearchResultItem> createState() => _SearchResultItemState();
}

class _SearchResultItemState extends State<_SearchResultItem> {
  @override
  void didUpdateWidget(covariant _SearchResultItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected || !widget.selected) {
      return;
    }
    // Keyboard navigation must bring the newly highlighted row into view.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final duration = MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : Motion.tile;
      Scrollable.ensureVisible(context, alignment: 0.5, duration: duration);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SettingsNavItem(
      page: widget.page,
      selected: widget.selected,
      support: widget.support,
      onPressed: widget.onPressed,
    );
  }
}
