import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../input/shell_interaction_registry.dart';
import '../input/shell_visual_registry.dart';
import '../local_apps/local_flutter_application.dart';
import '../localization/denial_localizations.dart';
import '../models/denial_window.dart';
import '../models/display_layout.dart';
import '../state/display_layout.dart';
import '../state/shell_controller.dart';
import '../theme/motion.dart';
import '../theme/shell_theme.dart';
import '../theme/tokens.dart';
import '../wallpaper/state/wallpaper_accent.dart';
import '../widgets/shell_backdrop_blur.dart';
import '../widgets/window_hero.dart';
import '../widgets/window_surface_tree.dart';
import 'desktop_taskbar_button.dart';
import 'desktop_workspace.dart';

/// Target description for an active taskbar hover preview.
@immutable
class DesktopTaskbarPreviewTarget {
  const DesktopTaskbarPreviewTarget({
    required this.objectId,
    required this.buttonBounds,
    required this.side,
    this.monitorId,
  });

  final int objectId;
  final Rect buttonBounds;
  final SystemBarSide side;
  final int? monitorId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DesktopTaskbarPreviewTarget &&
          objectId == other.objectId &&
          buttonBounds == other.buttonBounds &&
          side == other.side &&
          monitorId == other.monitorId;

  @override
  int get hashCode => Object.hash(objectId, buttonBounds, side, monitorId);
}

/// Manages hover timing, adjacent switching, and debounce-closing for taskbar previews.
class DesktopTaskbarPreviewController
    extends Notifier<DesktopTaskbarPreviewTarget?> {
  @override
  DesktopTaskbarPreviewTarget? build() {
    ref.onDispose(() {
      _showTimer?.cancel();
      _hideTimer?.cancel();
    });
    return null;
  }

  Timer? _showTimer;
  Timer? _hideTimer;
  int _session = 0;

  static const Duration hoverShowDelay = Duration(milliseconds: 350);
  static const Duration hoverAdjacentDelay = Duration(milliseconds: 60);
  static const Duration hoverHideDelay = Duration(milliseconds: 250);

  /// Schedules showing a preview for [target].
  void scheduleShow(DesktopTaskbarPreviewTarget target) {
    _hideTimer?.cancel();
    _hideTimer = null;

    final isAlreadyShowing = state != null;
    if (isAlreadyShowing && state?.objectId == target.objectId) {
      return;
    }

    _showTimer?.cancel();
    final currentSession = ++_session;
    final delay = isAlreadyShowing ? hoverAdjacentDelay : hoverShowDelay;

    _showTimer = Timer(delay, () {
      if (_session == currentSession) {
        state = target;
      }
    });
  }

  /// Schedules closing the preview after a brief delay.
  void scheduleHide() {
    _showTimer?.cancel();
    _showTimer = null;

    _hideTimer?.cancel();
    final currentSession = ++_session;

    _hideTimer = Timer(hoverHideDelay, () {
      if (_session == currentSession) {
        state = null;
      }
    });
  }

  /// Cancels a pending hide timer (e.g. when pointer enters the preview card).
  void cancelHide() {
    _hideTimer?.cancel();
    _hideTimer = null;
  }

  /// Immediately hides the preview and clears all pending timers.
  void hideImmediately() {
    _showTimer?.cancel();
    _showTimer = null;
    _hideTimer?.cancel();
    _hideTimer = null;
    _session++;
    if (state != null) {
      state = null;
    }
  }
}

/// Global provider for the taskbar window preview controller.
final desktopTaskbarPreviewProvider =
    NotifierProvider<
      DesktopTaskbarPreviewController,
      DesktopTaskbarPreviewTarget?
    >(DesktopTaskbarPreviewController.new);

/// Full-stage overlay layer hosting the active taskbar window preview card.
class DesktopTaskbarPreviewLayer extends ConsumerWidget {
  const DesktopTaskbarPreviewLayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overviewActive = ref.watch(
      desktopWorkspaceProvider.select((s) => s.overviewActive),
    );
    if (overviewActive) {
      return const SizedBox.shrink();
    }

    final target = ref.watch(desktopTaskbarPreviewProvider);
    if (target == null) {
      return const SizedBox.shrink();
    }

    final window = ref.watch(
      shellControllerProvider.select(
        (s) => s.windowByObjectId(target.objectId),
      ),
    );

    if (window == null) {
      return const SizedBox.shrink();
    }

    final displayLayout = ref.watch(displayLayoutProvider);
    final viewSize = MediaQuery.sizeOf(context);
    Rect screenBounds = Offset.zero & viewSize;

    if (displayLayout != null && target.monitorId != null) {
      for (final output in displayLayout.outputs) {
        if (output.monitorId == target.monitorId) {
          screenBounds = output.logicalRect;
          break;
        }
      }
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        DesktopTaskbarPreviewPositionedCard(
          target: target,
          window: window,
          screenBounds: screenBounds,
        ),
      ],
    );
  }
}

