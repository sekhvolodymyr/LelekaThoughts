import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'store.dart';
import 'widgets.dart';

const blogSummary =
    'id,author_id,title,excerpt,status,created_at,updated_at,published_at,author:profiles!articles_author_id_fkey(display_name,username)';

abstract interface class BlogSource {
  String? get owner;
  Future<List<LelekaRecord>> list({required bool mine, required int limit});
  Future<LelekaRecord?> read(String id, {bool mine = false});
  Future<void> action(String action, LelekaRecord payload);
}

class SupabaseBlogSource implements BlogSource {
  @override
  String? get owner => app.uid;
  @override
  Future<List<LelekaRecord>> list({
    required bool mine,
    required int limit,
  }) async {
    var query = app.db.from('articles').select(blogSummary);
    if (mine) {
      if (owner == null) return [];
      query = query.eq('author_id', owner!);
    } else {
      query = query.eq('status', 'published');
    }
    return rows(
      await query
          .order(mine ? 'updated_at' : 'published_at', ascending: false)
          .limit(limit),
    );
  }

  @override
  Future<LelekaRecord?> read(String id, {bool mine = false}) async {
    var query = app.db
        .from('articles')
        .select(
          '*,author:profiles!articles_author_id_fkey(display_name,username)',
        )
        .eq('id', id);
    if (mine) {
      if (owner == null) return null;
      query = query.eq('author_id', owner!);
    } else {
      query = query.eq('status', 'published');
    }
    final data = await query.maybeSingle();
    return data == null ? null : row(data);
  }

  @override
  Future<void> action(String action, LelekaRecord payload) async {
    await app.db.rpc(
      'blog_action',
      params: {'action': action, 'payload': payload},
    );
  }
}

Future<void> shareArticle(String id) => SharePlus.instance
    .share(ShareParams(text: '$website/blog/$id'))
    .then((_) {});

class BlogPage extends StatefulWidget {
  final bool mine;
  final BlogSource? source;
  const BlogPage({super.key, this.mine = true, this.source});
  @override
  State<BlogPage> createState() => _BlogPageState();
}

class _BlogPageState extends StoreState<BlogPage> {
  late final source = widget.source ?? SupabaseBlogSource();
  String? owner;
  List<LelekaRecord> articles = [];
  bool loading = true;
  String error = '';
  int limit = 50, generation = 0;
  @override
  void initState() {
    super.initState();
    owner = source.owner;
    unawaited(load());
  }

  @override
  void changed() {
    if (owner != source.owner) {
      owner = source.owner;
      articles = [];
      generation++;
      unawaited(load());
    }
    super.changed();
  }

  Future<void> load() async {
    final token = ++generation;
    if (mounted)
      setState(() {
        loading = true;
        error = '';
      });
    try {
      final data = await source.list(mine: widget.mine, limit: limit);
      if (mounted && token == generation) setState(() => articles = data);
    } catch (e) {
      if (mounted && token == generation)
        setState(() {
          error = app.message(e);
          articles = [];
        });
    } finally {
      if (mounted && token == generation) setState(() => loading = false);
    }
  }

  Future<void> edit([String? id]) async {
    final expected = source.owner;
    LelekaRecord? article;
    if (id != null) {
      article = await attempt<LelekaRecord?>(
        context,
        () => source.read(id, mine: true),
      );
      if (article == null) return;
    }
    if (!mounted || expected != source.owner) return;
    await go(context, BlogEditor(article: article, source: source));
    if (mounted) await load();
  }

