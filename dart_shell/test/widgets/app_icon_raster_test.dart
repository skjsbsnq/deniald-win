import 'dart:io';

import 'package:denial_dart_shell/src/widgets/app_icon.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

/// The shell renders SVG app icons as vector pictures (the default
/// flutter_svg strategy): identical icons share one decode-cache entry and
/// are never re-decoded while the icon set moves or changes density. A
/// broken icon path must fall back to the bundled default instead of
/// throwing inside the shell.
final Finder _fileIconLoader = find.byWidgetPredicate(
  (widget) => widget is SvgPicture && widget.bytesLoader is DesktopAppSvgLoader,
);

final Finder _fallbackAssetIcon = find.byWidgetPredicate(
  (widget) => widget is SvgPicture && widget.bytesLoader is SvgAssetLoader,
);

void main() {
  testWidgets('file icons decode once and share the entry across widgets', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('denial-icon-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/icon.svg')
      ..writeAsStringSync('''
<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">
  <path fill="currentColor" d="M0 0H64V64H0Z"/>
</svg>
''');
    final cold = svg.cache.count;
    await tester.runAsync(() => DesktopAppSvgLoader(file.path).loadBytes(null));
    final warm = svg.cache.count;
    // Exactly one decode exists per distinct icon file.
    expect(warm, cold + 1);

    Widget icons({int count = 2, double dpr = 2, double x = 0}) {
      return MediaQuery(
        data: MediaQueryData(devicePixelRatio: dpr),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: Transform.translate(
              offset: Offset(x, 0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < count; i++)
                    SizedBox.square(
                      dimension: 85,
                      child: AppIconImage(iconPath: file.path),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(icons());
    await tester.pumpAndSettle();
    expect(_fileIconLoader, findsNWidgets(2));
    // Both widgets show the decoded graphic, not the placeholder or the
    // bundled fallback.
    expect(
      find.descendant(of: _fileIconLoader, matching: _fallbackAssetIcon),
      findsNothing,
    );
    expect(svg.cache.count, warm);
    final warmAllocations = svg.cache.count;
    for (var frame = 1; frame <= 20; frame++) {
      await tester.pumpWidget(icons(x: frame * 0.7));
    }
    expect(svg.cache.count, warmAllocations);

    await tester.pumpWidget(icons(count: 1));
    await tester.pumpAndSettle();
    expect(_fileIconLoader, findsOneWidget);
    expect(svg.cache.count, warmAllocations);

    await tester.pumpWidget(icons(count: 1, dpr: 3));
    await tester.pumpAndSettle();
    // Vector pictures are density-independent in the decode cache.
    expect(svg.cache.count, warmAllocations);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a broken icon path falls back to the bundled icon', (
    tester,
  ) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(devicePixelRatio: 2),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox.square(
              dimension: 85,
              child: AppIconImage(iconPath: '/nonexistent/denial-icon/icon.svg'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(_fileIconLoader, findsOneWidget);
    expect(
      find.descendant(of: _fileIconLoader, matching: _fallbackAssetIcon),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