/// Positioned card calculating alignment, screen edge clamping, and animations.
class DesktopTaskbarPreviewPositionedCard extends ConsumerWidget {
  const DesktopTaskbarPreviewPositionedCard({
    required this.target,
    required this.window,
    required this.screenBounds,
    super.key,
  });

  final DesktopTaskbarPreviewTarget target;
  final DenialWindow window;
  final Rect screenBounds;

  static const double _cardWidth = 240.0;
  static const double _headerHeight = 32.0;
  static const double _cardPadding = 8.0;
  static const double _screenMargin = 8.0;
  static const double _buttonOffset = 6.0;

  static double _desktopWindowAspect(DenialWindow window) {
    if (window.width <= 0 || window.height <= 0) {
      return 16.0 / 10.0;
    }
    return (window.width.toDouble() / window.height.toDouble())
        .clamp(0.35, 3.20)
        .toDouble();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aspect = _desktopWindowAspect(window);
    final thumbnailWidth = _cardWidth - (_cardPadding * 2);
    final rawHeight = thumbnailWidth / aspect;
    final thumbnailHeight = rawHeight.clamp(70.0, 160.0);
    final totalCardHeight =
        _headerHeight + thumbnailHeight + (_cardPadding * 2) + 4.0;

    double top;
    double left;

    switch (target.side) {
      case SystemBarSide.bottom:
        top = target.buttonBounds.top - totalCardHeight - _buttonOffset;
        left = target.buttonBounds.center.dx - (_cardWidth / 2.0);
        break;
      case SystemBarSide.top:
        top = target.buttonBounds.bottom + _buttonOffset;
        left = target.buttonBounds.center.dx - (_cardWidth / 2.0);
        break;
      case SystemBarSide.left:
        left = target.buttonBounds.right + _buttonOffset;
        top = target.buttonBounds.center.dy - (totalCardHeight / 2.0);
        break;
      case SystemBarSide.right:
        left = target.buttonBounds.left - _cardWidth - _buttonOffset;
        top = target.buttonBounds.center.dy - (totalCardHeight / 2.0);
        break;
      case SystemBarSide.hidden:
        return const SizedBox.shrink();
    }

    final minLeft = screenBounds.left + _screenMargin;
    final maxLeft = screenBounds.right - _cardWidth - _screenMargin;
    left = minLeft <= maxLeft ? left.clamp(minLeft, maxLeft) : minLeft;

    final minTop = screenBounds.top + _screenMargin;
    final maxTop = screenBounds.bottom - totalCardHeight - _screenMargin;
    top = minTop <= maxTop ? top.clamp(minTop, maxTop) : minTop;

    return Positioned(
      left: left,
      top: top,
      width: _cardWidth,
      height: totalCardHeight,
      child: RepaintBoundary(
        child: ShellVisualRegion(
          debugLabel: 'Taskbar preview (${window.title})',
          revision: Object.hash(target.objectId, target.monitorId),
          requiresClientSampling: true,
          child: ShellInputRegion(
            debugLabel: 'Taskbar preview (${window.title})',
            child: MouseRegion(
              onEnter: (_) {
                ref.read(desktopTaskbarPreviewProvider.notifier).cancelHide();
              },
              onExit: (_) {
                ref.read(desktopTaskbarPreviewProvider.notifier).scheduleHide();
              },
              child: _DesktopTaskbarPreviewCardContent(
                target: target,
                window: window,
                thumbnailWidth: thumbnailWidth,
                thumbnailHeight: thumbnailHeight,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopTaskbarPreviewCardContent extends ConsumerWidget {
  const _DesktopTaskbarPreviewCardContent({
    required this.target,
    required this.window,
    required this.thumbnailWidth,
    required this.thumbnailHeight,
  });

  final DesktopTaskbarPreviewTarget target;
  final DenialWindow window;
  final double thumbnailWidth;
  final double thumbnailHeight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ShellTheme.of(context);
    final accent = ref.watch(shellAccentProvider);
    final title = localizedWindowTitle(context, window);
    final isMinimized = ref.watch(
      desktopWorkspaceProvider.select(
        (s) => s.placements[window.objectId]?.minimized ?? false,
      ),
    );

    const borderRadius = BorderRadius.all(Radius.circular(ShellRadii.window));
    final previewSemanticLabel = context.l10n.taskbarPreviewTitle(title);

    return Semantics(
      button: true,
      label: previewSemanticLabel,
      enabled: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          ref.read(desktopTaskbarPreviewProvider.notifier).hideImmediately();
          ref.read(desktopWorkspaceProvider.notifier).activate(window.objectId);
          ref.read(shellControllerProvider.notifier).focusWindow(window);
        },
        child: ShellBackdropBlur(
          borderRadius: borderRadius,
          child: Container(
            decoration: BoxDecoration(
              color: theme.panelColor(accent.cardFillTop),
              borderRadius: borderRadius,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.12),
                width: 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.36),
                  blurRadius: 16.0,
                  offset: const Offset(0.0, 4.0),
                ),
              ],
            ),
            padding: const EdgeInsets.all(8.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header: Icon + Title + Close Button
                SizedBox(
                  height: 24.0,
                  child: Row(
                    children: [
                      _TaskbarPreviewIcon(window: window),
                      const SizedBox(width: 6.0),
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ShellText.systemBarValue.copyWith(
                            fontSize: 12.0,
                            fontWeight: FontWeight.w600,
                            color: ShellColors.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4.0),
                      _PreviewCloseButton(
                        window: window,
                        onClose: () {
                          ref
                              .read(desktopTaskbarPreviewProvider.notifier)
                              .hideImmediately();
                          ref
                              .read(shellControllerProvider.notifier)
                              .closeWindow(window);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6.0),
                // Thumbnail area: zero mobile status bars, true desktop window surface
                SizedBox(
                  width: thumbnailWidth,
                  height: thumbnailHeight,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4.0),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: ShellColors.background.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(4.0),
                        border: Border.all(
                          color: isMinimized
                              ? Colors.white.withValues(alpha: 0.08)
                              : kWindowHairline,
                          width: 1.0,
                        ),
                      ),
                      child: _TaskbarWindowThumbnail(
                        window: window,
                        isMinimized: isMinimized,
                      ),
                    ),
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

class _TaskbarWindowThumbnail extends StatelessWidget {
  const _TaskbarWindowThumbnail({
    required this.window,
    required this.isMinimized,
  });

  final DenialWindow window;
  final bool isMinimized;

  @override
  Widget build(BuildContext context) {
    if (window.isLocalFlutter) {
      return ExcludeSemantics(
        child: Container(
          color: ShellColors.background,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _TaskbarPreviewIcon(window: window),
                const SizedBox(height: 6.0),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0),
                  child: Text(
                    localizedWindowTitle(context, window),
                    style: ShellText.systemBarCaption.copyWith(
                      color: ShellColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (window.width <= 0 ||
        window.height <= 0 ||
        (window.surfaceLayers.isEmpty && window.textureId <= 0)) {
      return Container(
        color: ShellColors.background,
        child: Center(child: _TaskbarPreviewIcon(window: window)),
      );
    }

    return FittedBox(
      fit: BoxFit.contain,
      child: SizedBox(
        width: math.max(1.0, window.width.toDouble()),
        height: math.max(1.0, window.height.toDouble()),
        child: WindowSurfaceTree(
          window: window,
          filterQuality: FilterQuality.medium,
          includePopups: true,
        ),
      ),
    );
  }
}

class _TaskbarPreviewIcon extends ConsumerWidget {
  const _TaskbarPreviewIcon({required this.window});

  final DenialWindow window;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (window.isLocalFlutter) {
      final localApps = ref.watch(localFlutterApplicationsProvider);
      for (final app in localApps) {
        if (app.id == window.appId || app.titleFor(context) == window.title) {
          if (app.icon != null) {
            return Icon(
              app.icon,
              size: DesktopTaskbarButtonMetrics.iconSize,
              color: ShellColors.textPrimary,
            );
          }
          break;
        }
      }
      return const SizedBox.square(
        dimension: DesktopTaskbarButtonMetrics.iconSize,
      );
    }

    return SizedBox.square(
      dimension: DesktopTaskbarButtonMetrics.iconSize,
      child: TaskbarWindowIcon(window: window, active: true),
    );
  }
}

class _PreviewCloseButton extends StatefulWidget {
  const _PreviewCloseButton({required this.window, required this.onClose});

  final DenialWindow window;
  final VoidCallback onClose;

  @override
  State<_PreviewCloseButton> createState() => _PreviewCloseButtonState();
}

class _PreviewCloseButtonState extends State<_PreviewCloseButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final title = localizedWindowTitle(context, widget.window);
    final label = context.l10n.taskbarPreviewClose(title);

    return Semantics(
      button: true,
      label: label,
      child: MouseRegion(
        onEnter: (_) {
          if (mounted) setState(() => _hovered = true);
        },
        onExit: (_) {
          if (mounted) setState(() => _hovered = false);
        },
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onClose,
          child: AnimatedContainer(
            duration: Motion.pill,
            width: 20.0,
            height: 20.0,
            decoration: BoxDecoration(
              color: _hovered ? const Color(0xffc42b1c) : Colors.transparent,
              borderRadius: BorderRadius.circular(4.0),
            ),
            child: Center(
              child: Icon(
                Icons.close,
                size: 12.0,
                color: _hovered ? Colors.white : ShellColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
