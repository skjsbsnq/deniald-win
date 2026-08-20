import 'dart:async';
import 'dart:ui' as ui;

import 'package:denial_dart_shell/src/desktop/desktop_dashboard_wifi_card.dart';
import 'package:denial_dart_shell/src/localization/denial_localizations.dart';
import 'package:denial_dart_shell/src/services/network_manager_service.dart';
import 'package:denial_dart_shell/src/state/network_connectivity.dart';
import 'package:denial_dart_shell/src/theme/tokens.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('card renders title, power toggle, scan and refresh buttons', (
    tester,
  ) async {
    final backend = _FakeNetworkBackend(
      _snapshot(
        networks: <WifiNetwork>[
          _network('Home-5G', strength: 80, security: WifiSecurity.wpaPersonal),
        ],
      ),
    );
    addTearDown(backend.dispose);
    final container = ProviderContainer.test(
      overrides: <Override>[
        networkManagerServiceProvider.overrideWithValue(backend),
      ],
    );

    await tester.pumpWidget(_host(container));
    await tester.pump();

    expect(find.text('Wi-Fi'), findsOneWidget);
    expect(find.text('Home-5G'), findsOneWidget);
    expect(find.byIcon(Icons.power_settings_new_rounded), findsOneWidget);
    expect(find.byIcon(Icons.radar_rounded), findsOneWidget);
    expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('scan button is disabled when Wi-Fi is disabled', (tester) async {
    final backend = _FakeNetworkBackend(
      _snapshot(networks: const <WifiNetwork>[], enabled: false),
    );
    addTearDown(backend.dispose);
    final container = ProviderContainer.test(
      overrides: <Override>[
        networkManagerServiceProvider.overrideWithValue(backend),
      ],
    );

    await tester.pumpWidget(_host(container));
    await tester.pump();

    expect(find.text('Wi-Fi is off'), findsOneWidget);

    final scanButtonSemantics = tester.getSemantics(
      find.bySemanticsLabel('Scan Wi-Fi networks'),
    );
    expect(
      scanButtonSemantics.getSemanticsData().hasAction(ui.SemanticsAction.tap),
      isFalse,
    );

    await tester.tap(find.bySemanticsLabel('Turn on Wi-Fi'));
    await tester.pump();

    expect(backend.setWirelessCalls, 1);
    expect(backend.lastEnabledValue, isTrue);
  });

  testWidgets(
    'displays error notice when error is non-null and clears on tap',
    (tester) async {
      final backend = _FakeNetworkBackend(
        _snapshot(networks: const <WifiNetwork>[]),
      );
      addTearDown(backend.dispose);
      final container = ProviderContainer.test(
        overrides: <Override>[
          networkManagerServiceProvider.overrideWithValue(backend),
        ],
      );

      await tester.pumpWidget(_host(container));
      await tester.pump();

      container.read(networkConnectivityProvider.notifier).state = container
          .read(networkConnectivityProvider)
          .copyWith(error: 'Connection timeout failure');
      await tester.pump();

      expect(find.text('Connection timeout failure'), findsOneWidget);

      await tester.tap(find.text('Connection timeout failure'));
      await tester.pump();

      expect(find.text('Connection timeout failure'), findsNothing);
    },
  );

  testWidgets(
    'clicking saved network connects, connected disconnects, secure prompts password',
    (tester) async {
      final backend = _FakeNetworkBackend(
        _snapshot(
          networks: <WifiNetwork>[
            _network('SavedNet', savedConnectionPath: '/saved/1'),
            _network('ConnectedNet', connected: true),
            _network('EncryptedNet', security: WifiSecurity.wpaPersonal),
          ],
        ),
      );
      addTearDown(backend.dispose);
      final container = ProviderContainer.test(
        overrides: <Override>[
          networkManagerServiceProvider.overrideWithValue(backend),
        ],
      );

      await tester.pumpWidget(_host(container));
      await tester.pump();

      expect(find.text('SavedNet'), findsOneWidget);
      expect(find.text('ConnectedNet'), findsOneWidget);
      expect(find.text('EncryptedNet'), findsOneWidget);

      await tester.tap(find.text('SavedNet'));
      await tester.pump();
      expect(backend.connectCalls, 1);

      await tester.tap(find.bySemanticsLabel('Disconnect from ConnectedNet'));
      await tester.pump();
      expect(backend.disconnectCalls, 1);

      await tester.tap(find.text('EncryptedNet'));
      await tester.pump();

      expect(find.byType(EditableText), findsOneWidget);
      expect(find.text('Password for EncryptedNet'), findsOneWidget);

      await tester.enterText(find.byType(EditableText), 'secret-password-123');
      await tester.tap(find.text('Connect'));
      await tester.pump();

      expect(backend.connectCalls, 2);
      expect(backend.passwordMatched, isTrue);
      expect(find.byType(EditableText), findsNothing);
    },
  );

  testWidgets('displays empty state when no networks found', (tester) async {
    final backend = _FakeNetworkBackend(
      _snapshot(networks: const <WifiNetwork>[]),
    );
    addTearDown(backend.dispose);
    final container = ProviderContainer.test(
      overrides: <Override>[
        networkManagerServiceProvider.overrideWithValue(backend),
      ],
    );

    await tester.pumpWidget(_host(container));
    await tester.pump();

    expect(find.text('No Wi-Fi networks found'), findsOneWidget);
  });
}

