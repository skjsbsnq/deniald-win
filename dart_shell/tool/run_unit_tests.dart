import 'dart:io';
import 'dart:typed_data';

import 'package:denial_dart_shell/src/models/tray_item.dart';
import 'package:denial_dart_shell/src/services/sni_pixmap_decoder.dart';

void main() async {
  int passed = 0;
  int failed = 0;

  void test(String name, void Function() fn) {
    try {
      fn();
      passed++;
      stdout.writeln('  ✓ $name');
    } catch (e, st) {
      failed++;
      stderr.writeln('  ✗ $name: $e\n$st');
    }
  }

  void expect(dynamic actual, dynamic expected, [String? reason]) {
    if (actual != expected) {
      throw AssertionError(
        'Expected $expected, got $actual${reason != null ? " ($reason)" : ""}',
      );
    }
  }

  void expectList(List<int> actual, List<int> expected) {
    if (actual.length != expected.length) {
      throw AssertionError(
        'Length mismatch: expected ${expected.length}, got ${actual.length}',
      );
    }
    for (int i = 0; i < actual.length; i++) {
      if (actual[i] != expected[i]) {
        throw AssertionError(
          'Element at $i mismatch: expected ${expected[i]}, got ${actual[i]}',
        );
      }
    }
  }

  stdout.writeln('=== Running SNI Pixmap Decoder Unit Tests ===');

  test(
    '1x1 pure red (network order ARGB FF FF 00 00) -> opaque red RGBA (FF 00 00 FF)',
    () {
      final argb = Uint8List.fromList([0xFF, 0xFF, 0x00, 0x00]);
      final rgba = argbToRgba(argb, 1, 1);
      expect(rgba.length, 4);
      expect(rgba[0], 0xFF);
      expect(rgba[1], 0x00);
      expect(rgba[2], 0x00);
      expect(rgba[3], 0xFF);
    },
  );

  test(
    '1x1 translucent blue (network order ARGB 80 00 00 FF) -> RGBA (00 00 FF 80)',
    () {
      final argb = Uint8List.fromList([0x80, 0x00, 0x00, 0xFF]);
      final rgba = argbToRgba(argb, 1, 1);
      expect(rgba.length, 4);
      expect(rgba[0], 0x00);
      expect(rgba[1], 0x00);
      expect(rgba[2], 0xFF);
      expect(rgba[3], 0x80);
    },
  );

  test('2x2 four colors row-major order preservation', () {
    final argb = Uint8List.fromList([
      0xFF, 0xFF, 0x00, 0x00, // (0,0) Red
      0xFF, 0x00, 0xFF, 0x00, // (1,0) Green
      0xFF, 0x00, 0x00, 0xFF, // (0,1) Blue
      0xFF, 0xFF, 0xFF, 0xFF, // (1,1) White
    ]);

    final rgba = argbToRgba(argb, 2, 2);
    expect(rgba.length, 16);
    expectList(rgba.sublist(0, 4), [0xFF, 0x00, 0x00, 0xFF]);
    expectList(rgba.sublist(4, 8), [0x00, 0xFF, 0x00, 0xFF]);
    expectList(rgba.sublist(8, 12), [0x00, 0x00, 0xFF, 0xFF]);
    expectList(rgba.sublist(12, 16), [0xFF, 0xFF, 0xFF, 0xFF]);
  });

  test('throws ArgumentError on truncated buffer', () {
    bool caught = false;
    try {
      argbToRgba(Uint8List.fromList([0xFF, 0xFF, 0x00]), 1, 1);
    } on ArgumentError {
      caught = true;
    }
    expect(caught, true, 'argbToRgba should throw ArgumentError');
  });

  test('selectBestPixmap prefers exact match', () {
    final p16 = TrayPixmap(
      width: 16,
      height: 16,
      bytes: Uint8List(16 * 16 * 4),
    );
    final p24 = TrayPixmap(
      width: 24,
      height: 24,
      bytes: Uint8List(24 * 24 * 4),
    );
    final p32 = TrayPixmap(
      width: 32,
      height: 32,
      bytes: Uint8List(32 * 32 * 4),
    );

    final selected = selectBestPixmap([p16, p32, p24], 24);
    expect(selected?.width, 24);
  });

  test('selectBestPixmap prefers smallest >= targetSize', () {
    final p16 = TrayPixmap(
      width: 16,
      height: 16,
      bytes: Uint8List(16 * 16 * 4),
    );
    final p32 = TrayPixmap(
      width: 32,
      height: 32,
      bytes: Uint8List(32 * 32 * 4),
    );
    final p48 = TrayPixmap(
      width: 48,
      height: 48,
      bytes: Uint8List(48 * 48 * 4),
    );

    final selected = selectBestPixmap([p48, p16, p32], 22);
    expect(selected?.width, 32);
  });

  test('selectBestPixmap falls back to largest < targetSize', () {
    final p8 = TrayPixmap(width: 8, height: 8, bytes: Uint8List(8 * 8 * 4));
    final p16 = TrayPixmap(
      width: 16,
      height: 16,
      bytes: Uint8List(16 * 16 * 4),
    );

    final selected = selectBestPixmap([p8, p16], 32);
    expect(selected?.width, 16);
  });

  test('HTML sanitization', () {
    expect(sanitizeToolTipText('<b>Discord</b>'), 'Discord');
    expect(sanitizeToolTipText('Line 1<br/>Line 2'), 'Line 1\nLine 2');
    expect(
      sanitizeToolTipText('Tom &amp; Jerry &gt; 9000 &lt;'),
      'Tom & Jerry > 9000 <',
    );
    expect(
      sanitizeToolTipText('&quot;Quote&quot; &#39;Single&#39;'),
      '"Quote" \'Single\'',
    );
  });

  stdout.writeln('=== Results: $passed Passed, $failed Failed ===');
  if (failed > 0) exit(1);
}
