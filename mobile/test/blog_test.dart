import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:leleka_thoughts/blog.dart';
import 'package:leleka_thoughts/store.dart';
import 'package:leleka_thoughts/palette.dart';

import 'support/fake_blog.dart';

Finder input(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);
Future<void> tapText(WidgetTester tester, String text) async {
  if (find.text(text).evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      find.text(text),
      250,
      scrollable: find.byType(Scrollable).first,
    );
  }
  final target = find.text(text).last;
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    app.prefs = await SharedPreferences.getInstance();
    app.palette = LelekaPalette.all.first;
    app.language = 'uk';
  });
  testWidgets(
    'Native blog supports drafts, long articles, publish, edit, read, unpublish and delete',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 940));
      final source = FakeBlogSource();
      await tester.pumpWidget(
        MaterialApp(
          theme: app.palette.theme,
          home: BlogPage(source: source),
        ),
      );
      await tester.pumpAndSettle();
      await tapText(tester, 'Написати статтю');
      await tester.enterText(input('Назва статті'), 'Мій творчий щоденник');
      await tester.enterText(input('Текст статті'), 'Ідея та процес. ' * 150);
      await tapText(tester, 'Зберегти чернетку');
      expect(source.articles.single['status'], 'draft');
      expect(
        (source.articles.single['body'] as String).length,
        greaterThan(1000),
      );
      await tapText(tester, 'Редагувати');
      await tester.enterText(input('Назва статті'), 'Нова назва');
      await tapText(tester, 'Опублікувати статтю');
      expect(source.articles.single['status'], 'published');
      await tapText(tester, 'Читати статтю');
      expect(find.text('Нова назва'), findsOneWidget);
      expect(find.byType(SelectableText), findsWidgets);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tapText(tester, 'Редагувати');
      await tapText(tester, 'Зняти з публікації');
      expect(source.articles.single['status'], 'draft');
      expect(find.text('Читати статтю'), findsNothing);
      await tapText(tester, 'Видалити');
      await tapText(tester, 'Готово');
      expect(source.articles, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.binding.setSurfaceSize(null);
    },
  );
  testWidgets(
    'Failed publication preserves local text without automatically retrying',
    (tester) async {
      final source = FakeBlogSource()..offline = true;
      await tester.pumpWidget(
        MaterialApp(
          theme: app.palette.theme,
          home: BlogEditor(source: source),
        ),
      );
      await tester.enterText(input('Назва статті'), 'Незавершена ідея');
      await tester.enterText(input('Текст статті'), 'Збережи цей текст');
      await tapText(tester, 'Опублікувати статтю');
      expect(find.text('Offline fixture'), findsWidgets);
      expect(
        app.prefs.getString('leleka.blog.v1:fixture-author'),
        contains('Збережи цей текст'),
      );
      await tester.pump(const Duration(seconds: 5));
      expect(source.calls, ['save']);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MaterialApp(
          theme: app.palette.theme,
          home: BlogEditor(source: source),
        ),
      );
      expect(
        tester.widget<TextField>(input('Текст статті')).controller!.text,
        'Збережи цей текст',
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Switching accounts hides the previous account draft', (
    tester,
  ) async {
    final source = FakeBlogSource();
    await tester.pumpWidget(
      MaterialApp(
        theme: app.palette.theme,
        home: BlogEditor(source: source),
      ),
    );
    await tester.enterText(input('Текст статті'), 'PRIVATE_DRAFT_SECRET');
    source.owner = 'different-account';
    app.setLanguage('uk');
    await tester.pumpAndSettle();
    expect(input('Текст статті'), findsNothing);
    expect(find.text('PRIVATE_DRAFT_SECRET'), findsNothing);
    expect(source.calls, isEmpty);
  });
  testWidgets(
    'An old account response cannot restore its private article list',
    (tester) async {
      final source = DelayedBlogSource();
      await tester.pumpWidget(
        MaterialApp(
          theme: app.palette.theme,
          home: BlogPage(source: source),
        ),
      );
      await tester.pump();
      source.owner = 'different-account';
      app.setLanguage('uk');
      await tester.pump();
      source.pending.complete([
        {
          'id': 'old',
          'title': 'PRIVATE_OLD_ACCOUNT',
          'status': 'draft',
          'author_id': 'fixture-author',
        },
      ]);
      await tester.pumpAndSettle();
      expect(find.text('PRIVATE_OLD_ACCOUNT'), findsNothing);
      expect(find.text('Ще немає статей'), findsOneWidget);
    },
  );
}

class DelayedBlogSource extends FakeBlogSource {
  final pending = Completer<List<LelekaRecord>>();
  bool first = true;
  @override
  Future<List<LelekaRecord>> list({required bool mine, required int limit}) {
    if (first) {
      first = false;
      return pending.future;
    }
    return super.list(mine: mine, limit: limit);
  }
}