Widget _host(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: DenialLocalizationScope(
      child: MediaQuery(
        data: const MediaQueryData(size: Size(470, 300)),
        child: DefaultTextStyle(
          style: ShellText.base,
          child: const SizedBox(
            width: 470,
            height: 300,
            child: DesktopDashboardWifiCard(),
          ),
        ),
      ),
    ),
  );
}

class _FakeNetworkBackend implements NetworkManagerBackend {
  _FakeNetworkBackend(this._current);

  final StreamController<NetworkManagerSnapshot> _snapshots =
      StreamController<NetworkManagerSnapshot>.broadcast(sync: true);
  NetworkManagerSnapshot _current;
  int connectCalls = 0;
  int disconnectCalls = 0;
  int forgetCalls = 0;
  int setWirelessCalls = 0;
  bool? lastEnabledValue;
  bool passwordMatched = false;

  @override
  NetworkManagerSnapshot get currentSnapshot => _current;

  @override
  Stream<NetworkManagerSnapshot> get snapshots => _snapshots.stream;

  void emit(NetworkManagerSnapshot snapshot) {
    _current = snapshot;
    _snapshots.add(snapshot);
  }

  @override
  Future<void> start() async => emit(_current);

  @override
  Future<void> refresh() async => emit(_current);

  @override
  Future<void> setWirelessEnabled(bool enabled) async {
    setWirelessCalls += 1;
    lastEnabledValue = enabled;
    emit(_snapshot(networks: _current.networks, enabled: enabled));
  }

  @override
  Future<void> requestScan() async {}

  @override
  Future<void> connect(WifiNetwork network, {String? password}) async {
    connectCalls += 1;
    passwordMatched = password == 'secret-password-123';
  }

  @override
  Future<void> disconnect() async {
    disconnectCalls += 1;
  }

  @override
  Future<void> forget(WifiNetwork network) async {
    forgetCalls += 1;
  }

  @override
  Future<void> dispose() => _snapshots.close();
}

NetworkManagerSnapshot _snapshot({
  required List<WifiNetwork> networks,
  bool hasAdapter = true,
  bool enabled = true,
}) {
  return NetworkManagerSnapshot(
    serviceAvailable: true,
    wifiDeviceAvailable: hasAdapter,
    wirelessHardwareEnabled: true,
    wirelessEnabled: enabled,
    status: enabled
        ? NetworkConnectivityStatus.online
        : NetworkConnectivityStatus.disabled,
    networks: networks,
    activeConnectionPath: networks.any((network) => network.connected)
        ? '/active/1'
        : null,
    devicePath: hasAdapter ? '/device/1' : null,
    lastScan: 1,
    radioPermission: NetworkPermission.allowed,
    controlPermission: NetworkPermission.allowed,
    modifyPermission: NetworkPermission.allowed,
  );
}

WifiNetwork _network(
  String ssid, {
  WifiSecurity security = WifiSecurity.open,
  bool connected = false,
  String? savedConnectionPath,
  int strength = 72,
}) {
  return WifiNetwork(
    ssid: ssid,
    ssidBytes: ssid.codeUnits,
    security: security,
    strength: strength,
    frequency: 5180,
    devicePath: '/device/1',
    accessPointPath: '/access/$ssid',
    savedConnectionPath: savedConnectionPath,
    connected: connected,
    available: true,
  );
}
