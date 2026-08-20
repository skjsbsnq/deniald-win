import 'package:flutter/foundation.dart';

/// The visual presentation status requested by a StatusNotifierItem.
enum TrayItemStatus {
  /// The item is passive and can be hidden in an overflow / secondary area.
  passive,

  /// The item is active and should be presented in the primary tray area.
  active,

  /// The item requests urgent user attention.
  needsAttention;

  static TrayItemStatus fromString(String? raw) {
    switch (raw?.trim().toLowerCase()) {
      case 'passive':
        return TrayItemStatus.passive;
      case 'needsattention':
      case 'needs_attention':
        return TrayItemStatus.needsAttention;
      case 'active':
      default:
        return TrayItemStatus.active;
    }
  }

  String toWireString() {
    switch (this) {
      case TrayItemStatus.passive:
        return 'Passive';
      case TrayItemStatus.active:
        return 'Active';
      case TrayItemStatus.needsAttention:
        return 'NeedsAttention';
    }
  }
}

/// The broad functional category of a StatusNotifierItem.
enum TrayItemCategory {
  applicationStatus,
  communications,
  systemServices,
  hardware,
  other;

  static TrayItemCategory fromString(String? raw) {
    switch (raw?.trim().toLowerCase()) {
      case 'applicationstatus':
      case 'application_status':
        return TrayItemCategory.applicationStatus;
      case 'communications':
      case 'communication':
        return TrayItemCategory.communications;
      case 'systemservices':
      case 'system_services':
        return TrayItemCategory.systemServices;
      case 'hardware':
        return TrayItemCategory.hardware;
      default:
        return TrayItemCategory.other;
    }
  }

  String toWireString() {
    switch (this) {
      case TrayItemCategory.applicationStatus:
        return 'ApplicationStatus';
      case TrayItemCategory.communications:
        return 'Communications';
      case TrayItemCategory.systemServices:
        return 'SystemServices';
      case TrayItemCategory.hardware:
        return 'Hardware';
      case TrayItemCategory.other:
        return 'ApplicationStatus';
    }
  }
}

/// Sanitizes tooltip text by stripping HTML tags and converting line breaks to standard newlines.
String sanitizeToolTipText(String raw) {
  if (raw.isEmpty) return '';
  // Convert break and paragraph tags to newlines
  var text = raw.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
  text = text.replaceAll(RegExp(r'</?p\s*/?>', caseSensitive: false), '\n');
  // Strip all other HTML tags
  text = text.replaceAll(RegExp(r'<[a-zA-Z\/][^>]*>'), '');
  // Unescape common HTML entities
  text = text
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&#39;', "'")
      .replaceAll('&nbsp;', ' ');
  // Keep markup-induced paragraph boundaries readable without allowing an
  // untrusted tooltip to consume arbitrary vertical space.
  text = text.replaceAll(RegExp(r'\n{2,}'), '\n');
  return text.trim();
}

/// Raw ARGB32 pixmap image data provided by a StatusNotifierItem.
@immutable
class TrayPixmap {
  const TrayPixmap({
    required this.width,
    required this.height,
    required this.bytes,
  });

  /// Width in pixels.
  final int width;

  /// Height in pixels.
  final int height;

  /// Raw byte buffer in network byte order (Big-Endian ARGB32).
  final Uint8List bytes;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrayPixmap &&
          other.width == width &&
          other.height == height &&
          listEquals(other.bytes, bytes);

  @override
  int get hashCode => Object.hash(width, height, Object.hashAll(bytes));

  @override
  String toString() => 'TrayPixmap(${width}x$height, ${bytes.length} bytes)';
}

/// An immutable representation of an individual StatusNotifierItem exposed via D-Bus.
@immutable
class TrayItem {
  const TrayItem({
    required this.service,
    required this.path,
    required this.id,
    required this.title,
    this.status = TrayItemStatus.active,
    this.category = TrayItemCategory.applicationStatus,
    this.windowId = 0,
    this.iconName = '',
    this.iconThemePath = '',
    this.iconPixmap = const <TrayPixmap>[],
    this.overlayIconName = '',
    this.overlayIconPixmap = const <TrayPixmap>[],
    this.attentionIconName = '',
    this.attentionIconPixmap = const <TrayPixmap>[],
    this.menuPath = '',
    this.itemIsMenu = false,
    this.toolTipIconName = '',
    this.toolTipIconPixmap = const <TrayPixmap>[],
    this.toolTipTitle = '',
    this.toolTipDescription = '',
  });

  /// The unique or well-known D-Bus bus name owning this item (e.g. `:1.42` or `org.kde.StatusNotifierItem-1024`).
  final String service;

  /// The D-Bus object path of this item (e.g. `/StatusNotifierItem` or `/org/ayatana/NotificationItem/nm_applet`).
  final String path;

  /// Application identifier (e.g. `nm-applet`, `discord`, `steam`).
  final String id;

  /// Human-readable title or label for this item.
  final String title;

  /// Visual status of the item.
  final TrayItemStatus status;

  /// Category describing the item's role.
  final TrayItemCategory category;

  /// Associated X11 / Wayland window ID (if provided).
  final int windowId;

  /// Freedesktop icon name for standard display.
  final String iconName;

