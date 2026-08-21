import 'package:denial_dart_shell/src/models/denial_window.dart';
import 'package:denial_dart_shell/src/state/shell_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('transient popups are absent from app lists and adjacent switching', () {
    final normal = _window(1, 'Normal');
    final popup = _window(2, 'Menu', serverSideDecorated: false);
    final other = _window(3, 'Other');
    final state = ShellState.initial().copyWith(
      windows: <DenialWindow>[normal, popup, other],
      foregroundObjectId: normal.objectId,
    );

    expect(state.openAppWindows, <DenialWindow>[normal, other]);
    expect(state.openAppWindowCount, 2);
    expect(state.adjacentOpenAppWindow(1), other);
    expect(state.adjacentOpenAppWindow(-1), isNull);
  });
}

DenialWindow _window(
  int objectId,
  String title, {
  bool serverSideDecorated = true,
}) {
  return DenialWindow(
    objectId: objectId,
    objectKind: 'root_surface',
    surfaceId: objectId,
    windowId: objectId,
    textureId: objectId,
    title: title,
    appId: 'test-$objectId',
    width: 800,
    height: 600,
    surfaceX: 0,
    surfaceY: 0,
    surfaceWidth: 800,
    surfaceHeight: 600,
    textureSourceX: 0,
    textureSourceY: 0,
    textureSourceWidth: 800,
    textureSourceHeight: 600,
    geometryX: 0,
    geometryY: 0,
    geometryWidth: 800,
    geometryHeight: 600,
    monitorId: 1,
    transform: 0,
    scale120: 120,
    serverSideDecorated: serverSideDecorated,
  );
}
