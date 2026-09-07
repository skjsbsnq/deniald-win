import 'package:flutter/widgets.dart';

import '../info/dashboard_notification_list.dart';
import '../info/info_tool_drawer.dart';
import '../info/profile_header_card.dart';

/// Info page of the dashboard: profile banner, grouped notification center,
/// and the collapsible productivity drawer.
class InfoView extends StatelessWidget {
  const InfoView({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
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
    );
  }
}
