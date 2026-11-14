import 'package:flutter/material.dart';

import 'store.dart';
import 'widgets.dart';
import 'auth.dart';
import 'editor.dart';
import 'screens.dart';
import 'stories.dart';

class PostCard extends StatefulWidget {
  final LelekaRecord post;
  final bool comments;
  const PostCard(this.post, {super.key, this.comments = false});
  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends StoreState<PostCard> {
  late bool comments = widget.comments;
  bool busy = false;
  LelekaRecord get p => app.posts.firstWhere(
    (p) => p['id'] == widget.post['id'],
    orElse: () => widget.post,
  );
  Future<void> mutate(String action) async {
    if (await ensureAuth(context)) {
      if (!mounted) return;
      await attempt(context, () => app.action(action, {'id': p['id']}));
    }
  }

  Future<void> menu(String value) async {
    if (value == 'message') {
      await newChat(context, post: text(p['id']));
      return;
    }
    if (value == 'share') {
      await shareLink('post/${p['id']}');
      return;
    }
    if (!await ensureAuth(context) || !mounted) return;
    if (value == 'continue' || value == 'edit' || value == 'quote') {
      await go(
        context,
        Editor(
          parent: value == 'continue' ? p : null,
          edit: value == 'edit' ? p : null,
          quote: value == 'quote' ? p : null,
        ),
      );
    } else if (value == 'delete') {
      if (await confirm(context, 'Видалити')) {
        if (!mounted) return;
        await attempt(context, () async {
          final media = rows(p['media']);
          await app.action('delete_post', {'id': p['id']});
          await app.removeMedia(media);
        });
      }
    } else if (value == 'report') {
      final reason = await prompt(context, 'Причина');
      if (reason != null && mounted) {
        await attempt(
          context,
          () => app.action('report', {
            'id': p['id'],
            'target_type': 'post',
            'reason': reason,
          }),
        );
      }
    } else if (value == 'pin') {
      await attempt(
        context,
        () => app.action('pin', {
          'id': app.me?['pinned_post'] == p['id'] ? null : p['id'],
        }),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final author = row(p['author']), thread = row(p['thread']);
    final deleted = yes(p['deleted']);
    final own = p['author_id'] == app.uid;
    final liked = rows(p['likes']).any((x) => x['user_id'] == app.uid);
    final reposted = rows(p['reposts']).any((x) => x['user_id'] == app.uid);
    final media = rows(p['media']);
    Widget action(
      IconData icon,
      String label,
      VoidCallback onTap, {
      bool active = false,
      int? count,
    }) => Semantics(
      label: app.t(label),
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 20,
                color: active ? app.palette.primary : app.palette.muted,
              ),
              if (count != null && count > 0) ...[
                const SizedBox(width: 5),
                Text(
                  '$count',
                  style: TextStyle(fontSize: 11, color: app.palette.muted),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: app.palette.border)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 17, 16, 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => go(context, ProfilePage(text(p['author_id']))),
            child: PersonAvatar(author, size: 36),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 5,
                        children: [
                          InkWell(
                            onTap: () =>
                                go(context, ProfilePage(text(p['author_id']))),
                            child: Text(
                              text(author['display_name']).isEmpty
                                  ? app.t('Видалений користувач')
                                  : text(author['display_name']),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text(
                            '@${author['username'] ?? 'deleted'} · ${ago(p['created_at'])}',
                            style: TextStyle(
                              fontSize: 10,
                              color: app.palette.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: app.t('Додати'),
                      onSelected: menu,
                      icon: const Icon(Icons.more_horiz, size: 20),
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'share',
                          child: Text(app.t('Поділитися')),
                        ),
                        PopupMenuItem(
                          value: 'message',
                          child: Text(app.t('Надіслати в повідомлення')),
                        ),
                        if (own && !deleted) ...[
                          PopupMenuItem(
                            value: 'continue',
                            child: Text(app.t('Продовжити')),
                          ),
                          PopupMenuItem(
                            value: 'edit',
                            child: Text(app.t('Редагувати')),
                          ),
                          PopupMenuItem(
                            value: 'pin',
                            child: Text(app.t('Закріпити')),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: Text(app.t('Видалити')),
                          ),
                        ] else if (!deleted)
                          PopupMenuItem(
                            value: 'report',
                            child: Text(app.t('Поскаржитися')),
                          ),
                      ],
                    ),
                  ],
                ),
                if (yes(author['is_demo']))
                  Text(
                    app.t('Приклад контенту'),
                    style: TextStyle(fontSize: 10, color: app.palette.muted),
                  ),
                if (p['part'] != null && p['part'] > 1)
                  Text(
                    app.t('Продовження ланцюжка'),
                    style: TextStyle(fontSize: 11, color: app.palette.primary),
                  ),
                if (app.me?['pinned_post'] == p['id'])
                  Text(
                    '⌁ ${app.t('Закріплено')}',
                    style: TextStyle(fontSize: 11, color: app.palette.primary),
                  ),
                Text(
                  deleted ? app.t('Пост видалено') : text(p['body']),
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.65,
                    color: deleted ? app.palette.muted : app.palette.text,
                  ),
                ),
                if (p['edited_at'] != null && !deleted)
                  Text(
                    app.t('Змінено'),
                    style: TextStyle(fontSize: 10, color: app.palette.muted),
                  ),
                if (p['thread_id'] != null)
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      alignment: Alignment.centerLeft,
                    ),
                    onPressed: () =>
                        go(context, ThreadPage(text(p['thread_id']))),
                    icon: const Icon(Icons.link, size: 16),
                    label: Text(
                      '${thread['title'] ?? app.t('Ланцюжки')} · ${app.t('Частина')} ${p['part'] ?? 1}',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                if (!deleted && media.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: media.length == 1
                          ? photo(
                              media.first,
                              MediaQuery.sizeOf(context).width <= 640
                                  ? 1.6
                                  : 2.2,
                            )
                          : GridView.count(
                              crossAxisCount: 2,
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              mainAxisSpacing: 3,
                              crossAxisSpacing: 3,
                              children: media.map((m) => photo(m, 1)).toList(),
                            ),
                    ),
                  ),
                if (!deleted && p['quote_id'] != null)
                  QuotePreview(text(p['quote_id'])),
                if (!deleted && p['thread_id'] != null)
                  for (final s in app.series.where(
                    (s) => s['thread_id'] == p['thread_id'],
                  ))
                    TextButton.icon(
                      onPressed: () => go(context, SeriesPage(text(s['id']))),
                      icon: const Icon(Icons.play_circle_outline, size: 16),
                      label: Text(
                        app.t('Дивитися процес'),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                if (!deleted)
                  Row(
                    children: [
                      action(
                        liked ? Icons.favorite : Icons.favorite_border,
                        'Вподобати',
                        () => mutate('like'),
                        active: liked,
                        count: rows(p['likes']).length,
                      ),
                      const SizedBox(width: 16),
                      action(
                        Icons.mode_comment_outlined,
                        'Коментарі',
                        () => setState(() => comments = !comments),
                        count: rows(p['comments']).length,
                      ),
                      const SizedBox(width: 16),
                      PopupMenuButton<String>(
                        tooltip: app.t('Репост'),
                        padding: EdgeInsets.zero,
                        onSelected: (v) =>
                            v == 'quote' ? menu('quote') : mutate('repost'),
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: 'repost',
                            child: Text(app.t('Репост')),
                          ),
                          PopupMenuItem(
                            value: 'quote',
                            child: Text(app.t('Цитувати')),
                          ),
                        ],
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Row(
                            children: [
                              Icon(
                                Icons.repeat,
                                size: 20,
                                color: reposted
                                    ? app.palette.primary
                                    : app.palette.muted,
                              ),
                              if (rows(p['reposts']).isNotEmpty)
                                Text(
                                  ' ${rows(p['reposts']).length}',
                                  style: const TextStyle(fontSize: 11),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const Spacer(),
                      action(
                        app.saved(p['id'])
                            ? Icons.bookmark
                            : Icons.bookmark_border,
                        'Зберегти',
                        () => mutate('save'),
                        active: app.saved(p['id']),
                      ),
                    ],
                  ),
                if (comments && !deleted) Comments(p),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget photo(LelekaRecord media, double ratio) => InkWell(
    onTap: () => go(context, PhotoPage(mediaUrl(media['src']))),
    child: AspectRatio(
      aspectRatio: ratio,
      child: Image.network(
        mediaUrl(media['src']),
        fit: BoxFit.cover,
        errorBuilder: (_, e, s) =>
            const Center(child: Icon(Icons.broken_image_outlined)),
      ),
    ),
  );
}

class PhotoPage extends StatelessWidget {
  final String url;
  const PhotoPage(this.url, {super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
    ),
    body: Center(
      child: InteractiveViewer(
        minScale: 1,
        maxScale: 5,
        child: Image.network(
          url,
          errorBuilder: (_, e, s) =>
              const Icon(Icons.broken_image, color: Colors.white),
        ),
      ),
    ),
  );
}

class QuotePreview extends StatefulWidget {
  final String id;
  const QuotePreview(this.id, {super.key});
  @override
  State<QuotePreview> createState() => _QuotePreviewState();
}

class _QuotePreviewState extends StoreState<QuotePreview> {
  LelekaRecord? post;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void changed() {
    super.changed();
    load();
  }

  void load() {
    app.db
        .from('posts')
        .select(postSelect)
        .eq('id', widget.id)
        .maybeSingle()
        .then((p) {
          if (mounted) setState(() => post = p);
        })
        .catchError((Object e) {});
  }

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => go(context, ThreadPage(widget.id, single: true)),
    child: Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: app.palette.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (post != null && !yes(post!['deleted']))
            Text(
              text(row(post!['author'])['display_name']),
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
            ),
          Text(
            post == null || yes(post!['deleted'])
                ? app.t('Пост видалено')
                : text(post!['body']),
            maxLines: 5,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    ),
  );
}

class Comments extends StatefulWidget {
  final LelekaRecord post;
  const Comments(this.post, {super.key});
  @override
  State<Comments> createState() => _CommentsState();
}

class _CommentsState extends State<Comments> {
  List<LelekaRecord> items = [];
  final input = TextEditingController();
  LelekaRecord? reply;
  final expanded = <String>{};
  bool busy = false;
  String error = '';
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final data = await app.db
          .from('comments')
          .select('*,author:profiles!comments_author_id_fkey(*)')
          .eq('post_id', widget.post['id'])
          .order('created_at')
          .limit(200);
      if (mounted) setState(() => items = data);
    } catch (e) {
      if (mounted) setState(() => error = app.message(e));
    }
  }

  Widget comment(LelekaRecord c, {bool nested = false}) {
    final author = row(c['author']);
    return Padding(
      padding: EdgeInsets.only(top: 12, left: nested ? 18 : 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PersonAvatar(author, size: 27),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${author['display_name'] ?? app.t('Видалений користувач')} · ${ago(c['created_at'])}',
                  style: TextStyle(fontSize: 10, color: app.palette.muted),
                ),
                Text(
                  yes(c['deleted'])
                      ? app.t('Коментар видалено')
                      : text(c['body']),
                  style: const TextStyle(fontSize: 12, height: 1.5),
                ),
                if (!yes(c['deleted']))
                  Wrap(
                    children: [
                      TextButton(
                        onPressed: () async {
                          if (await ensureAuth(context)) {
                            setState(() {
                              reply = c;
                              input.text =
                                  '@${author['username'] ?? 'deleted'} ';
                            });
                          }
                        },
                        child: Text(
                          app.t('Відповісти'),
                          style: const TextStyle(fontSize: 10),
                        ),
                      ),
                      if (app.uid == c['author_id'] ||
                          app.uid == widget.post['author_id'])
                        TextButton(
                          onPressed: () async {
                            await attempt(
                              context,
                              () =>
                                  app.action('delete_comment', {'id': c['id']}),
                            );
                            await load();
                          },
                          child: Text(
                            app.t('Видалити'),
                            style: const TextStyle(fontSize: 10),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      line(),
      for (final c in items.where((c) => c['parent_id'] == null)) ...[
        comment(c),
        if (items.any((r) => r['parent_id'] == c['id']))
          TextButton(
            onPressed: () => setState(() {
              if (!expanded.add(c['id'])) expanded.remove(c['id']);
            }),
            child: Text(
              '${app.t('Показати відповіді')} (${items.where((r) => r['parent_id'] == c['id']).length})',
              style: const TextStyle(fontSize: 11),
            ),
          ),
        if (expanded.contains(c['id']))
          ...items
              .where((r) => r['parent_id'] == c['id'])
              .map((r) => comment(r, nested: true)),
      ],
      if (reply != null)
        Row(
          children: [
            Expanded(
              child: Text(
                '@${row(reply!['author'])['username']}',
                style: const TextStyle(fontSize: 11),
              ),
            ),
            IconButton(
              onPressed: () => setState(() {
                reply = null;
                input.clear();
              }),
              icon: const Icon(Icons.close, size: 16),
            ),
          ],
        ),
      if (error.isNotEmpty) Text(error),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: input,
              maxLength: 1000,
              minLines: 1,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: app.t('Написати коментар…'),
                counterText: '',
              ),
            ),
          ),
          IconButton(
            tooltip: app.t('Надіслати'),
            onPressed: busy
                ? null
                : () async {
                    if (input.text.trim().isEmpty ||
                        !await ensureAuth(context) ||
                        !mounted) {
                      return;
                    }
                    setState(() => busy = true);
                    try {
                      final parent = reply?['parent_id'] ?? reply?['id'];
                      await app.action('comment', {
                        'id': widget.post['id'],
                        'body': input.text,
                        'parent_id': parent,
                      });
                      if (parent != null) expanded.add(parent);
                      input.clear();
                      reply = null;
                      await load();
                    } catch (e) {
                      if (mounted) setState(() => error = app.message(e));
                    } finally {
                      if (mounted) setState(() => busy = false);
                    }
                  },
            icon: const Icon(Icons.send_outlined),
          ),
        ],
      ),
    ],
  );
}

class ThreadPage extends StatefulWidget {
  final String id;
  final String? focus;
  final bool single;
  const ThreadPage(this.id, {super.key, this.focus, this.single = false});
  @override
  State<ThreadPage> createState() => _ThreadPageState();
}

class _ThreadPageState extends StoreState<ThreadPage> {
  List<LelekaRecord> items = [];
  bool loading = true;
  String error = '', title = '';
  int limit = 18;
  final focusKey = GlobalKey();
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      var query = app.db.from('posts').select(postSelect);
      final data =
          await (widget.single
                  ? query.eq('id', widget.id)
                  : query.eq('thread_id', widget.id))
              .order(widget.single ? 'created_at' : 'part')
              .limit(limit);
      if (!widget.single) {
        final th = await app.db
            .from('threads')
            .select()
            .eq('id', widget.id)
            .maybeSingle();
        title = text(th?['title']);
      }
      if (mounted) {
        setState(() {
          items = data;
          loading = false;
        });
      }
      if (widget.focus != null && items.any((p) => p['id'] == widget.focus)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (focusKey.currentContext != null) {
            Scrollable.ensureVisible(
              focusKey.currentContext!,
              duration: const Duration(milliseconds: 200),
            );
          }
        });
      } else if (widget.focus != null && items.length == limit) {
        limit += 18;
        await load();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = app.message(e);
          loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => NativePage(
    title: widget.single
        ? 'Пост'
        : title.isEmpty
        ? 'Ланцюжки'
        : title,
    body: RefreshIndicator(
      onRefresh: load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          for (final s in app.series.where((s) => s['thread_id'] == widget.id))
            ListTile(
              title: Text(text(s['title'])),
              subtitle: Text(app.t('Дивитися процес')),
              trailing: const Icon(Icons.play_circle_outline),
              onTap: () => go(context, SeriesPage(text(s['id']))),
            ),
          if (error.isNotEmpty)
            EmptyState(
              title: 'Не вдалося завантажити дані',
              detail: error,
              action: TextButton(
                onPressed: load,
                child: Text(app.t('Спробувати ще')),
              ),
            ),
          if (loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: CircularProgressIndicator(),
              ),
            ),
          for (final p in items)
            PostCard(
              p,
              key: p['id'] == widget.focus ? focusKey : ValueKey(p['id']),
              comments: widget.single || p['id'] == widget.focus,
            ),
          if (items.length == limit && !widget.single)
            TextButton(
              onPressed: () {
                limit += 18;
                load();
              },
              child: Text(app.t('Завантажити ще')),
            ),
          if (items.isNotEmpty && items.last['author_id'] == app.uid)
            Padding(
              padding: const EdgeInsets.all(24),
              child: OutlinedButton.icon(
                onPressed: () async {
                  await go(context, Editor(parent: items.last));
                  await load();
                },
                icon: const Icon(Icons.add),
                label: Text(app.t('Продовжити')),
              ),
            ),
        ],
      ),
    ),
  );
}
