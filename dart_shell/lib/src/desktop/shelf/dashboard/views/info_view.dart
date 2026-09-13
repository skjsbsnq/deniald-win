import 'package:flutter/material.dart' show Scrollbar;
import 'package:flutter/widgets.dart';

import '../info/dashboard_notification_list.dart';
import '../info/info_tool_drawer.dart';
import '../info/profile_header_card.dart';

/// Info page of the dashboard: profile banner, grouped notification center,
/// and the collapsible productivity drawer.
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
