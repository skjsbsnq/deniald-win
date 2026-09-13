import 'dart:async';

import 'package:denial_dart_shell/l10n/generated/app_localizations.dart';
import 'package:denial_dart_shell/src/desktop/desktop_workspace.dart';
import 'package:denial_dart_shell/src/desktop/shelf/shelf_media_card.dart';
import 'package:denial_dart_shell/src/desktop/shelf/unified_tray_bubble.dart';
import 'package:denial_dart_shell/src/desktop/shelf/unified_tray_button.dart';
import 'package:denial_dart_shell/src/models/battery_status.dart';
import 'package:denial_dart_shell/src/services/media_player_service.dart';
import 'package:denial_dart_shell/src/state/bluetooth.dart';
import 'package:denial_dart_shell/src/state/desktop_notifications.dart';
import 'package:denial_dart_shell/src/state/network_connectivity.dart';
import 'package:denial_dart_shell/src/state/quick_settings.dart';
import 'package:denial_dart_shell/src/state/system_status.dart';
import 'package:denial_dart_shell/src/theme/shell_theme.dart';
import 'package:denial_dart_shell/src/widgets/shade/quick_settings_tiles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('tray bubble shows no media section while no player is active', (
    tester,
  ) async {
    final service = _FakeMediaPlayerService();
    await tester.pumpWidget(
      _mediaScope(
        service: service,
        child: _wrap(const UnifiedTrayBubble(visible: true, shelfHeight: 56)),
      ),
    );
    service.emit(MprisPlaybackState.unavailable());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // The media card leaves no placeholder: the quick settings tiles still
    // sit directly below the status chips.
    expect(find.byType(ShelfMediaCard), findsNothing);
    expect(find.byType(QuickSettingsTiles), findsOneWidget);
  });

  testWidgets(
    'tray bubble mounts the media card between chips and tiles while playing',
    (tester) async {
      final service = _FakeMediaPlayerService();
      await tester.pumpWidget(
        _mediaScope(
          service: service,
          child: _wrap(const UnifiedTrayBubble(visible: true, shelfHeight: 56)),
        ),
      );
      service.emit(_playback());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(ShelfMediaCard), findsOneWidget);
      expect(find.text('Test Track'), findsOneWidget);
      expect(find.text('Test Artist'), findsOneWidget);
      expect(
        tester.getTopLeft(find.byType(ShelfMediaCard)).dy,
        lessThan(tester.getTopLeft(find.byType(QuickSettingsTiles)).dy),
      );

      // Transport keys dispatch through the player service.
      await tester.tap(find.byIcon(Icons.skip_previous_rounded));
      await tester.tap(find.byIcon(Icons.pause_rounded));
      await tester.tap(find.byIcon(Icons.skip_next_rounded));
      expect(
        service.calls,
        containsAllInOrder(<String>['previous', 'playPause', 'next']),
      );

      // Pausing swaps the transport glyph; going unavailable removes the card.
      service.emit(_playback(status: MprisPlaybackStatus.paused));
      await tester.pump();
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      service.emit(MprisPlaybackState.unavailable());
      await tester.pump();
      expect(find.byType(ShelfMediaCard), findsNothing);
    },
  );

  testWidgets('media card dispatches its control callbacks', (tester) async {
    var previous = 0;
    var playPause = 0;
    var next = 0;
    await tester.pumpWidget(
      ProviderScope(
        child: _wrap(
          Center(
            child: ShelfMediaCard(
              playback: _playback(),
              now: DateTime(2026, 9, 9),
              onPrevious: () => previous += 1,
              onPlayPause: () => playPause += 1,
              onNext: () => next += 1,
              width: 380,
              height: 168,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.skip_previous_rounded));
    await tester.tap(find.byIcon(Icons.pause_rounded));
    await tester.tap(find.byIcon(Icons.skip_next_rounded));
    expect((previous, playPause, next), (1, 1, 1));
  });

  testWidgets('shelf media popup still renders the shared card', (
    tester,
  ) async {
    final media = StreamController<MprisPlaybackState>.broadcast();
    addTearDown(media.close);
    await tester.pumpWidget(
      _mediaScope(
        service: _FakeMediaPlayerService(),
        mediaStream: media.stream,
        child: _wrap(
          const UnifiedTrayButton(expanded: false, onPressed: _noop),
          disableAnimations: true,
        ),
      ),
    );
    media.add(_playback());
    await tester.pump();

    // The media button mounts only while a player reports an active track.
    expect(find.byIcon(Icons.graphic_eq_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.graphic_eq_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(ShelfMediaCard), findsOneWidget);
    expect(find.text('Test Track'), findsOneWidget);
  });
}

void _noop() {}

MprisPlaybackState _playback({
  MprisPlaybackStatus status = MprisPlaybackStatus.playing,
}) {
  return MprisPlaybackState(
    serviceName: 'org.mpris.MediaPlayer2.fake',
    identity: 'Fake Player',
    title: 'Test Track',
    artists: const <String>['Test Artist'],
    album: 'Test Album',
    artUrl: '',
    length: const Duration(minutes: 3),
    position: const Duration(minutes: 1),
    observedAt: DateTime(2026, 9, 9),
    status: status,
    canGoNext: true,
    canGoPrevious: true,
    canPlay: true,
    canPause: true,
  );
}

Widget _mediaScope({
  required _FakeMediaPlayerService service,
  required Widget child,
  Stream<MprisPlaybackState>? mediaStream,
}) {
  return ProviderScope(
    overrides: [
      quickSettingsProvider.overrideWith(_FakeQuickSettingsController.new),
      networkConnectivityProvider.overrideWith(_FakeNetworkController.new),
      bluetoothProvider.overrideWith(_FakeBluetoothController.new),
      desktopNotificationsProvider.overrideWithBuild(
        (_, _) => const DesktopNotificationsState(),
      ),
      desktopWorkspaceProvider.overrideWith(_FakeWorkspaceController.new),
      batteryProvider.overrideWith(_FakeBatteryController.new),
      clockProvider.overrideWith(
        (ref) => Stream<DateTime>.value(DateTime(2026, 9, 9)),
      ),
      mediaPlayerServiceProvider.overrideWithValue(service),
      if (mediaStream != null)
        mediaPlaybackProvider.overrideWith((ref) => mediaStream),
    ],
    child: child,
  );
}

Widget _wrap(Widget child, {bool disableAnimations = false}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: MediaQuery(
      data: MediaQueryData(
        size: const Size(800, 600),
        disableAnimations: disableAnimations,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xff121212),
        body: ShellTheme(data: const ShellThemeData(), child: child),
      ),
    ),
  );
}

class _FakeMediaPlayerService implements MediaPlayerService {
  final List<String> calls = <String>[];
  final StreamController<MprisPlaybackState> _snapshots =
      StreamController<MprisPlaybackState>.broadcast();
  MprisPlaybackState _current = MprisPlaybackState.unavailable();

  @override
  Stream<MprisPlaybackState> get snapshots => _snapshots.stream;

  @override
  MprisPlaybackState get current => _current;

  void emit(MprisPlaybackState state) {
    _current = state;
    _snapshots.add(state);
  }

  @override
  Future<void> start() async {}

  @override
  Future<void> refresh() async {}

  @override
  Future<void> previous() async {
    calls.add('previous');
  }

  @override
  Future<void> next() async {
    calls.add('next');
  }

  @override
  Future<void> playPause() async {
    calls.add('playPause');
  }

  @override
  Future<void> dispose() async {
    await _snapshots.close();
  }
}

class _FakeQuickSettingsController extends QuickSettingsController {
  @override
  QuickSettingsState build() => QuickSettingsState.initial();
}

class _FakeNetworkController extends NetworkConnectivityController {
  @override
  NetworkConnectivityState build() =>
      NetworkConnectivityState.initial().copyWith(initializing: false);
}

class _FakeBluetoothController extends BluetoothController {
  @override
  BluetoothState build() =>
      BluetoothState.initial().copyWith(initializing: false);
}

class _FakeWorkspaceController extends DesktopWorkspaceController {
  @override
  DesktopWorkspaceState build() => DesktopWorkspaceState.initial();
}

class _FakeBatteryController extends BatteryController {
  @override
  BatteryStatus build() => BatteryStatus.unknown;
}
