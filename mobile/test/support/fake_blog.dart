import 'package:leleka_thoughts/blog.dart';
import 'package:leleka_thoughts/store.dart';

class FakeBlogSource implements BlogSource {
  @override
  String? owner = 'fixture-author';
  final articles = <LelekaRecord>[];
  final calls = <String>[];
  bool offline = false;
  @override
  Future<List<LelekaRecord>> list({
    required bool mine,
    required int limit,
  }) async => articles
      .where((a) => mine ? a['author_id'] == owner : a['status'] == 'published')
      .take(limit)
      .map((a) => {...a})
      .toList();
  @override
  Future<LelekaRecord?> read(String id, {bool mine = false}) async {
    for (final a in articles) {
      if (a['id'] == id &&
          (mine ? a['author_id'] == owner : a['status'] == 'published'))
        return {...a};
    }
    return null;
  }

  @override
  Future<void> action(String action, LelekaRecord payload) async {
    calls.add(action);
    if (offline) throw Exception('Offline fixture');
    final id = payload['id'] ?? 'fixture-${articles.length + 1}';
    final old = articles.where((a) => a['id'] == id).firstOrNull;
    if (action == 'delete') {
      articles.removeWhere((a) => a['id'] == id);
      return;
    }
    articles.removeWhere((a) => a['id'] == id);
    articles.add({
      ...?old,
      ...payload,
      'id': id,
      'author_id': owner,
      'status': action == 'unpublish'
          ? 'draft'
          : payload['publish'] == true
          ? 'published'
          : old?['status'] ?? 'draft',
      'updated_at': DateTime.now().toIso8601String(),
      'published_at': DateTime.now().toIso8601String(),
      'author': {
        'display_name': 'Тестовий креатор',
        'username': 'fixture_creator',
      },
    });
  }
}
