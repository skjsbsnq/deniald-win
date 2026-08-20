import 'dart:typed_data';

import 'package:denial_dart_shell/src/models/tray_item.dart';
import 'package:denial_dart_shell/src/services/sni_pixmap_decoder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('argbToRgba pixel conversions', () {
    test(
      '1x1 pure red (network order ARGB FF FF 00 00) -> opaque red RGBA (FF 00 00 FF)',
      () {
        // Network order ARGB: A=0xFF, R=0xFF, G=0x00, B=0x00
        final argb = Uint8List.fromList([0xFF, 0xFF, 0x00, 0x00]);
        final rgba = argbToRgba(argb, 1, 1);

        expect(rgba.length, 4);
        expect(rgba[0], 0xFF); // R
        expect(rgba[1], 0x00); // G
        expect(rgba[2], 0x00); // B
        expect(rgba[3], 0xFF); // A (fully opaque)
      },
    );

    test(
      '1x1 translucent blue (network order ARGB 80 00 00 FF) -> RGBA (00 00 FF 80)',
      () {
        // Network order ARGB: A=0x80 (128), R=0x00, G=0x00, B=0xFF (255)
        final argb = Uint8List.fromList([0x80, 0x00, 0x00, 0xFF]);
        final rgba = argbToRgba(argb, 1, 1);

        expect(rgba.length, 4);
        expect(rgba[0], 0x00); // R
        expect(rgba[1], 0x00); // G
        expect(rgba[2], 0xFF); // B
        expect(rgba[3], 0x80); // A (50% transparent)
      },
    );

    test('2x2 four colors row-major order preservation', () {
      // Pixel 0 (0,0): Red   (FF, FF, 00, 00)
      // Pixel 1 (1,0): Green (FF, 00, FF, 00)
      // Pixel 2 (0,1): Blue  (FF, 00, 00, FF)
      // Pixel 3 (1,1): White (FF, FF, FF, FF)
      final argb = Uint8List.fromList([
        0xFF, 0xFF, 0x00, 0x00, // (0,0) Red
        0xFF, 0x00, 0xFF, 0x00, // (1,0) Green
        0xFF, 0x00, 0x00, 0xFF, // (0,1) Blue
        0xFF, 0xFF, 0xFF, 0xFF, // (1,1) White
      ]);

      final rgba = argbToRgba(argb, 2, 2);
      expect(rgba.length, 16);

      // (0,0) Red in RGBA
      expect(rgba.sublist(0, 4), [0xFF, 0x00, 0x00, 0xFF]);
      // (1,0) Green in RGBA
      expect(rgba.sublist(4, 8), [0x00, 0xFF, 0x00, 0xFF]);
      // (0,1) Blue in RGBA
      expect(rgba.sublist(8, 12), [0x00, 0x00, 0xFF, 0xFF]);
      // (1,1) White in RGBA
      expect(rgba.sublist(12, 16), [0xFF, 0xFF, 0xFF, 0xFF]);
    });

    test(
      'throws ArgumentError if buffer is smaller than required dimensions',
      () {
        final truncated = Uint8List.fromList([0xFF, 0xFF, 0x00]);
        expect(() => argbToRgba(truncated, 1, 1), throwsArgumentError);
      },
    );
  });

  group('selectBestPixmap size selection', () {
    test('returns null for empty or invalid list', () {
      expect(selectBestPixmap([], 24), isNull);
      expect(
        selectBestPixmap([
          TrayPixmap(width: 0, height: 0, bytes: Uint8List(0)),
          TrayPixmap(width: 16, height: 16, bytes: Uint8List(10)), // too short
        ], 24),
        isNull,
      );
    });

    test('selects exact match when available', () {
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

    test('prefers smallest size that is >= targetSize if no exact match', () {
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

      // For target 22: p32 is closest >= 22
      final selected = selectBestPixmap([p48, p16, p32], 22);
      expect(selected?.width, 32);
    });

    test(
      'falls back to largest available if all are smaller than targetSize',
      () {
        final p8 = TrayPixmap(width: 8, height: 8, bytes: Uint8List(8 * 8 * 4));
        final p16 = TrayPixmap(
          width: 16,
          height: 16,
          bytes: Uint8List(16 * 16 * 4),
        );

        // For target 32: both smaller, select largest (16)
        final selected = selectBestPixmap([p8, p16], 32);
        expect(selected?.width, 16);
      },
    );
  });

  group('sanitizeToolTipText HTML processing', () {
    test('strips standard HTML tags while preserving text', () {
      expect(sanitizeToolTipText('<b>Discord</b>'), 'Discord');
      expect(
        sanitizeToolTipText('<i>Status:</i> <b>Online</b>'),
        'Status: Online',
      );
      expect(
        sanitizeToolTipText('<span color="red">Disconnected</span>'),
        'Disconnected',
      );
    });

    test('converts <br> and <p> tags into newlines', () {
      expect(sanitizeToolTipText('Line 1<br/>Line 2'), 'Line 1\nLine 2');
      expect(
        sanitizeToolTipText('Line 1<br>Line 2<br />Line 3'),
        'Line 1\nLine 2\nLine 3',
      );
      expect(
        sanitizeToolTipText('<p>Paragraph 1</p><p>Paragraph 2</p>'),
        'Paragraph 1\nParagraph 2',
      );
    });

    test('unescapes HTML entities', () {
      expect(
        sanitizeToolTipText('Tom &amp; Jerry &gt; 9000 &lt;'),
        'Tom & Jerry > 9000 <',
      );
      expect(
        sanitizeToolTipText('&quot;Quote&quot; &apos;Single&apos;'),
        '"Quote" \'Single\'',
      );
    });

    test('handles empty or blank string gracefully', () {
      expect(sanitizeToolTipText(''), '');
      expect(sanitizeToolTipText('   '), '');
    });
  });

  group('SniPixmapDecoder cache lifecycle', () {
    test('computes stable cache key and evicts properly', () {
      final decoder = SniPixmapDecoder();
      expect(decoder.cachedEntriesCount, 0);

      decoder.evict('test_');
      expect(decoder.cachedEntriesCount, 0);

      decoder.clear();
      expect(decoder.cachedEntriesCount, 0);
    });
  });
}
