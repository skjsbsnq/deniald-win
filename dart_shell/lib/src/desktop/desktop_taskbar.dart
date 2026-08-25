import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/display_layout.dart';
import '../state/shell_controller.dart';
import '../theme/motion.dart';
import '../theme/shell_theme.dart';
import '../wallpaper/state/wallpaper_accent.dart';
import '../widgets/shell_backdrop_blur.dart';
import 'desktop_taskbar_button.dart';
import 'desktop_workspace.dart';

@immutable
class _TaskbarWindowIds {
  const _TaskbarWindowIds(this.ids);

  final List<int> ids;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _TaskbarWindowIds && listEquals(ids, other.ids);

  @override
  int get hashCode => Object.hashAll(ids);
}

/// The desktop taskbar module rendering open window buttons in a frosted pill card.
///
/// Designed with strict selective observation: dragging or resizing windows
/// will never trigger a rebuild of the taskbar container or its buttons.
class DesktopTaskbar extends ConsumerWidget {
  const DesktopTaskbar({
    required this.side,
    this.monitorId,
    this.compactThreshold = 8,
    super.key,
  });

  final SystemBarSide side;
  final int? monitorId;
  final int compactThreshold;

  static const double _buttonGap = 4.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAppWindowIds = ref.watch(
      shellControllerProvider.select((state) {
        return _TaskbarWindowIds(
          state.openAppWindows.map((w) => w.objectId).toList(growable: false),
        );
      }),
    );

    final taskbarIds = ref.watch(
      desktopWorkspaceProvider.select((state) {
        final result = <int>[];
        for (final id in userAppWindowIds.ids) {
          final placement = state.placements[id];
          if (placement == null) {
            result.add(id);
          } else if (monitorId == null ||
              placement.monitorId == monitorId ||
              placement.monitorId <= 0 ||
              (monitorId != null && monitorId! <= 0)) {
            result.add(id);
          }
        }
        return _TaskbarWindowIds(result);
      }),
    );

    final visibleIds = taskbarIds.ids;
    if (visibleIds.isEmpty) {
      return const SizedBox.shrink();
    }

    final accent = ref.watch(shellAccentProvider);
    final horizontal = side.isHorizontal;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Automatically switch to compact mode if window count exceeds threshold
        // or if available main-axis extent is too constrained.
        final maxExtent = horizontal
            ? constraints.maxWidth
            : constraints.maxHeight;
        final bool isCompact =
            !horizontal ||
            visibleIds.length >= compactThreshold ||
            (maxExtent.isFinite &&
                maxExtent > 0 &&
                (maxExtent / visibleIds.length) < 110.0);

        final items = <Widget>[
          for (int i = 0; i < visibleIds.length; i += 1) ...[
            if (i > 0)
              horizontal
                  ? const SizedBox(width: _buttonGap)
                  : const SizedBox(height: _buttonGap),
            DesktopTaskbarWindowButton(
              key: ValueKey('taskbar-window-${visibleIds[i]}'),
              objectId: visibleIds[i],
              side: side,
              compact: isCompact,
              monitorId: monitorId,
            ),
          ],
        ];

        final child = horizontal
            ? Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: items,
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: items,
              );

        return _TaskbarCard(
          accent: accent,
          horizontal: horizontal,
          child: child,
        );
      },
    );
  }
}

class _TaskbarCard extends StatelessWidget {
  const _TaskbarCard({
    required this.accent,
    required this.horizontal,
    required this.child,
  });

  final WallpaperAccent accent;
  final bool horizontal;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(999));
    final theme = ShellTheme.of(context);

    return ShellBackdropBlur(
      grouped: true,
      borderRadius: radius,
      child: AnimatedContainer(
        duration: Motion.wallpaperReveal,
        curve: Motion.standard,
        padding: horizontal
            ? const EdgeInsets.symmetric(horizontal: 4.0, vertical: 0.0)
            : const EdgeInsets.symmetric(horizontal: 0.0, vertical: 4.0),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              theme.panelColor(accent.cardFillTop),
              theme.panelColor(accent.cardFill),
            ],
          ),
          borderRadius: radius,
        ),
        alignment: Alignment.center,
        child: child,
      ),
    );
  }
}
