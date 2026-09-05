import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/shell_theme.dart';
import '../theme/tokens.dart';

/// Active menu session tracking to ensure mutual exclusion between shell menus.
class ShellMenuSession {
  const ShellMenuSession({required this.owner, required this.dismiss});

  final Object owner;
  final VoidCallback dismiss;
}

final shellMenuSessionProvider =
    NotifierProvider<ShellMenuSessionController, ShellMenuSession?>(
      ShellMenuSessionController.new,
    );

class ShellMenuSessionController extends Notifier<ShellMenuSession?> {
  final Set<int> _menuPointerDowns = <int>{};

  @override
  ShellMenuSession? build() => null;

  void show(Object owner, VoidCallback dismiss) {
    final previous = state;
    if (previous != null && !identical(previous.owner, owner)) {
      previous.dismiss();
    }
    state = ShellMenuSession(owner: owner, dismiss: dismiss);
  }

  void clear(Object owner) {
    if (identical(state?.owner, owner)) {
      state = null;
    }
  }

  void dismiss() {
    final current = state;
    if (current == null) {
      return;
    }
    state = null;
    current.dismiss();
  }

  void noteMenuPointerDown(int pointer) {
    _menuPointerDowns.add(pointer);
  }

  bool takeMenuPointerDown(int pointer) {
    return _menuPointerDowns.remove(pointer);
  }
}

/// Standard menu container style matching the Shell M3 design language.
MenuStyle shellMenuStyle(BuildContext context) {
  final accent = ShellTheme.of(context).accentPalette;
  final viewHeight = MediaQuery.sizeOf(context).height;
  return MenuStyle(
    backgroundColor: WidgetStatePropertyAll<Color>(
      context.shellColors.panelBackgroundBottom,
    ),
    shadowColor: WidgetStatePropertyAll<Color>(context.shellColors.shadow),
    surfaceTintColor: WidgetStatePropertyAll<Color>(
      ShellMediaColors.transparentDark,
    ),
    elevation: const WidgetStatePropertyAll<double>(14),
    padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
      EdgeInsets.symmetric(vertical: 4),
    ),
    minimumSize: const WidgetStatePropertyAll<Size>(Size(164, 0)),
    maximumSize: WidgetStatePropertyAll<Size>(
      Size(320, (viewHeight - 16).clamp(120, 560).toDouble()),
    ),
    side: WidgetStatePropertyAll<BorderSide>(
      BorderSide(color: accent.outline, width: 1),
    ),
    shape: WidgetStatePropertyAll<OutlinedBorder>(
      RoundedRectangleBorder(
        borderRadius: context.shellTheme.borderRadius(ShellShapeScale.medium),
      ),
    ),
    visualDensity: VisualDensity.compact,
  );
}

/// Standard menu item button style for shell context menus.
ButtonStyle shellMenuButtonStyle(
  BuildContext context, {
  bool destructive = false,
}) {
  final accent = ShellTheme.of(context).accentPalette;
  return ButtonStyle(
    foregroundColor: WidgetStateProperty.resolveWith<Color>((states) {
      if (states.contains(WidgetState.disabled)) {
        return context.shellColors.textTertiary;
      }
      return destructive
          ? context.shellColors.performanceBad
          : context.shellColors.textPrimary;
    }),
    iconColor: WidgetStateProperty.resolveWith<Color>((states) {
      if (states.contains(WidgetState.disabled)) {
        return context.shellColors.textTertiary;
      }
      return destructive
          ? context.shellColors.performanceBad
          : context.shellColors.textSecondary;
    }),
    backgroundColor: WidgetStateProperty.resolveWith<Color>((states) {
      if (states.contains(WidgetState.hovered) ||
          states.contains(WidgetState.focused)) {
        return accent.subtle;
      }
      return ShellMediaColors.transparentDark;
    }),
    overlayColor: const WidgetStatePropertyAll<Color>(
      ShellMediaColors.transparentDark,
    ),
    textStyle: const WidgetStatePropertyAll<TextStyle>(
      TextStyle(
        fontFamilyFallback: ShellText.fallbackFontFamilies,
        fontSize: 12,
        height: 1.25,
        leadingDistribution: TextLeadingDistribution.even,
        fontWeight: FontWeight.w500,
        decoration: TextDecoration.none,
      ),
    ),
    padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
      EdgeInsets.symmetric(horizontal: 10),
    ),
    minimumSize: const WidgetStatePropertyAll<Size>(Size(164, 28)),
    maximumSize: const WidgetStatePropertyAll<Size>(Size(320, 28)),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    visualDensity: VisualDensity.standard,
    shape: WidgetStatePropertyAll<OutlinedBorder>(
      RoundedRectangleBorder(
        borderRadius: context.shellTheme.borderRadius(ShellShapeScale.small),
      ),
    ),
    alignment: AlignmentDirectional.centerStart,
  );
}

/// A standard menu item in shell popup menus.
class ShellMenuItem extends StatelessWidget {
  const ShellMenuItem({
    required this.label,
    this.icon,
    this.leading,
    this.onPressed,
    this.destructive = false,
    super.key,
  });

  final String label;
  final IconData? icon;
  final Widget? leading;
  final VoidCallback? onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    Widget? leadingWidget = leading;
    if (leadingWidget == null && icon != null) {
      leadingWidget = Icon(icon, size: 16);
    }

    return MenuItemButton(
      leadingIcon: leadingWidget,
      style: shellMenuButtonStyle(context, destructive: destructive),
      onPressed: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text(
          label,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          textHeightBehavior: const TextHeightBehavior(
            applyHeightToFirstAscent: true,
            applyHeightToLastDescent: true,
            leadingDistribution: TextLeadingDistribution.even,
          ),
        ),
      ),
    );
  }
}

/// A standard divider in shell popup menus.
class ShellMenuDivider extends StatelessWidget {
  const ShellMenuDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      indent: 6,
      endIndent: 6,
      color: context.shellColors.hairlineSoft,
    );
  }
}
