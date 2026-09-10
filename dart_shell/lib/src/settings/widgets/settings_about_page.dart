import 'package:flutter/material.dart';

import '../../localization/denial_localizations.dart';
import '../../theme/shell_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/denial_wordmark.dart';
import 'settings_controls.dart';

const settingsAboutWordmarkKey = ValueKey<String>('settings-about-wordmark');

/// About page, converged onto the new page skeleton (`SettingsPageLayout`).
///
/// The hero content (wordmark, tagline, belief, description and credit) keeps
/// its data source; the page title now lives in the shared page header, so the
/// body no longer repeats a title of its own.
class SettingsAboutPage extends StatelessWidget {
  const SettingsAboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Semantics(
      container: true,
      label: l10n.settingsAboutPageSemanticsLabel,
      child: SettingsPageLayout(
        icon: Icons.info_outline_rounded,
        eyebrow: l10n.settingsAboutPageSemanticsLabel,
        title: l10n.settingsNavigationAbout,
        children: const <Widget>[
          SettingsCardGroup(children: <Widget>[_AboutHero()]),
          SettingsCardGroup(children: <Widget>[_AboutDescription()]),
          SettingsCardGroup(children: <Widget>[_AboutCredit()]),
        ],
      ),
    );
  }
}

class _AboutHero extends StatelessWidget {
  const _AboutHero();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final accent = ShellTheme.of(context).accent;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 26),
      child: Column(
        children: [
          ConstrainedBox(
            key: settingsAboutWordmarkKey,
            constraints: const BoxConstraints(maxWidth: 420),
            child: AspectRatio(
              aspectRatio: denialWordmarkAspectRatio,
              child: DenialWordmark(
                semanticsLabel: l10n.settingsAboutLogoSemanticsLabel,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            l10n.settingsAboutTagline,
            textAlign: TextAlign.center,
            style: ShellText.settingsPageTitleCollapsed.copyWith(
              color: context.shellColors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          DecoratedBox(
            decoration: BoxDecoration(
              color: accent.withAlpha(26),
              borderRadius: context.shellTheme.borderRadius(
                ShellShapeScale.full,
              ),
              border: Border.all(color: accent.withAlpha(76)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              child: Text(
                l10n.settingsAboutBelief,
                textAlign: TextAlign.center,
                style: ShellText.cardTitle.copyWith(color: accent),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AboutDescription extends StatelessWidget {
  const _AboutDescription();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final bodyStyle = ShellText.settingsRowSupport.copyWith(
      color: context.shellColors.textSecondary,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
      child: Column(
        children: [
          Text(
            l10n.settingsAboutDescription,
            textAlign: TextAlign.center,
            style: bodyStyle,
          ),
          const SizedBox(height: 12),
          Text(
            l10n.settingsAboutArchitecture,
            textAlign: TextAlign.center,
            style: bodyStyle,
          ),
        ],
      ),
    );
  }
}

class _AboutCredit extends StatelessWidget {
  const _AboutCredit();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final accent = ShellTheme.of(context).accent;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
      child: Column(
        children: [
          Icon(Icons.person_outline_rounded, color: accent, size: 24),
          const SizedBox(height: 10),
          Text(
            l10n.settingsAboutCreditLabel,
            textAlign: TextAlign.center,
            style: ShellText.settingsRowSupport.copyWith(
              color: context.shellColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          SelectableText(
            l10n.settingsAboutCreditName,
            textAlign: TextAlign.center,
            style: ShellText.settingsPageTitleCollapsed.copyWith(
              color: context.shellColors.textPrimary,
            ),
          ),
          const SizedBox(height: 9),
          Text(
            l10n.settingsAboutCollaboration,
            textAlign: TextAlign.center,
            style: ShellText.settingsRowSupport.copyWith(
              color: context.shellColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
