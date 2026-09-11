import 'dart:async';

import 'package:dbus/dbus.dart';
import 'package:denial_dart_shell/src/services/media_player_service.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('dispose cancels the refresh timer and the owner subscription', () {
    fakeAsync((async) {
      final client = _FakeDBusClient();
      final service = MediaPlayerService(client: client);

      unawaited(service.start());
      async.flushMicrotasks();
      expect(client.listNamesCalls, 1);
      expect(client.ownerStreamHasListener, isTrue);

      async.elapse(const Duration(minutes: 1));
      async.flushMicrotasks();
      expect(client.listNamesCalls, 2);

      unawaited(service.dispose());
      async.flushMicrotasks();
      // StreamSubscription.cancel() resolves on the real event loop, but its
      // effect is immediate: the owner listener is already detached and the
      // periodic refresh timer is already cancelled.
      expect(client.ownerStreamHasListener, isFalse);

      async.elapse(const Duration(minutes: 5));
      async.flushMicrotasks();
      expect(client.listNamesCalls, 2);
    });
  });

  test('a second start() on a live service is a no-op', () {
    fakeAsync((async) {
      final client = _FakeDBusClient();
      final service = MediaPlayerService(client: client);

      unawaited(service.start());
      unawaited(service.start());
      async.flushMicrotasks();
      expect(client.listNamesCalls, 1);

      unawaited(service.dispose());
      async.flushMicrotasks();
    });
  });

  test(
    'the service is released once the last playback listener leaves',
    () async {
      final clients = <_FakeDBusClient>[];
      final container = ProviderContainer.test(
        overrides: [
          mediaPlayerServiceProvider.overrideWith((ref) {
            final client = _FakeDBusClient();
            clients.add(client);
            final service = MediaPlayerService(client: client);
            ref.onDispose(() => unawaited(service.dispose()));
            return service;
          }),
        ],
      );
      addTearDown(container.dispose);

      final first = container.listen(
        mediaPlaybackProvider,
        (previous, next) {},
      );
      await _flushEvents();
      expect(clients, hasLength(1));
      expect(clients.single.listNamesCalls, 1);
      expect(clients.single.ownerStreamHasListener, isTrue);

      first.close();
      await _until(() => clients.single.closed);
      expect(clients.single.ownerStreamHasListener, isFalse);

      // A returning consumer gets a fresh service that starts again.
      final second = container.listen(
        mediaPlaybackProvider,
        (previous, next) {},
      );
      addTearDown(second.close);
      await _until(() => clients.length > 1);
      await _flushEvents();
      expect(clients.last.closed, isFalse);
      expect(clients.last.listNamesCalls, 1);
    },
  );
}

/// Lets scheduled provider disposal and service futures settle.
Future<void> _flushEvents() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<void> _until(bool Function() condition) async {
  for (var i = 0; i < 50 && !condition(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _FakeDBusClient extends DBusClient {
  _FakeDBusClient() : super(DBusAddress('unix:path=/dev/null'));

  final StreamController<DBusNameOwnerChangedEvent> _ownerEvents =
      StreamController<DBusNameOwnerChangedEvent>.broadcast();
  var listNamesCalls = 0;
  var closed = false;

  bool get ownerStreamHasListener => _ownerEvents.hasListener;

  @override
  Stream<DBusNameOwnerChangedEvent> get nameOwnerChanged => _ownerEvents.stream;

  @override
  Future<List<String>> listNames() async {
    listNamesCalls++;
    return const <String>[];
  }

  @override
  Future<void> close() async {
    closed = true;
    await _ownerEvents.close();
  }
}
