part of 'desktop_shell.dart';

/// Shared geometry for the ChromeOS-style launcher bubble.
///
/// Both the overlay positioning rect and the launcher's own layout must agree
/// on the bubble width; a single source keeps them from drifting apart.
class _LauncherBubbleMetrics {
  _LauncherBubbleMetrics._();

  static const double idealWidth = 600.0;

  /// The bubble width for [viewSize], clamped so the bubble plus its 8px
  /// margins stay inside the view.
  static double width(Size viewSize) =>
      (viewSize.width - 16.0).clamp(320.0, idealWidth).toDouble();
}

/// Launcher-bubble mount point above the window layer.
///
/// Since the ChromeOS shelf is the only desktop bar form, this overlay keeps
/// exactly three pieces of the legacy panel host: the launcher bubble itself,
/// its full-scene dismiss barrier, and the legacy edge-hover trigger that
/// opens the launcher (its rect still follows the persisted
/// [ShellPopupPlacement], which no longer has a settings editor). The
/// dashboard surface and its trigger are gone — the unified dashboard bubble
/// owns that role.
class _DesktopPanelOverlay extends ConsumerStatefulWidget {
  const _DesktopPanelOverlay({
    required this.viewSize,
    required this.shellOutputRect,
    required this.applicationSearchFocusNode,
    required this.onOpenLauncher,
    required this.onDismissLauncher,
    required this.onCancelPanelClose,
    required this.onSchedulePanelClose,
    required this.onPanelOpened,
    required this.onLaunchApp,
    required this.onLaunchLocalApp,
  });

  final Size viewSize;
  final Rect? shellOutputRect;
  final FocusNode applicationSearchFocusNode;
  final VoidCallback onOpenLauncher;
  final VoidCallback onDismissLauncher;
  final VoidCallback onCancelPanelClose;
  final VoidCallback onSchedulePanelClose;

  /// Reports that the launcher finished opening, completing the hover
  /// controller's open handshake so a pointer that already left can schedule
  /// its delayed close.
  final VoidCallback onPanelOpened;
  final ValueChanged<DesktopApp> onLaunchApp;
  final ValueChanged<LocalFlutterApplication> onLaunchLocalApp;

  @override
  ConsumerState<_DesktopPanelOverlay> createState() =>
      _DesktopPanelOverlayState();
}

class _DesktopPanelOverlayState extends ConsumerState<_DesktopPanelOverlay> {
  DesktopApplicationLauncher? _applicationLauncher;
  bool _launcherWasOpen = false;

  DesktopApplicationLauncher _cachedApplicationLauncher() {
    final cached = _applicationLauncher;
    if (cached != null &&
        identical(cached.searchFocusNode, widget.applicationSearchFocusNode) &&
        cached.onEnter == widget.onCancelPanelClose &&
        cached.onExit == widget.onSchedulePanelClose &&
        cached.onDismiss == widget.onDismissLauncher &&
        cached.onLaunch == widget.onLaunchApp &&
        cached.onLaunchLocal == widget.onLaunchLocalApp) {
      return cached;
    }
    return _applicationLauncher = DesktopApplicationLauncher(
      searchFocusNode: widget.applicationSearchFocusNode,
      onEnter: widget.onCancelPanelClose,
      onExit: widget.onSchedulePanelClose,
      onDismiss: widget.onDismissLauncher,
      onLaunch: widget.onLaunchApp,
      onLaunchLocal: widget.onLaunchLocalApp,
    );
  }

  @override
  Widget build(BuildContext context) {
    final panelState = ref.watch(
      desktopWorkspaceProvider.select(
        (state) => (panel: state.panel, overviewActive: state.overviewActive),
      ),
    );
    final overlaySettings = ref.watch(
      shellSettingsProvider.select((settings) => settings.overlays),
    );
    final configuredThickness = ref.watch(
      shellSettingsProvider.select((s) => s.layout.effectiveSystemBarThickness),
    );
    final effectiveShelfHeight = configuredThickness > 0
        ? configuredThickness
        : ShelfLayer.defaultThickness;

    final bubbleHeight = math.min(
      560.0,
      math.max(200.0, widget.viewSize.height - effectiveShelfHeight - 16.0),
    );
    final launcherRect = Rect.fromLTWH(
      8.0,
      math.max(
        8.0,
        widget.viewSize.height - effectiveShelfHeight - 8.0 - bubbleHeight,
      ),
      _LauncherBubbleMetrics.width(widget.viewSize),
      bubbleHeight,
    );
    final launcherTriggerRect = DesktopMetrics.launcherTriggerRect(
      widget.viewSize,
      outputRect: widget.shellOutputRect,
      placement: overlaySettings.launcher,
    );
    final launcherOpen = panelState.panel == DesktopPanel.launcher;

    // The launcher's own spring owns the entrance, so no transition widget is
    // left to report completion. Complete the hover controller's open
    // handshake on the first frame the panel is open instead; otherwise a
    // pointer that left mid-entrance would keep a pending close forever.
    if (launcherOpen && !_launcherWasOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.onPanelOpened();
        }
      });
    }
    _launcherWasOpen = launcherOpen;

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Positioned.fill(
          key: const ValueKey<String>('desktop-launcher-dismiss-barrier'),
          child: ShellInputRegion(
            debugLabel: 'Desktop launcher dismiss barrier',
            active: launcherOpen,
            pointerPolicy: ShellPointerPolicy.fullScene,
            keyboardPolicy: ShellKeyboardPolicy.none,
            child: IgnorePointer(
              ignoring: !launcherOpen,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onDismissLauncher,
              ),
            ),
          ),
        ),
        Positioned.fromRect(
          key: const ValueKey<String>('desktop-launcher-position'),
          rect: launcherRect,
          child: ShellInputRegion(
            debugLabel: 'Desktop application launcher',
            active: launcherOpen,
            pointerPolicy: ShellPointerPolicy.fullScene,
            keyboardPolicy: ShellKeyboardPolicy.capture,
            child: IgnorePointer(
              ignoring: !launcherOpen,
              child: _cachedApplicationLauncher(),
            ),
          ),
        ),
        if (!panelState.overviewActive && !launcherTriggerRect.isEmpty)
          Positioned.fromRect(
            rect: launcherTriggerRect,
            child: ShellInputRegion(
              debugLabel: 'Desktop launcher edge trigger',
              child: _DesktopPanelEdgeTrigger(
                onEnter: widget.onOpenLauncher,
                onExit: widget.onSchedulePanelClose,
              ),
            ),
          ),
      ],
    );
  }
}
