import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../localization/denial_localizations.dart';
import '../../theme/shell_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/shell_cursor.dart';

/// Height of the Settings search capsule (`02-VISUAL-SPEC.md` §3.1).
const double settingsSearchBarHeight = 56;

/// Identifies the search capsule for tests and layout asserts.
const settingsSearchBarKey = ValueKey<String>('settings-search-bar');

/// Horizontal inset of the search capsule contents.
///
/// The geometry table fixes the capsule height, radius, icon, and text roles
/// but not its inset; 16 is the shell's governing edge inset (§2.2) and keeps
/// the capsule aligned with the navigation cards below it.
const double settingsSearchBarInset = 16;

/// The Android 17-style search capsule that heads the Settings navigation.
///
/// S02 ships the appearance only. [onTap] stays `null`, and a capsule without
/// a handler is deliberately not clickable, not focusable, and exposes no tap
/// action, so the un-wired placeholder cannot be reached from the keyboard.
/// S07 supplies [onTap] and upgrades the semantics to a real search field.
class SettingsSearchBar extends StatelessWidget {
  const SettingsSearchBar({this.onTap, super.key});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = ShellTheme.of(context);
    final enabled = onTap != null;
    final hint = l10n.settingsSearchHint;
    final capsule = DecoratedBox(
      decoration: BoxDecoration(
        color: theme.cardColor(context.shellColors.surfaceContainerHigh),
        borderRadius: theme.borderRadius(ShellShapeScale.full),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: settingsSearchBarInset),
        child: Row(
          children: <Widget>[
            Icon(
              Icons.search_rounded,
              size: 24,
              color: context.shellColors.textSecondary,
            ),
            const SizedBox(width: settingsSearchBarInset),
            Expanded(
              child: Text(
                hint,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ShellText.settingsSearchHint.copyWith(
                  color: context.shellColors.textTertiary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return SizedBox(
      height: settingsSearchBarHeight,
      child: Semantics(
        key: settingsSearchBarKey,
        container: true,
        excludeSemantics: true,
        label: hint,
        button: enabled,
        child: enabled
            ? FocusableActionDetector(
                mouseCursor: ShellMouseCursors.link,
                shortcuts: const <ShortcutActivator, Intent>{
                  SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
                  SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
                },
                actions: <Type, Action<Intent>>{
                  ActivateIntent: CallbackAction<ActivateIntent>(
                    onInvoke: (_) {
                      onTap!();
                      return null;
                    },
                  ),
                },
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onTap,
                  child: capsule,
                ),
              )
            : capsule,
      ),
    );
  }
}