  /// Custom icon theme directory path specified by the item (if any).
  final String iconThemePath;

  /// Available raw pixmap variants for standard display.
  final List<TrayPixmap> iconPixmap;

  /// Freedesktop icon name for overlay badges.
  final String overlayIconName;

  /// Available raw pixmap variants for overlay badges.
  final List<TrayPixmap> overlayIconPixmap;

  /// Freedesktop icon name when status is [TrayItemStatus.needsAttention].
  final String attentionIconName;

  /// Available raw pixmap variants when status is [TrayItemStatus.needsAttention].
  final List<TrayPixmap> attentionIconPixmap;

  /// D-Bus object path to the DBusMenu interface (T15).
  final String menuPath;

  /// Whether the item acts directly as a menu rather than an icon.
  final bool itemIsMenu;

  /// Freedesktop icon name embedded in ToolTip.
  final String toolTipIconName;

  /// Available raw pixmap variants embedded in ToolTip.
  final List<TrayPixmap> toolTipIconPixmap;

  /// Tooltip headline text.
  final String toolTipTitle;

  /// Tooltip detailed description or body text.
  final String toolTipDescription;

  /// Unique composite key identifying this item on the bus.
  String get key => '$service$path';

  /// Primary display label (prefers title, falls back to id, then service).
  String get displayLabel {
    if (title.trim().isNotEmpty) return title.trim();
    if (id.trim().isNotEmpty) return id.trim();
    return service;
  }

  /// Sanitized tooltip body text with HTML stripped.
  String get sanitizedToolTipDescription =>
      sanitizeToolTipText(toolTipDescription);

  /// Sanitized tooltip title text with HTML stripped.
  String get sanitizedToolTipTitle => sanitizeToolTipText(toolTipTitle);

  TrayItem copyWith({
    String? service,
    String? path,
    String? id,
    String? title,
    TrayItemStatus? status,
    TrayItemCategory? category,
    int? windowId,
    String? iconName,
    String? iconThemePath,
    List<TrayPixmap>? iconPixmap,
    String? overlayIconName,
    List<TrayPixmap>? overlayIconPixmap,
    String? attentionIconName,
    List<TrayPixmap>? attentionIconPixmap,
    String? menuPath,
    bool? itemIsMenu,
    String? toolTipIconName,
    List<TrayPixmap>? toolTipIconPixmap,
    String? toolTipTitle,
    String? toolTipDescription,
  }) {
    return TrayItem(
      service: service ?? this.service,
      path: path ?? this.path,
      id: id ?? this.id,
      title: title ?? this.title,
      status: status ?? this.status,
      category: category ?? this.category,
      windowId: windowId ?? this.windowId,
      iconName: iconName ?? this.iconName,
      iconThemePath: iconThemePath ?? this.iconThemePath,
      iconPixmap: iconPixmap ?? this.iconPixmap,
      overlayIconName: overlayIconName ?? this.overlayIconName,
      overlayIconPixmap: overlayIconPixmap ?? this.overlayIconPixmap,
      attentionIconName: attentionIconName ?? this.attentionIconName,
      attentionIconPixmap: attentionIconPixmap ?? this.attentionIconPixmap,
      menuPath: menuPath ?? this.menuPath,
      itemIsMenu: itemIsMenu ?? this.itemIsMenu,
      toolTipIconName: toolTipIconName ?? this.toolTipIconName,
      toolTipIconPixmap: toolTipIconPixmap ?? this.toolTipIconPixmap,
      toolTipTitle: toolTipTitle ?? this.toolTipTitle,
      toolTipDescription: toolTipDescription ?? this.toolTipDescription,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TrayItem &&
        other.service == service &&
        other.path == path &&
        other.id == id &&
        other.title == title &&
        other.status == status &&
        other.category == category &&
        other.windowId == windowId &&
        other.iconName == iconName &&
        other.iconThemePath == iconThemePath &&
        listEquals(other.iconPixmap, iconPixmap) &&
        other.overlayIconName == overlayIconName &&
        listEquals(other.overlayIconPixmap, overlayIconPixmap) &&
        other.attentionIconName == attentionIconName &&
        listEquals(other.attentionIconPixmap, attentionIconPixmap) &&
        other.menuPath == menuPath &&
        other.itemIsMenu == itemIsMenu &&
        other.toolTipIconName == toolTipIconName &&
        listEquals(other.toolTipIconPixmap, toolTipIconPixmap) &&
        other.toolTipTitle == toolTipTitle &&
        other.toolTipDescription == toolTipDescription;
  }

  @override
  int get hashCode => Object.hash(
    service,
    path,
    id,
    title,
    status,
    category,
    windowId,
    iconName,
    iconThemePath,
    Object.hashAll(iconPixmap),
    overlayIconName,
    Object.hashAll(overlayIconPixmap),
    attentionIconName,
    Object.hashAll(attentionIconPixmap),
    menuPath,
    itemIsMenu,
    toolTipIconName,
    Object.hashAll(toolTipIconPixmap),
    toolTipTitle,
    toolTipDescription,
  );

  @override
  String toString() =>
      'TrayItem(service: $service, path: $path, id: $id, title: $title, status: $status, icon: $iconName, pixmaps: ${iconPixmap.length})';
}
