import '../../local_apps/local_flutter_application.dart';
import 'desktop_app.dart';

enum HomeGridItemType { clock, batteryDischarge, app }

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
    required this.minColSpan,
    required this.maxColSpan,
    required this.minRowSpan,
    required this.maxRowSpan,
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
      minColSpan: clockMinColSpan,
      maxColSpan: clockMaxColSpan,
      minRowSpan: clockMinRowSpan,
      maxRowSpan: clockMaxRowSpan,
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
      minColSpan: 1,
      maxColSpan: 1,
      minRowSpan: 1,
      maxRowSpan: 1,
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
      minColSpan: 1,
      maxColSpan: 1,
      minRowSpan: 1,
      maxRowSpan: 1,
      app: null,
      localApp: localApp,
    );
  }

  /// An application tile the user placed on the desktop start menu's pin board.
  ///
  /// The only difference from [HomeGridItem.app] is the span ceiling: the pin
  /// board offers Windows 10's four tile sizes, while the mobile home screen
  /// keeps every application at one cell. Both bounds live on the instance so
  /// widening one board cannot widen the other.
  factory HomeGridItem.pinnedApp(
    DesktopApp desktopApp, {
    int colSpan = pinnedDefaultColSpan,
    int rowSpan = pinnedDefaultRowSpan,
  }) {
    return HomeGridItem._(
      type: HomeGridItemType.app,
      id: 'app:${desktopApp.id}',
      colSpan: colSpan.clamp(pinnedMinColSpan, pinnedMaxColSpan).toInt(),
      rowSpan: rowSpan.clamp(pinnedMinRowSpan, pinnedMaxRowSpan).toInt(),
      minColSpan: pinnedMinColSpan,
      maxColSpan: pinnedMaxColSpan,
      minRowSpan: pinnedMinRowSpan,
      maxRowSpan: pinnedMaxRowSpan,
      app: desktopApp,
      localApp: null,
    );
  }

  /// A shell-hosted application on the pin board. See [HomeGridItem.pinnedApp].
  factory HomeGridItem.pinnedLocalApp(
    LocalFlutterApplication localApp, {
    int colSpan = pinnedDefaultColSpan,
    int rowSpan = pinnedDefaultRowSpan,
  }) {
    return HomeGridItem._(
      type: HomeGridItemType.app,
      id: 'local:${localApp.id}',
      colSpan: colSpan.clamp(pinnedMinColSpan, pinnedMaxColSpan).toInt(),
      rowSpan: rowSpan.clamp(pinnedMinRowSpan, pinnedMaxRowSpan).toInt(),
      minColSpan: pinnedMinColSpan,
      maxColSpan: pinnedMaxColSpan,
      minRowSpan: pinnedMinRowSpan,
      maxRowSpan: pinnedMaxRowSpan,
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
      minColSpan: batteryDischargeMinColSpan,
      maxColSpan: batteryDischargeMaxColSpan,
      minRowSpan: batteryDischargeMinRowSpan,
      maxRowSpan: batteryDischargeMaxRowSpan,
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
  static const int pinnedDefaultColSpan = 2;
  static const int pinnedDefaultRowSpan = 2;
  static const int pinnedMinColSpan = 1;
  static const int pinnedMaxColSpan = 4;
  static const int pinnedMinRowSpan = 1;
  static const int pinnedMaxRowSpan = 4;

  final HomeGridItemType type;
  final String id;
  final int colSpan;
  final int rowSpan;
  final int minColSpan;
  final int maxColSpan;
  final int minRowSpan;
  final int maxRowSpan;
  final DesktopApp? app;
  final LocalFlutterApplication? localApp;

  /// Whether either axis has room to move. Deriving this from the bounds rather
  /// than from [type] is what lets one board offer four tile sizes for an
  /// application while another pins every application to a single cell.
  bool get resizable => maxColSpan > minColSpan || maxRowSpan > minRowSpan;

  HomeGridItem resize({required int colSpan, required int rowSpan}) {
    if (!resizable) {
      return this;
    }
    return HomeGridItem._(
      type: type,
      id: id,
      colSpan: colSpan.clamp(minColSpan, maxColSpan).toInt(),
      rowSpan: rowSpan.clamp(minRowSpan, maxRowSpan).toInt(),
      minColSpan: minColSpan,
      maxColSpan: maxColSpan,
      minRowSpan: minRowSpan,
      maxRowSpan: maxRowSpan,
      app: app,
      localApp: localApp,
    );
  }
}
