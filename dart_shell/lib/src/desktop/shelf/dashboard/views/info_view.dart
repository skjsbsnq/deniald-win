import 'package:flutter/material.dart' show Scrollbar;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../localization/denial_localizations.dart';
import '../../../../state/system_status.dart';
import '../../../../theme/shell_theme.dart';
import '../info/dashboard_notification_list.dart';
import '../info/info_tool_drawer.dart';
import '../info/profile_header_card.dart';

/// Info page of the dashboard: the emphasized clock block, profile banner,
/// grouped notification center, and the collapsible productivity drawer.
class InfoView extends StatefulWidget {
  const InfoView({super.key});

  @override
  State<InfoView> createState() => _InfoViewState();
}

class _InfoViewState extends State<InfoView> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The scrollbar shares an explicit controller with the scroll view
    // because the shell provides no PrimaryScrollController to adopt.
    return Scrollbar(
      controller: _scrollController,
      child: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: const [
            _DashboardClockBlock(),
            SizedBox(height: 14),
            ProfileHeaderCard(),
            SizedBox(height: 10),
            DashboardNotificationList(),
            SizedBox(height: 10),
            InfoToolDrawer(),
          ],
        ),
      ),
    );
  }
}

/// Display-L emphasized clock with a secondary date line, per the M3E
/// dashboard hero typography. Bare type on the panel surface — the wallpaper
/// accent already tints the page — and driven by the shared minute tick so a
/// parked panel performs no extra work.
class _DashboardClockBlock extends ConsumerWidget {
  const _DashboardClockBlock();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.shellTheme;
    final colors = context.shellColors;
    final now = ref.watch(clockProvider).value ?? DateTime.now();

    return Semantics(
      label:
          '${localizedTime(context, now)} '
          '${localizedLongDate(context, now)}',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              localizedTime(context, now),
              style: theme.text.displayLargeEmphasized.copyWith(
                color: colors.textPrimary,
                height: 1.0,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              localizedLongDate(context, now),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.text.titleMedium.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
