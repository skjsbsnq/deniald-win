import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../launcher/models/desktop_app.dart';
import '../local_apps/local_flutter_application.dart';
import '../localization/denial_localizations.dart';
import '../theme/motion.dart';
import '../theme/tokens.dart';
import '../wallpaper/state/wallpaper_accent.dart';
import '../widgets/app_icon.dart';
import '../widgets/shell_cursor.dart';

/// One launchable row in the start menu.
///
/// The desktop shell has two unrelated notions of "application" — freedesktop
/// `.desktop` entries and Flutter applications hosted inside the shell — and
/// neither can be turned into the other. This unifies only what the list needs
/// (a name to sort by, an icon, and a way to launch) so the list never has to
/// branch on which kind it is holding.
@immutable
class DesktopStartMenuEntry {
  const DesktopStartMenuEntry._({
    required this.id,
    required this.name,
    required this.categories,
    required this.iconPath,
    required this.icon,
    required this.desktopApp,
    required this.localApp,
  });

  factory DesktopStartMenuEntry.desktop(DesktopApp app) {
    return DesktopStartMenuEntry._(
      id: app.id,
      name: app.name,
      categories: app.categories,
      iconPath: app.iconPath,
      icon: null,
      desktopApp: app,
      localApp: null,
    );
  }

  factory DesktopStartMenuEntry.local(
    LocalFlutterApplication app,
    BuildContext context,
  ) {
    return DesktopStartMenuEntry._(
      id: app.id,
      name: app.titleFor(context),
      categories: app.categoriesFor(context),
      iconPath: null,
      icon: app.icon,
      desktopApp: null,
      localApp: app,
    );
  }

  final String id;
  final String name;
  final List<String> categories;
  final String? iconPath;
  final IconData? icon;
  final DesktopApp? desktopApp;
  final LocalFlutterApplication? localApp;
}

/// A letter heading plus the entries filed under it.
@immutable
class DesktopStartMenuAppGroup {
  const DesktopStartMenuAppGroup({required this.key, required this.entries});

  /// `A`–`Z`, or [startMenuOtherGroupKey] for everything else.
  final String key;
  final List<DesktopStartMenuEntry> entries;
}

/// Heading for names that do not begin with a Latin letter.
///
/// Windows 10 files digits and symbols under a single heading ahead of `A`; the
/// same bucket also absorbs CJK names here, because grouping those by reading
/// needs a collation table this shell does not have.
const String startMenuOtherGroupKey = '#';

/// Latin letters carrying diacritics, paired positionally with [_foldedLatin].
///
/// Grouping is a display concern, so `Épiphanie` belongs under `E` rather than
/// in the catch-all bucket. Dart has no accent-folding collator and `intl` does
/// not ship one, so the mapping is spelled out. It deliberately stops at
/// Latin-1 Supplement and Latin Extended-A: beyond that a name falls into the
/// catch-all group, which is visibly wrong rather than quietly misfiled.
const String _accentedLatin =
    'ÀÁÂÃÄÅĀĂĄÇĆĈĊČÈÉÊËĒĔĖĘĚÌÍÎÏĨĪĬĮİÑŃŅŇÒÓÔÕÖØŌŎŐÙÚÛÜŨŪŬŮŰŲÝŶŸŚŜŞŠŹŻŽĎĐĜĞĠĢĤĦĴĶĹĻĽŁŔŖŘŢŤŦŴ';
const String _foldedLatin =
    'AAAAAAAAACCCCCEEEEEEEEEIIIIIIIIINNNNOOOOOOOOOUUUUUUUUUUYYYSSSSZZZDDGGGGHHJKLLLLRRRTTTW';

/// Returns the heading [name] belongs under.
String startMenuGroupKey(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) {
    return startMenuOtherGroupKey;
  }
  final first = String.fromCharCode(trimmed.runes.first).toUpperCase();
  final accented = _accentedLatin.indexOf(first);
  final folded = accented < 0 ? first : _foldedLatin[accented];
  if (folded.length != 1) {
    return startMenuOtherGroupKey;
  }
  const int upperA = 0x41;
  const int upperZ = 0x5a;
  final unit = folded.codeUnitAt(0);
  if (unit < upperA || unit > upperZ) {
    return startMenuOtherGroupKey;
  }
  return folded;
}

/// Files [entries] under letter headings, the catch-all first and `A`–`Z` after.
///
/// Callers pass an already name-sorted list and this preserves that order
/// inside each group, so the two orderings can never disagree.
List<DesktopStartMenuAppGroup> groupStartMenuEntries(
  List<DesktopStartMenuEntry> entries,
) {
  final buckets = <String, List<DesktopStartMenuEntry>>{};
  for (final entry in entries) {
    buckets
        .putIfAbsent(
          startMenuGroupKey(entry.name),
          () => <DesktopStartMenuEntry>[],
        )
        .add(entry);
  }
  final keys = buckets.keys.toList()
    ..sort((a, b) {
      if (a == b) {
        return 0;
      }
      if (a == startMenuOtherGroupKey) {
        return -1;
      }
      if (b == startMenuOtherGroupKey) {
        return 1;
      }
      return a.compareTo(b);
    });
  return <DesktopStartMenuAppGroup>[
    for (final key in keys)
      DesktopStartMenuAppGroup(key: key, entries: buckets[key]!),
  ];
}

