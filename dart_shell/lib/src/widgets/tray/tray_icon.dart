import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../models/tray_item.dart';
import '../../services/sni_pixmap_decoder.dart';
import '../../services/xdg_icon_theme.dart';
import '../../state/status_notifier.dart';
import '../../theme/tokens.dart';
import 'tray_menu.dart';

/// Metrics and sizing constants for tray icons.
abstract final class TrayMetrics {
  /// Standard tray icon logical dimension (width and height).
  static const double iconSize = 20.0;

  /// Default padding around tray buttons.
  static const EdgeInsets buttonPadding = EdgeInsets.all(4.0);

  /// Size ratio of overlay status badges relative to the base icon.
  static const double overlayScale = 0.55;

  /// Default delay before showing tooltip on hover.
  static const Duration tooltipWaitDuration = Duration(milliseconds: 350);

  /// Fallback icon asset shipped with Denial shell.
  static const String fallbackAsset =
      'assets/icons/application-default-icon.svg';
}

/// A reactive widget that resolves and renders a StatusNotifierItem tray icon.
///
/// Supports:
/// - Status-aware icon selection (Attention icons for `needsAttention` status)
/// - Raw ARGB32 pixmap decoding via [SniPixmapDecoder]
/// - Freedesktop XDG icon theme resolution via [XdgIconTheme] (with `IconThemePath`)
/// - Secondary overlay badge rendering in the bottom-right corner
/// - Sanitized multi-line HTML tooltips
/// - Passive item dimming and hover interaction
/// - Complete repaint boundary isolation
class TrayIcon extends ConsumerStatefulWidget {
  const TrayIcon({
    super.key,
    required this.item,
    this.size = TrayMetrics.iconSize,
    this.onTap,
    this.onSecondaryTap,
    this.showTooltip = true,
  });

  final TrayItem item;
  final double size;
  final VoidCallback? onTap;
  final VoidCallback? onSecondaryTap;
  final bool showTooltip;

  @override
  ConsumerState<TrayIcon> createState() => _TrayIconState();
}

class _TrayIconState extends ConsumerState<TrayIcon> {
  ui.Image? _mainPixmapImage;
  String? _mainIconFilePath;
  ui.Image? _overlayPixmapImage;
  String? _overlayIconFilePath;

  bool _isHovered = false;
  int _resolveGeneration = 0;

  @override
  void initState() {
    super.initState();
    _scheduleResolve();
  }

