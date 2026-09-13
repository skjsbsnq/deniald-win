import '../../local_apps/local_flutter_application.dart';
import 'desktop_app.dart';

enum HomeGridItemType {
  clock,
  batteryDischarge,
  app,

  /// MD3E blob widget family (T23): weather snapshot, compact battery, and
  /// the quick-action pill row. Purely additive — persisted layouts carry
  /// item ids as strings, so older saves keep resolving exactly as before.
  weather,
  battery,
  quickActions,
}

class HomeLayoutSlot {
  const HomeLayoutSlot({required this.id, this.colSpan, this.rowSpan});

  final String id;
  final int? colSpan;
  final int? rowSpan;
}

class HomeGridItem {
  const HomeGridItem._({
    required this.type,
    required this.id,
    required this.colSpan,
    required this.rowSpan,
    required this.app,
    required this.localApp,
  });

  factory HomeGridItem.clock({
    int colSpan = defaultClockColSpan,
    int rowSpan = defaultClockRowSpan,
  }) {
    return HomeGridItem._(
      type: HomeGridItemType.clock,
      id: 'widget:clock',
      colSpan: colSpan.clamp(clockMinColSpan, clockMaxColSpan).toInt(),
      rowSpan: rowSpan.clamp(clockMinRowSpan, clockMaxRowSpan).toInt(),
      app: null,
      localApp: null,
    );
  }

  factory HomeGridItem.app(DesktopApp desktopApp) {
    return HomeGridItem._(
      type: HomeGridItemType.app,
      id: 'app:${desktopApp.id}',
      colSpan: 1,
      rowSpan: 1,
      app: desktopApp,
      localApp: null,
    );
  }

  factory HomeGridItem.localApp(LocalFlutterApplication localApp) {
    return HomeGridItem._(
      type: HomeGridItemType.app,
      id: 'local:${localApp.id}',
      colSpan: 1,
      rowSpan: 1,
      app: null,
      localApp: localApp,
    );
  }

  factory HomeGridItem.batteryDischarge({
    int colSpan = defaultBatteryDischargeColSpan,
    int rowSpan = defaultBatteryDischargeRowSpan,
  }) {
    return HomeGridItem._(
      type: HomeGridItemType.batteryDischarge,
      id: 'widget:battery-discharge',
      colSpan: colSpan
          .clamp(batteryDischargeMinColSpan, batteryDischargeMaxColSpan)
          .toInt(),
      rowSpan: rowSpan
          .clamp(batteryDischargeMinRowSpan, batteryDischargeMaxRowSpan)
          .toInt(),
      app: null,
      localApp: null,
    );
  }

  factory HomeGridItem.weather({
    int colSpan = defaultWeatherColSpan,
    int rowSpan = defaultWeatherRowSpan,
  }) {
    return HomeGridItem._(
      type: HomeGridItemType.weather,
      id: 'widget:weather',
      colSpan: colSpan.clamp(weatherMinColSpan, weatherMaxColSpan).toInt(),
      rowSpan: rowSpan.clamp(weatherMinRowSpan, weatherMaxRowSpan).toInt(),
      app: null,
      localApp: null,
    );
  }

  factory HomeGridItem.battery({
    int colSpan = defaultBatteryColSpan,
    int rowSpan = defaultBatteryRowSpan,
  }) {
    return HomeGridItem._(
      type: HomeGridItemType.battery,
      id: 'widget:battery',
      colSpan: colSpan.clamp(batteryMinColSpan, batteryMaxColSpan).toInt(),
      rowSpan: rowSpan.clamp(batteryMinRowSpan, batteryMaxRowSpan).toInt(),
      app: null,
      localApp: null,
    );
  }

  factory HomeGridItem.quickActions({
    int colSpan = defaultQuickActionsColSpan,
    int rowSpan = defaultQuickActionsRowSpan,
  }) {
    return HomeGridItem._(
      type: HomeGridItemType.quickActions,
      id: 'widget:quick-actions',
      colSpan: colSpan
          .clamp(quickActionsMinColSpan, quickActionsMaxColSpan)
          .toInt(),
      rowSpan: rowSpan
          .clamp(quickActionsMinRowSpan, quickActionsMaxRowSpan)
          .toInt(),
      app: null,
      localApp: null,
    );
  }