  @override
  Widget build(BuildContext context) => NativePage(
    title: widget.mine ? 'Мій блог' : 'Блоги креаторів',
    actions: [
      if (widget.mine && source.owner != null)
        IconButton(
          key: const ValueKey('blog-create'),
          tooltip: app.t('Написати статтю'),
          onPressed: () => edit(),
          icon: const Icon(Icons.edit_note),
        ),
    ],
    body: widget.mine && source.owner == null
        ? const EmptyState(title: 'Увійдіть, щоб долучитися')
        : RefreshIndicator(
            onRefresh: load,
            child: ListView(
              padding: const EdgeInsets.all(20),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                if (widget.mine) ...[
                  FilledButton.icon(
                    onPressed: () => edit(),
                    icon: const Icon(Icons.add),
                    label: Text(app.t('Написати статтю')),
                  ),
                  TextButton(
                    onPressed: () =>
                        go(context, BlogPage(mine: false, source: source)),
                    child: Text(app.t('Читати блоги')),
                  ),
                ],
                if (loading) const LinearProgressIndicator(),
                if (error.isNotEmpty) ...[
                  Text(
                    error,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  TextButton(onPressed: load, child: Text(app.t('Повторити'))),
                ],
                if (!loading && articles.isEmpty && error.isEmpty)
                  const EmptyState(title: 'Ще немає статей'),
                for (final article in articles)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.mine)
                          Chip(
                            label: Text(
                              app.t(
                                article['status'] == 'published'
                                    ? 'Опубліковано'
                                    : 'Чернетка',
                              ),
                            ),
                          ),
                        const SizedBox(height: 8),
                        Text(
                          text(article['title']),
                          style: const TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (text(article['excerpt']).isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              text(article['excerpt']),
                              style: TextStyle(
                                height: 1.7,
                                color: app.palette.muted,
                              ),
                            ),
                          ),
                        const SizedBox(height: 12),
                        Text(
                          widget.mine
                              ? ago(article['updated_at'])
                              : text(row(article['author'])['display_name']),
                          style: TextStyle(
                            fontSize: 12,
                            color: app.palette.muted,
                          ),
                        ),
                        Wrap(
                          spacing: 10,
                          runSpacing: 6,
                          children: [
                            if (widget.mine)
                              TextButton(
                                onPressed: () => edit(text(article['id'])),
                                child: Text(app.t('Редагувати')),
                              ),
                            if (article['status'] == 'published')
                              TextButton(
                                onPressed: () => go(
                                  context,
                                  BlogReader(
                                    id: text(article['id']),
                                    source: source,
                                  ),
                                ),
                                child: Text(app.t('Читати статтю')),
                              ),
                            if (widget.mine)
                              TextButton(
                                onPressed: () async {
                                  if (!await confirm(
                                        context,
                                        'Видалити статтю назавжди?',
                                      ) ||
                                      !context.mounted)
                                    return;
                                  final expected = owner;
                                  await attempt(context, () async {
                                    if (source.owner != expected)
                                      throw Exception(
                                        app.t('Увійдіть до акаунта'),
                                      );
                                    await source.action('delete', {
                                      'id': article['id'],
                                    });
                                  });
                                  if (mounted) await load();
                                },
                                child: Text(
                                  app.t('Видалити'),
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        line(),
                      ],
                    ),
                  ),
                if (!loading && articles.length == limit)
                  TextButton(
                    onPressed: () {
                      limit += 50;
                      load();
                    },
                    child: Text(app.t('Показати ще')),
                  ),
              ],
            ),
          ),
  );
}

class BlogEditor extends StatefulWidget {
  final LelekaRecord? article;
  final BlogSource? source;
  const BlogEditor({super.key, this.article, this.source});
  @override
  State<BlogEditor> createState() => _BlogEditorState();
}

class _BlogEditorState extends StoreState<BlogEditor> {
  late final source = widget.source ?? SupabaseBlogSource();
  late final String? owner;
  final title = TextEditingController(),
      excerpt = TextEditingController(),
      body = TextEditingController();
  String? id;
  String status = 'draft', error = '';
  bool busy = false, saved = false;
  Timer? timer;
  String get draftKey => 'leleka.blog.v1:$owner';
  @override
  void initState() {
    super.initState();
    owner = source.owner;
    var initial = widget.article ?? <String, dynamic>{};
    if (widget.article == null) {
      try {
        initial = row(jsonDecode(app.prefs.getString(draftKey) ?? '{}'));
      } catch (_) {}
    }
    id = initial['id'] as String?;
    status = initial['status'] == 'published' ? 'published' : 'draft';
    title.text = text(initial['title']);
    excerpt.text = text(initial['excerpt']);
    body.text = text(initial['body']);
  }

  LelekaRecord get payload => {
    if (id != null) 'id': id,
    'title': title.text.trim(),
    'excerpt': excerpt.text,
    'body': body.text,
    'status': status,
  };
  void cache() {
    if (owner != null && !saved)
      unawaited(app.prefs.setString(draftKey, jsonEncode(payload)));
  }

  void changedText(String _) {
    timer?.cancel();
    timer = Timer(const Duration(milliseconds: 250), cache);
  }

  @override
  void dispose() {
    timer?.cancel();
    cache();
    title.dispose();
    excerpt.dispose();
    body.dispose();
    super.dispose();
  }

