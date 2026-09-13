import 'package:flutter/material.dart';

import '../../localization/denial_localizations.dart';
import '../../theme/shell_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/shell_expressive_surface.dart';

/// The launcher entry button on the left edge of the shelf.
class ShelfLauncherButton extends StatelessWidget {
  const ShelfLauncherButton({this.onPressed, super.key});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.shellColors;
    final label = context.l10n.shelfOpenLauncher;

    return ShellExpressiveSurface(
      onPressed: onPressed,
      shape: ShellShapeScale.full,
      width: 40,
      height: 40,
      tooltip: label,
      semanticLabel: label,
      child: Icon(
        Icons.apps_rounded,
        size: 28,
        color: colors.textPrimary,
      ),
    );
  }
}
