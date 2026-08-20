import 'package:dbus/dbus.dart';
import 'package:denial_dart_shell/src/models/tray_item.dart';
import 'package:denial_dart_shell/src/services/status_notifier_watcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StatusNotifierAddress.parse', () {
    test('parses KDE style bus name only', () {
      final addr = StatusNotifierAddress.parse(':1.42');
      expect(addr.service, ':1.42');
      expect(addr.path, '/StatusNotifierItem');
      expect(addr.toWireString(), ':1.42');
    });

    test('parses KDE style well-known name', () {
      final addr = StatusNotifierAddress.parse(
        'org.kde.StatusNotifierItem-1024-1',
      );
      expect(addr.service, 'org.kde.StatusNotifierItem-1024-1');
      expect(addr.path, '/StatusNotifierItem');
      expect(addr.toWireString(), 'org.kde.StatusNotifierItem-1024-1');
    });

    test('parses Ayatana path-only with sender', () {
      final addr = StatusNotifierAddress.parse(
        '/org/ayatana/NotificationItem/nm_applet',
        sender: ':1.99',
      );
      expect(addr.service, ':1.99');
      expect(addr.path, '/org/ayatana/NotificationItem/nm_applet');
      expect(
        addr.toWireString(),
        ':1.99/org/ayatana/NotificationItem/nm_applet',
      );
    });

    test('parses combined service and custom path', () {
      final addr = StatusNotifierAddress.parse(':1.42/custom/status/path');
      expect(addr.service, ':1.42');
      expect(addr.path, '/custom/status/path');
      expect(addr.toWireString(), ':1.42/custom/status/path');
    });

    test('handles empty and whitespace strings gracefully', () {
      final addr = StatusNotifierAddress.parse('  ', sender: ':1.10');
      expect(addr.service, ':1.10');
      expect(addr.path, '/StatusNotifierItem');
    });

    test(
      'sanitizes malformed paths with trailing/duplicate slashes and invalid chars',
      () {
        expect(
          StatusNotifierAddress.sanitizePath('/org/ayatana/item/'),
          '/org/ayatana/item',
        );
        expect(
          StatusNotifierAddress.sanitizePath('//org///ayatana////item//'),
          '/org/ayatana/item',
        );
        expect(
          StatusNotifierAddress.sanitizePath('/org/app-indicator.1/foo'),
          '/org/app_indicator_1/foo',
        );

        final addr = StatusNotifierAddress.parse(
          '/org/ayatana/NotificationItem/nm_applet/',
          sender: ':1.42',
        );
        expect(addr.path, '/org/ayatana/NotificationItem/nm_applet');
      },
    );
  });

  group('TrayItem and Enums', () {
    test('TrayItemStatus parsing and conversion', () {
      expect(TrayItemStatus.fromString('Passive'), TrayItemStatus.passive);
      expect(TrayItemStatus.fromString('active'), TrayItemStatus.active);
      expect(
        TrayItemStatus.fromString('NeedsAttention'),
        TrayItemStatus.needsAttention,
      );
      expect(
        TrayItemStatus.fromString('needs_attention'),
        TrayItemStatus.needsAttention,
      );
      expect(TrayItemStatus.fromString(null), TrayItemStatus.active);
      expect(TrayItemStatus.fromString('unknown'), TrayItemStatus.active);

      expect(TrayItemStatus.passive.toWireString(), 'Passive');
      expect(TrayItemStatus.active.toWireString(), 'Active');
      expect(TrayItemStatus.needsAttention.toWireString(), 'NeedsAttention');
    });

    test('TrayItemCategory parsing and conversion', () {
      expect(
        TrayItemCategory.fromString('ApplicationStatus'),
        TrayItemCategory.applicationStatus,
      );
      expect(
        TrayItemCategory.fromString('Communications'),
        TrayItemCategory.communications,
      );
      expect(
        TrayItemCategory.fromString('SystemServices'),
        TrayItemCategory.systemServices,
      );
      expect(
        TrayItemCategory.fromString('Hardware'),
        TrayItemCategory.hardware,
      );
      expect(TrayItemCategory.fromString('Other'), TrayItemCategory.other);
      expect(TrayItemCategory.fromString(null), TrayItemCategory.other);
    });

    test('displayLabel preference logic', () {
      const itemWithAll = TrayItem(
        service: ':1.42',
        path: '/StatusNotifierItem',
        id: 'steam',
        title: 'Steam Client',
      );
      expect(itemWithAll.displayLabel, 'Steam Client');

      const itemWithIdOnly = TrayItem(
        service: ':1.42',
        path: '/StatusNotifierItem',
        id: 'steam',
        title: '',
      );
      expect(itemWithIdOnly.displayLabel, 'steam');

      const itemWithServiceOnly = TrayItem(
        service: ':1.42',
        path: '/StatusNotifierItem',
        id: '',
        title: '',
      );
      expect(itemWithServiceOnly.displayLabel, ':1.42');
    });

    test('TrayItem equality and copyWith', () {
      const original = TrayItem(
        service: ':1.42',
        path: '/StatusNotifierItem',
        id: 'nm-applet',
        title: 'Network',
        status: TrayItemStatus.active,
      );

      final copy = original.copyWith(status: TrayItemStatus.needsAttention);
      expect(copy.status, TrayItemStatus.needsAttention);
      expect(copy.id, 'nm-applet');
      expect(copy == original, isFalse);

      final identicalCopy = original.copyWith();
      expect(identicalCopy, equals(original));
      expect(identicalCopy.hashCode, equals(original.hashCode));
    });
  });

  group('StatusNotifierWatcherEndpoint', () {
    test('introspect returns full SNI watcher interface', () {
      final endpoint = StatusNotifierWatcherEndpoint(
        onRegisterItem: (s, sender) async {},
        onRegisterHost: (s, sender) async {},
        onGetItems: () => <String>[':1.42'],
        onGetHostRegistered: () => true,
        onGetProtocolVersion: () => 0,
      );

      final interfaces = endpoint.introspect();
      expect(interfaces, hasLength(1));
      final watcherIface = interfaces.first;
      expect(watcherIface.name, 'org.kde.StatusNotifierWatcher');
      expect(
        watcherIface.methods.map((m) => m.name),
        containsAll(<String>[
          'RegisterStatusNotifierItem',
          'RegisterStatusNotifierHost',
        ]),
      );
      expect(
        watcherIface.signals.map((s) => s.name),
        containsAll(<String>[
          'StatusNotifierItemRegistered',
          'StatusNotifierItemUnregistered',
          'StatusNotifierHostRegistered',
          'StatusNotifierHostUnregistered',
        ]),
      );
      expect(
        watcherIface.properties.map((p) => p.name),
        containsAll(<String>[
          'RegisteredStatusNotifierItems',
          'IsStatusNotifierHostRegistered',
          'ProtocolVersion',
        ]),
      );
    });

    test(
      'handles RegisterStatusNotifierItem and RegisterStatusNotifierHost method calls',
      () async {
        String? registeredItem;
        String? itemSender;
        String? registeredHost;
        String? hostSender;

        final endpoint = StatusNotifierWatcherEndpoint(
          onRegisterItem: (s, sender) async {
            registeredItem = s;
            itemSender = sender;
          },
          onRegisterHost: (s, sender) async {
            registeredHost = s;
            hostSender = sender;
          },
          onGetItems: () => <String>[':1.42'],
          onGetHostRegistered: () => true,
          onGetProtocolVersion: () => 0,
        );

        final itemResp = await endpoint.handleMethodCall(
          DBusMethodCall(
            sender: ':1.55',
            interface: 'org.kde.StatusNotifierWatcher',
            name: 'RegisterStatusNotifierItem',
            values: <DBusValue>[
              const DBusString('/org/ayatana/NotificationItem/nm'),
            ],
          ),
        );
        expect(itemResp, isA<DBusMethodSuccessResponse>());
        expect(registeredItem, '/org/ayatana/NotificationItem/nm');
        expect(itemSender, ':1.55');

        final hostResp = await endpoint.handleMethodCall(
          DBusMethodCall(
            sender: ':1.10',
            interface: 'org.kde.StatusNotifierWatcher',
            name: 'RegisterStatusNotifierHost',
            values: <DBusValue>[
              const DBusString('org.kde.StatusNotifierHost-1234'),
            ],
          ),
        );
        expect(hostResp, isA<DBusMethodSuccessResponse>());
        expect(registeredHost, 'org.kde.StatusNotifierHost-1234');
        expect(hostSender, ':1.10');
      },
    );

    test('handles getProperty and getAllProperties', () async {
      final endpoint = StatusNotifierWatcherEndpoint(
        onRegisterItem: (s, sender) async {},
        onRegisterHost: (s, sender) async {},
        onGetItems: () => <String>[':1.42', ':1.99/path'],
        onGetHostRegistered: () => true,
        onGetProtocolVersion: () => 0,
      );

      final itemsProp = await endpoint.getProperty(
        'org.kde.StatusNotifierWatcher',
        'RegisteredStatusNotifierItems',
      );
      expect(itemsProp, isA<DBusGetPropertyResponse>());
      final itemsArray =
          (itemsProp as DBusGetPropertyResponse).returnValues.first.asVariant()
              as DBusArray;
      expect(itemsArray.children.map((v) => (v as DBusString).value), <String>[
        ':1.42',
        ':1.99/path',
      ]);

      final hostProp = await endpoint.getProperty(
        'org.kde.StatusNotifierWatcher',
        'IsStatusNotifierHostRegistered',
      );
      expect(hostProp, isA<DBusGetPropertyResponse>());
      expect(
        ((hostProp as DBusGetPropertyResponse).returnValues.first.asVariant()
                as DBusBoolean)
            .value,
        isTrue,
      );

      final allProps = await endpoint.getAllProperties(
        'org.kde.StatusNotifierWatcher',
      );
      expect(allProps, isA<DBusGetAllPropertiesResponse>());
      final dict = (allProps as DBusGetAllPropertiesResponse).returnValues.first
          .asStringVariantDict();
      expect(dict.containsKey('RegisteredStatusNotifierItems'), isTrue);
      expect(dict.containsKey('IsStatusNotifierHostRegistered'), isTrue);
      expect(dict.containsKey('ProtocolVersion'), isTrue);
    });

    test('rejects unknown interfaces and methods', () async {
      final endpoint = StatusNotifierWatcherEndpoint(
        onRegisterItem: (s, sender) async {},
        onRegisterHost: (s, sender) async {},
        onGetItems: () => <String>[],
        onGetHostRegistered: () => false,
        onGetProtocolVersion: () => 0,
      );

      final badIface = await endpoint.handleMethodCall(
        DBusMethodCall(
          sender: ':1.1',
          interface: 'org.kde.Unknown',
          name: 'RegisterStatusNotifierItem',
          values: <DBusValue>[const DBusString(':1.42')],
        ),
      );
      expect(
        (badIface as DBusMethodErrorResponse).errorName,
        'org.freedesktop.DBus.Error.UnknownInterface',
      );

      final badMethod = await endpoint.handleMethodCall(
        DBusMethodCall(
          sender: ':1.1',
          interface: 'org.kde.StatusNotifierWatcher',
          name: 'UnknownMethod',
        ),
      );
      expect(
        (badMethod as DBusMethodErrorResponse).errorName,
        'org.freedesktop.DBus.Error.UnknownMethod',
      );
    });
  });
}
