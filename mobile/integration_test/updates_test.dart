import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:leleka_thoughts/blog.dart';
import 'package:leleka_thoughts/store.dart';
import 'package:leleka_thoughts/widgets.dart';

import '../test/support/fake_blog.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Android: shared public blog API, embroidery theme, editor and article reader',
    (tester) async {
      final response = await http
          .get(
            Uri.parse(
              '$apiUrl/rest/v1/articles?select=id&status=eq.published&limit=1',
            ),
            headers: {'apikey': publicKey},
          )
          .timeout(const Duration(seconds: 20));
      expect(response.statusCode, 200);
      expect(jsonDecode(response.body), isA<List<dynamic>>());
      app.prefs = await SharedPreferences.getInstance();
      app.language = 'uk';
      await app.prefs.remove('leleka.blog.v1:fixture-author');
      await tester.pumpWidget(
        AnimatedBuilder(
          animation: app,
          builder: (_, child) => MaterialApp(
            theme: app.palette.theme,
            home: const Scaffold(
              body: SafeArea(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(20),
                  child: Column(
                    children: [
                      StorkMark(size: 60),
                      SizedBox(height: 16),
                      NativeThemePicker(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('theme-vyshyvanka')),
      );
      await tester.tap(find.byKey(const ValueKey('theme-vyshyvanka')));
      await tester.pumpAndSettle();
      expect(app.palette.id, 'vyshyvanka');
      expect(app.prefs.getString('theme'), 'vyshyvanka');
      expect(find.byType(EmbroideryBand), findsWidgets);
      await binding.convertFlutterSurfaceToImage();
      await tester.pumpAndSettle();
      Future<void> capture(String name) async {
        final bytes = await binding.takeScreenshot(name);
        await File('${Directory.systemTemp.path}/$name.png')
            .writeAsBytes(bytes);
      }

      await capture('native-updates-theme');
      final source = FakeBlogSource();
      await tester.pumpWidget(
        MaterialApp(
          theme: app.palette.theme,
          home: BlogPage(source: source),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> tap(String label) async {
        if (find.text(label).evaluate().isEmpty)
          await tester.scrollUntilVisible(
            find.text(label),
            200,
            scrollable: find.byType(Scrollable).first,
          );
        await tester.ensureVisible(find.text(label).last);
        await tester.tap(find.text(label).last);
        await tester.pumpAndSettle();
      }

      Finder field(String label) => find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == label,
      );
      await tap('Написати статтю');
      await tester.enterText(field('Назва статті'), 'Ідеї, що продовжуються');
      await tester.enterText(
        field('Короткий опис'),
        'Мій творчий щоденник у LelekaThoughts',
      );
      await tester.enterText(
        field('Текст статті'),
        'Перший задум стає історією.\n\n${'Показуй процес і розвивай ідеї разом зі спільнотою. ' * 30}',
      );
      await tap('Зберегти чернетку');
      expect(source.articles.single['status'], 'draft');
      await tap('Редагувати');
      await tap('Опублікувати статтю');
      expect(source.articles.single['status'], 'published');
      await capture('native-updates-blog');
      await tap('Читати статтю');
      expect(find.byType(SelectableText), findsWidgets);
      expect(find.text('Ідеї, що продовжуються'), findsOneWidget);
      await capture('native-updates-reader');
      expect(tester.takeException(), isNull);
      await app.prefs.remove('leleka.blog.v1:fixture-author');
    },
  );
}