  Future<void> save({bool publish = false, bool unpublish = false}) async {
    if (busy) return;
    if (source.owner != owner || owner == null) {
      setState(() => error = app.t('Увійдіть до акаунта'));
      return;
    }
    if (title.text.trim().isEmpty ||
        title.text.trim().runes.length > 160 ||
        excerpt.text.runes.length > 240 ||
        body.text.runes.length > 50000 ||
        (publish && body.text.trim().isEmpty)) {
      setState(() => error = app.t('Додайте назву та текст статті.'));
      notice(context, error);
      return;
    }
    setState(() {
      busy = true;
      error = '';
    });
    timer?.cancel();
    cache();
    try {
      await source.action(unpublish ? 'unpublish' : 'save', {
        ...payload,
        'publish': publish,
      });
      saved = true;
      try {
        await app.prefs.remove(draftKey);
      } catch (_) {
        /* The server save already succeeded. */
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => error = app.message(e));
        notice(context, error);
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => NativePage(
    title: 'Мій блог',
    body: source.owner != owner || owner == null
        ? const EmptyState(title: 'Увійдіть, щоб долучитися')
        : ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (error.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    error,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              field(
                title,
                'Назва статті',
                maxLength: 160,
                onChanged: changedText,
                enabled: !busy,
              ),
              const SizedBox(height: 16),
              field(
                excerpt,
                'Короткий опис',
                maxLength: 240,
                lines: 2,
                onChanged: changedText,
                enabled: !busy,
              ),
              const SizedBox(height: 16),
              field(
                body,
                'Текст статті',
                maxLength: 50000,
                lines: 12,
                onChanged: changedText,
                enabled: !busy,
              ),
              const SizedBox(height: 12),
              Text(
                app.t(
                  'Чернетки бачиш тільки ти. Текст зберігається на цьому пристрої під час введення.',
                ),
                style: TextStyle(
                  fontSize: 12,
                  height: 1.7,
                  color: app.palette.muted,
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: busy ? null : () => save(publish: true),
                child: Text(
                  app.t(
                    status == 'published'
                        ? 'Оновити статтю'
                        : 'Опублікувати статтю',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: busy
                    ? null
                    : () => save(unpublish: status == 'published'),
                child: Text(
                  app.t(
                    status == 'published'
                        ? 'Зняти з публікації'
                        : 'Зберегти чернетку',
                  ),
                ),
              ),
              if (busy)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: LinearProgressIndicator(),
                ),
            ],
          ),
  );
}

class BlogReader extends StatefulWidget {
  final String id;
  final BlogSource? source;
  const BlogReader({super.key, required this.id, this.source});
  @override
  State<BlogReader> createState() => _BlogReaderState();
}

class _BlogReaderState extends StoreState<BlogReader> {
  late final source = widget.source ?? SupabaseBlogSource();
  LelekaRecord? article;
  String error = '';
  bool loading = true;
  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  Future<void> load() async {
    try {
      final value = await source.read(widget.id);
      if (mounted)
        setState(() {
          article = value;
          error = '';
        });
    } catch (e) {
      if (mounted)
        setState(() {
          article = null;
          error = app.message(e);
        });
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => NativePage(
    title: 'Стаття',
    actions: [
      if (article != null)
        IconButton(
          tooltip: app.t('Поширити статтю'),
          onPressed: () => attempt(context, () => shareArticle(widget.id)),
          icon: const Icon(Icons.share_outlined),
        ),
    ],
    body: RefreshIndicator(
      onRefresh: load,
      child: ListView(
        padding: const EdgeInsets.all(22),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (loading) const LinearProgressIndicator(),
          if (!loading && article == null)
            EmptyState(title: error.isEmpty ? 'Статтю не знайдено' : error),
          if (article != null) ...[
            SelectableText(
              text(article!['title']),
              style: const TextStyle(
                fontSize: 30,
                height: 1.25,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (text(article!['excerpt']).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 22),
                child: SelectableText(
                  text(article!['excerpt']),
                  style: TextStyle(
                    fontSize: 18,
                    height: 1.8,
                    color: app.palette.muted,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                '${text(row(article!['author'])['display_name'])} · ${ago(article!['published_at'])}',
                style: TextStyle(fontSize: 12, color: app.palette.muted),
              ),
            ),
            SelectableText(
              text(article!['body']),
              style: const TextStyle(fontSize: 17, height: 1.9),
            ),
          ],
        ],
      ),
    ),
  );
}
