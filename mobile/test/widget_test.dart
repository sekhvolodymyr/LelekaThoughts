import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:leleka_thoughts/store.dart';
import 'package:leleka_thoughts/palette.dart';
import 'package:leleka_thoughts/widgets.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    app.prefs = await SharedPreferences.getInstance();
    app.palette = LelekaPalette.all.first;
    app.language = 'uk';
  });
  test('All six palettes keep readable text and button contrast', () {
    double contrast(Color a, Color b) {
      final x = a.computeLuminance(), y = b.computeLuminance();
      return (x > y ? (x + .05) / (y + .05) : (y + .05) / (x + .05));
    }

    expect(LelekaPalette.all.map((p) => p.id).toSet().length, 6);
    for (final p in LelekaPalette.all) {
      expect(
        contrast(p.text, p.background),
        greaterThanOrEqualTo(4.5),
        reason: p.id,
      );
      expect(
        contrast(p.primary, p.onPrimary),
        greaterThanOrEqualTo(4.5),
        reason: p.id,
      );
    }
  });
  testWidgets('Native picker changes theme and persists the choice', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(500, 900));
    await tester.pumpWidget(
      AnimatedBuilder(
        animation: app,
        builder: (_, child) => MaterialApp(
          theme: app.palette.theme,
          home: const Scaffold(
            body: Padding(
              padding: EdgeInsets.all(20),
              child: NativeThemePicker(),
            ),
          ),
        ),
      ),
    );
    for (final p in LelekaPalette.all) {
      await tester.tap(find.byKey(ValueKey('theme-${p.id}')));
      await tester.pumpAndSettle();
      expect(app.palette.id, p.id);
      expect(app.prefs.getString('theme'), p.id);
      expect(tester.takeException(), isNull);
    }
    await tester.binding.setSurfaceSize(null);
  });
  test('Relative website media resolve in the native client', () {
    expect(mediaUrl('/media/photobook.webp'), '$website/media/photobook.webp');
    expect(
      mediaUrl('https://example.com/photo.png'),
      'https://example.com/photo.png',
    );
  });
  test('Unknown saved theme falls back to the light palette', () {
    expect(LelekaPalette.fromId('invalid').id, 'light');
  });
}
