import 'dart:io';

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../launcher/launcher_providers.dart';
import '../../../../../l10n/generated/app_localizations.dart';
import '../../../../localization/denial_localizations.dart';
import '../../../../state/system_identity.dart';
import '../../../../theme/shell_color_scheme.dart';
import '../../../../theme/shell_theme.dart';
import '../../../../theme/tokens.dart';
import '../../../../wallpaper/state/wallpaper_controller.dart';
import '../../../../wallpaper/wallpaper.dart';
import '../../../../wallpaper/widgets/wallpaper_image.dart';

/// Profile banner for the dashboard Info view: the current wallpaper as a
/// cover, the user's face icon straddling the cover edge, account identity,
/// distro badge, and system uptime.
class ProfileHeaderCard extends ConsumerStatefulWidget {
  const ProfileHeaderCard({super.key});

  @override
  ConsumerState<ProfileHeaderCard> createState() => _ProfileHeaderCardState();
}

class _ProfileHeaderCardState extends ConsumerState<ProfileHeaderCard> {
  // A short cover keeps the notification list above the fold on 1080p
  // panels; the avatar straddling its edge carries the visual weight.
  static const double _coverHeight = 80;
  static const double _avatarSize = 92;

  // Cached once per mount; the lookup is not free and the hostname cannot
  // change while the panel is open.
  late final String _hostname = Platform.localHostname;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = context.shellColors;
    final l10n = context.l10n;

    final identity = ref.watch(systemIdentityProvider);
    final assignment = ref.watch(
      wallpaperControllerProvider.select((state) => state.assignment),
    );
    final userName =
        ref.watch(runtimePathsProvider).environment['USER'] ?? 'user';

    final cardRadius = BorderRadius.vertical(
      top: theme.radius(ShellShapeScale.extraLarge),
      bottom: theme.radius(ShellShapeScale.large),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.panelColor(colors.surfaceContainer),
        borderRadius: cardRadius,
        border: Border.all(color: colors.hairlineSoft, width: 1.0),
      ),
      child: ClipRRect(
        borderRadius: cardRadius,
        child: Stack(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildCover(context, theme, colors, assignment.all),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 60, 16, 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$userName@$_hostname',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          height: 1.15,
                          decoration: TextDecoration.none,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (identity.distro != null) ...[
                            _DistroBadge(
                              icon: Icons.computer_rounded,
                              label:
                                  identity.distro!.prettyName ??
                                  identity.distro!.id ??
                                  '',
                            ),
                            const SizedBox(width: 8),
                          ],
                          if (identity.uptimeSeconds != null)
                            _UptimeBadge(
                              label: _formatUptime(
                                l10n,
                                identity.uptimeSeconds!,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Positioned(
              left: 16,
              top: _coverHeight - _avatarSize / 2,
              child: _buildAvatar(theme, colors, identity.avatarPath),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCover(
    BuildContext context,
    ShellThemeData theme,
    ShellColorScheme colors,
    WallpaperResource resource,
  ) {
    return SizedBox(
      height: _coverHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image(
            image: wallpaperImageProvider(
              resource,
              targetPixelSize:
                  const Size(420, 160) * MediaQuery.devicePixelRatioOf(context),
            ),
            fit: BoxFit.cover,
            filterQuality: FilterQuality.low,
            excludeFromSemantics: true,
            errorBuilder: (_, _, _) =>
                ColoredBox(color: colors.surfaceContainerHighest),
          ),
          DecoratedBox(
            decoration: BoxDecoration(color: theme.accent.withAlpha(20)),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar(
    ShellThemeData theme,
    ShellColorScheme colors,
    String? avatarPath,
  ) {
    final Widget content;
    if (avatarPath != null) {
      content = Image.file(
        File(avatarPath),
        fit: BoxFit.cover,
        filterQuality: FilterQuality.low,
        errorBuilder: (_, _, _) => _avatarFallback(colors),
      );
    } else {
      content = _avatarFallback(colors);
    }

    return Container(
      width: _avatarSize,
      height: _avatarSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        // Ring in the card surface color separates the face from the busy
        // wallpaper edge behind it.
        color: theme.panelColor(colors.surfaceContainer),
      ),
      padding: const EdgeInsets.all(3),
      child: ClipOval(child: content),
    );
  }

  Widget _avatarFallback(ShellColorScheme colors) {
    return ColoredBox(
      color: colors.surfaceContainerHighest,
      child: Icon(
        Icons.account_circle_rounded,
        size: _avatarSize - 6,
        color: colors.textSecondary,
      ),
    );
  }

  String _formatUptime(AppLocalizations l10n, double seconds) {
    final total = seconds.round();
    final days = total ~/ 86400;
    final hours = (total % 86400) ~/ 3600;
    final minutes = (total % 3600) ~/ 60;
    if (days > 0) {
      return l10n.uptimeDaysHours(days, hours);
    }
    if (hours > 0) {
      return l10n.uptimeHoursMinutes(hours, minutes);
    }
    return l10n.uptimeMinutes(minutes);
  }
}

class _DistroBadge extends StatelessWidget {
  const _DistroBadge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;

    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: theme.accentPalette.container,
        borderRadius: theme.borderRadius(ShellShapeScale.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: theme.accentPalette.onContainer),
          const SizedBox(width: 5),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: theme.accentPalette.onContainer,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }
}

class _UptimeBadge extends StatelessWidget {
  const _UptimeBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = context.shellTheme;
    final colors = context.shellColors;

    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: theme.borderRadius(ShellShapeScale.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.schedule_rounded, size: 14, color: colors.textSecondary),
          const SizedBox(width: 5),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }
}