/// The all-apps column: letter-grouped when idle, flat while searching.
///
/// Headings scroll away instead of pinning, which is what Windows 10 itself
/// does — pinning would need a `SliverPersistentHeader` per group and buys
/// nothing the reference screenshot shows.
class DesktopStartMenuAppList extends StatelessWidget {
  const DesktopStartMenuAppList({
    super.key,
    required this.entries,
    required this.searching,
    required this.accent,
    required this.onLaunch,
    required this.onShowMenu,
  });

  final List<DesktopStartMenuEntry> entries;
  final bool searching;
  final WallpaperAccent accent;
  final ValueChanged<DesktopStartMenuEntry> onLaunch;

  /// Right-clicking a row offers to pin it, which is the only way a tile ever
  /// reaches the board.
  final void Function(DesktopStartMenuEntry entry, Offset position) onShowMenu;

  @override
  Widget build(BuildContext context) {
    final rows = <_AppListRow>[];
    if (searching) {
      for (final entry in entries) {
        rows.add(_AppListRow.app(entry));
      }
    } else {
      for (final group in groupStartMenuEntries(entries)) {
        rows.add(_AppListRow.heading(group.key));
        for (final entry in group.entries) {
          rows.add(_AppListRow.app(entry));
        }
      }
    }

    // ListView wraps every child in a RepaintBoundary already, so one icon
    // settling cannot repaint the rows around it.
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        final heading = row.heading;
        if (heading != null) {
          return _AppListHeading(label: heading, accent: accent);
        }
        final entry = row.entry!;
        return _AppListEntryRow(
          key: ValueKey<String>('desktop-app-${entry.id}'),
          entry: entry,
          selected: searching && index == 0,
          accent: accent,
          onTap: () => onLaunch(entry),
          onShowMenu: (position) => onShowMenu(entry, position),
        );
      },
    );
  }
}

@immutable
class _AppListRow {
  const _AppListRow.heading(this.heading) : entry = null;
  const _AppListRow.app(this.entry) : heading = null;

  final String? heading;
  final DesktopStartMenuEntry? entry;
}

class _AppListHeading extends StatelessWidget {
  const _AppListHeading({required this.label, required this.accent});

  final String label;
  final WallpaperAccent accent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 12, top: 12, bottom: 2),
      child: Text(
        label,
        style: ShellText.cardTitle.copyWith(
          fontWeight: FontWeight.w700,
          color: accent.captionColor,
        ),
      ),
    );
  }
}

class _AppListEntryRow extends StatefulWidget {
  const _AppListEntryRow({
    super.key,
    required this.entry,
    required this.selected,
    required this.accent,
    required this.onTap,
    required this.onShowMenu,
  });

  final DesktopStartMenuEntry entry;
  final bool selected;
  final WallpaperAccent accent;
  final VoidCallback onTap;
  final ValueChanged<Offset> onShowMenu;

  @override
  State<_AppListEntryRow> createState() => _AppListEntryRowState();
}

class _AppListEntryRowState extends State<_AppListEntryRow> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    return Semantics(
      button: true,
      selected: widget.selected,
      label: context.l10n.desktopLaunchApplication(widget.entry.name),
      child: Focus(
        onFocusChange: (focused) => setState(() => _focused = focused),
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              (event.logicalKey == LogicalKeyboardKey.enter ||
                  event.logicalKey == LogicalKeyboardKey.space)) {
            widget.onTap();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: MouseRegion(
          cursor: ShellMouseCursors.link,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            onSecondaryTapUp: (details) =>
                widget.onShowMenu(details.globalPosition),
            child: AnimatedContainer(
              duration: Motion.tile,
              curve: Motion.standard,
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: widget.selected || _hovered || _focused
                    ? (widget.selected ? accent.cardFillTop : accent.cardFill)
                    : const Color(0x00000000),
                borderRadius: BorderRadius.circular(ShellRadii.window),
              ),
              // A focus ring drawn in front cannot inset the row, so the icon
              // and label stay put whether or not the row has focus.
              foregroundDecoration: _focused
                  ? BoxDecoration(
                      borderRadius: BorderRadius.circular(ShellRadii.window),
                      border: Border.all(color: accent.color),
                    )
                  : null,
              child: Row(
                children: [
                  SizedBox.square(
                    dimension: 24,
                    child: widget.entry.icon != null
                        ? ExcludeSemantics(
                            child: Icon(
                              widget.entry.icon!,
                              size: 20,
                              color: accent.color,
                            ),
                          )
                        : DeferredAppIcon(iconPath: widget.entry.iconPath),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.entry.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ShellText.cardTitle,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