  static const int defaultClockColSpan = 2;
  static const int defaultClockRowSpan = 1;
  static const int clockMinColSpan = 2;
  static const int clockMaxColSpan = 4;
  static const int clockMinRowSpan = 1;
  static const int clockMaxRowSpan = 3;
  static const int defaultBatteryDischargeColSpan = 4;
  static const int defaultBatteryDischargeRowSpan = 2;
  static const int batteryDischargeMinColSpan = 2;
  static const int batteryDischargeMaxColSpan = 4;
  static const int batteryDischargeMinRowSpan = 1;
  static const int batteryDischargeMaxRowSpan = 3;
  static const int defaultWeatherColSpan = 2;
  static const int defaultWeatherRowSpan = 1;
  static const int weatherMinColSpan = 2;
  static const int weatherMaxColSpan = 4;
  static const int weatherMinRowSpan = 1;
  static const int weatherMaxRowSpan = 2;
  static const int defaultBatteryColSpan = 2;
  static const int defaultBatteryRowSpan = 1;
  static const int batteryMinColSpan = 1;
  static const int batteryMaxColSpan = 2;
  static const int batteryMinRowSpan = 1;
  static const int batteryMaxRowSpan = 2;
  static const int defaultQuickActionsColSpan = 4;
  static const int defaultQuickActionsRowSpan = 1;
  static const int quickActionsMinColSpan = 3;
  static const int quickActionsMaxColSpan = 4;
  static const int quickActionsMinRowSpan = 1;
  static const int quickActionsMaxRowSpan = 1;

  final HomeGridItemType type;
  final String id;
  final int colSpan;
  final int rowSpan;
  final DesktopApp? app;
  final LocalFlutterApplication? localApp;

  bool get resizable => type != HomeGridItemType.app;

  int get minColSpan {
    return switch (type) {
      HomeGridItemType.clock => clockMinColSpan,
      HomeGridItemType.batteryDischarge => batteryDischargeMinColSpan,
      HomeGridItemType.weather => weatherMinColSpan,
      HomeGridItemType.battery => batteryMinColSpan,
      HomeGridItemType.quickActions => quickActionsMinColSpan,
      HomeGridItemType.app => 1,
    };
  }

  int get maxColSpan {
    return switch (type) {
      HomeGridItemType.clock => clockMaxColSpan,
      HomeGridItemType.batteryDischarge => batteryDischargeMaxColSpan,
      HomeGridItemType.weather => weatherMaxColSpan,
      HomeGridItemType.battery => batteryMaxColSpan,
      HomeGridItemType.quickActions => quickActionsMaxColSpan,
      HomeGridItemType.app => 1,
    };
  }

  int get minRowSpan {
    return switch (type) {
      HomeGridItemType.clock => clockMinRowSpan,
      HomeGridItemType.batteryDischarge => batteryDischargeMinRowSpan,
      HomeGridItemType.weather => weatherMinRowSpan,
      HomeGridItemType.battery => batteryMinRowSpan,
      HomeGridItemType.quickActions => quickActionsMinRowSpan,
      HomeGridItemType.app => 1,
    };
  }

  int get maxRowSpan {
    return switch (type) {
      HomeGridItemType.clock => clockMaxRowSpan,
      HomeGridItemType.batteryDischarge => batteryDischargeMaxRowSpan,
      HomeGridItemType.weather => weatherMaxRowSpan,
      HomeGridItemType.battery => batteryMaxRowSpan,
      HomeGridItemType.quickActions => quickActionsMaxRowSpan,
      HomeGridItemType.app => 1,
    };
  }

  HomeGridItem resize({required int colSpan, required int rowSpan}) {
    if (!resizable) {
      return this;
    }
    return switch (type) {
      HomeGridItemType.clock => HomeGridItem.clock(
        colSpan: colSpan,
        rowSpan: rowSpan,
      ),
      HomeGridItemType.batteryDischarge => HomeGridItem.batteryDischarge(
        colSpan: colSpan,
        rowSpan: rowSpan,
      ),
      HomeGridItemType.weather => HomeGridItem.weather(
        colSpan: colSpan,
        rowSpan: rowSpan,
      ),
      HomeGridItemType.battery => HomeGridItem.battery(
        colSpan: colSpan,
        rowSpan: rowSpan,
      ),
      HomeGridItemType.quickActions => HomeGridItem.quickActions(
        colSpan: colSpan,
        rowSpan: rowSpan,
      ),
      HomeGridItemType.app => this,
    };
  }
}