  @override
  void didUpdateWidget(covariant TrayIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.item != oldWidget.item || widget.size != oldWidget.size) {
      _scheduleResolve();
    }
  }

  @override
  void dispose() {
    _mainPixmapImage?.dispose();
    _mainPixmapImage = null;
    _overlayPixmapImage?.dispose();
    _overlayPixmapImage = null;
    super.dispose();
  }

  void _scheduleResolve() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _resolveIcons();
      }
    });
  }

  Future<void> _resolveIcons() async {
    final generation = ++_resolveGeneration;
    final pixelRatio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
    final targetPhysicalSize = (widget.size * pixelRatio).round().clamp(
      16,
      512,
    );

    final item = widget.item;

    // 1. Determine main candidate sources based on status
    final bool isAttention = item.status == TrayItemStatus.needsAttention;
    final candidatePixmaps = isAttention && item.attentionIconPixmap.isNotEmpty
        ? item.attentionIconPixmap
        : item.iconPixmap;
    final candidateIconName = isAttention && item.attentionIconName.isNotEmpty
        ? item.attentionIconName
        : item.iconName;

    ui.Image? resolvedMainPixmap;
    String? resolvedMainPath;

    // A. Pixmap first
    final bestPixmap = selectBestPixmap(candidatePixmaps, targetPhysicalSize);
    if (bestPixmap != null) {
      resolvedMainPixmap = await defaultSniPixmapDecoder.decode(
        bestPixmap,
        customKey: '${item.key}_main_${bestPixmap.width}',
      );
    }

    // B. IconName second if no pixmap
    if (resolvedMainPixmap == null && candidateIconName.isNotEmpty) {
      resolvedMainPath = await defaultXdgIconTheme.lookupIcon(
        candidateIconName,
        iconThemePath: item.iconThemePath,
        targetSize: targetPhysicalSize,
        scale: pixelRatio.round().clamp(1, 4),
      );
    }

    // 2. Determine overlay candidate sources
    ui.Image? resolvedOverlayPixmap;
    String? resolvedOverlayPath;
    final overlayTargetSize = (targetPhysicalSize * TrayMetrics.overlayScale)
        .round()
        .clamp(10, 256);

    if (item.overlayIconPixmap.isNotEmpty) {
      final bestOverlayPixmap = selectBestPixmap(
        item.overlayIconPixmap,
        overlayTargetSize,
      );
      if (bestOverlayPixmap != null) {
        resolvedOverlayPixmap = await defaultSniPixmapDecoder.decode(
          bestOverlayPixmap,
          customKey: '${item.key}_overlay_${bestOverlayPixmap.width}',
        );
      }
    }

    if (resolvedOverlayPixmap == null && item.overlayIconName.isNotEmpty) {
      resolvedOverlayPath = await defaultXdgIconTheme.lookupIcon(
        item.overlayIconName,
        iconThemePath: item.iconThemePath,
        targetSize: overlayTargetSize,
        scale: pixelRatio.round().clamp(1, 4),
      );
    }

    if (!mounted || generation != _resolveGeneration) {
      resolvedMainPixmap?.dispose();
      resolvedOverlayPixmap?.dispose();
      return;
    }

    final oldMain = _mainPixmapImage;
    final oldOverlay = _overlayPixmapImage;

    setState(() {
      _mainPixmapImage = resolvedMainPixmap;
      _mainIconFilePath = resolvedMainPath;
      _overlayPixmapImage = resolvedOverlayPixmap;
      _overlayIconFilePath = resolvedOverlayPath;
    });

    oldMain?.dispose();
    oldOverlay?.dispose();
  }

  String _buildTooltipText() {
    final title = widget.item.sanitizedToolTipTitle;
    final desc = widget.item.sanitizedToolTipDescription;
    if (title.isNotEmpty && desc.isNotEmpty) {
      return '$title\n$desc';
    }
    if (desc.isNotEmpty) return desc;
    if (title.isNotEmpty) return title;
    return widget.item.displayLabel;
  }

  void _showMenu() {
    final renderBox = context.findRenderObject() as RenderBox?;
    final origin = renderBox != null && renderBox.hasSize
        ? renderBox.localToGlobal(Offset.zero)
        : Offset.zero;
    final pos = Offset(origin.dx, origin.dy + widget.size);
    showTrayMenu(context: context, ref: ref, item: widget.item, position: pos);
  }

  Widget _buildMainIcon() {
    if (_mainPixmapImage != null) {
      return RawImage(
        image: _mainPixmapImage,
        width: widget.size,
        height: widget.size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
      );
    }

    if (_mainIconFilePath != null) {
      final path = _mainIconFilePath!;
      if (path.toLowerCase().endsWith('.svg')) {
        return SvgPicture.file(
          File(path),
          width: widget.size,
          height: widget.size,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => _buildFallbackIcon(),
        );
      }
      return Image.file(
        File(path),
        width: widget.size,
        height: widget.size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, _, _) => _buildFallbackIcon(),
      );
    }

    return _buildFallbackIcon();
  }

  Widget _buildOverlayBadge() {
    final overlaySize = widget.size * TrayMetrics.overlayScale;

    if (_overlayPixmapImage != null) {
      return RawImage(
        image: _overlayPixmapImage,
        width: overlaySize,
        height: overlaySize,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
      );
    }

    if (_overlayIconFilePath != null) {
      final path = _overlayIconFilePath!;
      if (path.toLowerCase().endsWith('.svg')) {
        return SvgPicture.file(
          File(path),
          width: overlaySize,
          height: overlaySize,
          fit: BoxFit.contain,
        );
      }
      return Image.file(
        File(path),
        width: overlaySize,
        height: overlaySize,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildFallbackIcon() {
    return SvgPicture.asset(
      TrayMetrics.fallbackAsset,
      width: widget.size,
      height: widget.size,
      fit: BoxFit.contain,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool hasOverlay =
        _overlayPixmapImage != null || _overlayIconFilePath != null;
    final bool isPassive = widget.item.status == TrayItemStatus.passive;

    Widget content = SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          _buildMainIcon(),
          if (hasOverlay)
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                padding: const EdgeInsets.all(1),
                decoration: const BoxDecoration(
                  color: ShellColors.background,
                  shape: BoxShape.circle,
                ),
                child: _buildOverlayBadge(),
              ),
            ),
        ],
      ),
    );

    if (isPassive) {
      content = Opacity(opacity: 0.65, child: content);
    }

    void handleTap() {
      if (widget.onTap != null) {
        widget.onTap!();
        return;
      }
      if (widget.item.itemIsMenu) {
        _showMenu();
      } else {
        ref.read(statusNotifierProvider.notifier).activate(widget.item);
      }
    }

    void handleSecondaryTap() {
      if (widget.onSecondaryTap != null) {
        widget.onSecondaryTap!();
        return;
      }
      _showMenu();
    }

    final container = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: handleTap,
        onSecondaryTap: handleSecondaryTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: TrayMetrics.buttonPadding,
          decoration: BoxDecoration(
            color: _isHovered
                ? ShellColors.windowButtonHover
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: content,
        ),
      ),
    );

    if (!widget.showTooltip) {
      return RepaintBoundary(child: container);
    }

    return RepaintBoundary(
      child: Tooltip(
        message: _buildTooltipText(),
        waitDuration: TrayMetrics.tooltipWaitDuration,
        decoration: BoxDecoration(
          color: ShellColors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: ShellColors.hairlineSoft),
          boxShadow: const [
            BoxShadow(
              color: ShellColors.shadow,
              blurRadius: 8,
              offset: Offset(0, 4),
            ),
          ],
        ),
        textStyle: const TextStyle(
          color: ShellColors.textPrimary,
          fontSize: 12,
          height: 1.35,
        ),
        child: container,
      ),
    );
  }
}
