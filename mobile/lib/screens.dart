import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'store.dart';
import 'widgets.dart';
import 'auth.dart';
import 'posts.dart';
import 'stories.dart';
import 'editor.dart';

class FeedPage extends StatefulWidget {
  const FeedPage({super.key});
  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends StoreState<FeedPage> {
  bool following = false, more = false;
  final scroll = ScrollController();
  @override
  void initState() {
    super.initState();
    scroll.addListener(() {
      if (scroll.position.extentAfter < 400 &&
          !more &&
          app.hasMore &&
          !app.loading) {
        loadMore();
      }
    });
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  Future<void> loadMore() async {
    setState(() => more = true);
    await app.refresh(more: true);
    if (mounted) setState(() => more = false);
  }

  @override
  Widget build(BuildContext context) {
    var list = app.posts
        .where((p) => !yes(p['deleted']) || p['thread_id'] != null)
        .toList();
    if (following) {
      list = list
          .where(
            (p) =>
                app.followed(p['author_id']) ||
                rows(p['reposts']).any((r) => app.followed(r['user_id'])),
          )
          .toList();
    } else {
      final interests = List<String>.from(app.me?['interests'] ?? []);
      int score(LelekaRecord p) =>
          List<String>.from(p['topics'] ?? []).any(interests.contains) ? 1 : 0;
      list.sort(
        (a, b) => score(b).compareTo(score(a)) != 0
            ? score(b).compareTo(score(a))
            : text(b['created_at']).compareTo(text(a['created_at'])),
      );
    }
    return RefreshIndicator(
      onRefresh: app.refresh,
      child: ListView(
        controller: scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Row(
            children: [
              for (final v in [false, true])
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => following = v),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: following == v
                                ? app.palette.primary
                                : app.palette.border,
                            width: following == v ? 2 : 1,
                          ),
                        ),
                      ),
                      child: Text(
                        app.t(v ? 'Підписки' : 'Для тебе'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: following == v
                              ? FontWeight.w600
                              : FontWeight.normal,
                          color: following == v
                              ? app.palette.primary
                              : app.palette.muted,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const StoryStrip(),
          line(),
          InkWell(
            onTap: () async {
              if (await ensureAuth(context) && context.mounted) {
                await go(context, const Editor());
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              child: Row(
                children: [
                  PersonAvatar(app.me, size: 36),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      app.t('З чого починається твоя ідея?'),
                      style: TextStyle(fontSize: 12, color: app.palette.muted),
                    ),
                  ),
                  const Icon(Icons.add, size: 20),
                ],
              ),
            ),
          ),
          line(),
          if (app.loading)
            const Padding(
              padding: EdgeInsets.all(48),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (app.error.isNotEmpty)
            EmptyState(
              title: 'Не вдалося завантажити дані',
              detail: app.error,
              action: TextButton(
                onPressed: app.refresh,
                child: Text(app.t('Спробувати ще')),
              ),
            ),
          if (!app.loading && list.isEmpty && app.error.isEmpty)
            EmptyState(
              detail: following
                  ? 'Підписуйтесь на креаторів, щоб бачити їхні пости тут.'
                  : 'Додайте першу публікацію',
            ),
          for (final p in list) PostCard(p, key: ValueKey(p['id'])),
          if (app.hasMore)
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextButton(
                onPressed: more ? null : loadMore,
                child: Text(app.t(more ? 'Завантаження…' : 'Завантажити ще')),
              ),
            ),
        ],
      ),
    );
  }
}

class PersonTile extends StatelessWidget {
  final LelekaRecord person;
  const PersonTile(this.person, {super.key});
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 3),
    leading: PersonAvatar(person),
    title: Text(
      text(person['display_name']),
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    ),
    subtitle: Text(
      '@${person['username']}',
      style: TextStyle(fontSize: 11, color: app.palette.muted),
    ),
    onTap: () => go(context, ProfilePage(text(person['id']))),
    trailing: app.uid == person['id']
        ? null
        : IconButton(
            tooltip: app.t(
              app.followed(person['id']) ? 'Ви підписані' : 'Підписатися',
            ),
            onPressed: () async {
              if (await ensureAuth(context) && context.mounted) {
                await attempt(
                  context,
                  () => app.action('follow', {'id': person['id']}),
                );
              }
            },
            icon: Icon(
              app.followed(person['id']) ? Icons.check : Icons.add,
              color: app.palette.primary,
            ),
          ),
  );
}

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends StoreState<SearchPage> {
  final query = TextEditingController();
  int tab = 0;
  List<LelekaRecord> results = [];
  bool busy = true;
  String error = '';
  Timer? timer;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    search();
  }

  @override
  void dispose() {
    timer?.cancel();
    query.dispose();
    super.dispose();
  }

  Future<void> search() async {
    final current = ++generation;
    setState(() => busy = true);
    try {
      final q = query.text.trim().replaceAll(RegExp(r'[%_,()]'), ' ');
      List<LelekaRecord> data;
      if (tab == 0) {
        data = await app.db
            .from('profiles')
            .select()
            .or(
              'display_name.ilike.%$q%,username.ilike.%${q.replaceFirst(RegExp(r'^@'), '')}%',
            )
            .limit(40);
      } else if (tab == 1) {
        data = await app.db
            .from('posts')
            .select(postSelect)
            .eq('deleted', false)
            .ilike('body', '%$q%')
            .order('created_at', ascending: false)
            .limit(40);
      } else {
        data = await app.db
            .from(tab == 2 ? 'threads' : 'series')
            .select()
            .ilike('title', '%$q%')
            .limit(40);
      }
      if (mounted && generation == current) {
        setState(() {
          results = data;
          error = '';
          busy = false;
        });
      }
    } catch (e) {
      if (mounted && current == generation) {
        setState(() {
          error = app.message(e);
          busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(18),
        child: TextField(
          key: const ValueKey('search-query'),
          controller: query,
          decoration: InputDecoration(
            hintText: app.t('Пошук…'),
            prefixIcon: const Icon(Icons.search),
          ),
          onChanged: (_) {
            timer?.cancel();
            timer = Timer(const Duration(milliseconds: 300), search);
          },
        ),
      ),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < 4; i++)
              TextButton(
                onPressed: () {
                  setState(() => tab = i);
                  search();
                },
                style: TextButton.styleFrom(
                  foregroundColor: i == tab
                      ? app.palette.primary
                      : app.palette.muted,
                ),
                child: Text(app.t(['Люди', 'Пости', 'Ланцюжки', 'Серії'][i])),
              ),
          ],
        ),
      ),
      line(),
      Expanded(
        child: busy
            ? const Center(child: CircularProgressIndicator())
            : error.isNotEmpty
            ? EmptyState(detail: error)
            : results.isEmpty
            ? const EmptyState(title: 'Немає результатів')
            : ListView.builder(
                itemCount: results.length,
                itemBuilder: (c, i) {
                  final item = results[i];
                  if (tab == 0) return PersonTile(item);
                  if (tab == 1) return PostCard(item);
                  return ListTile(
                    leading: const Icon(Icons.link),
                    title: Text(text(item['title'])),
                    trailing: const Icon(Icons.north_east, size: 18),
                    onTap: () => go(
                      context,
                      tab == 2
                          ? ThreadPage(text(item['id']))
                          : SeriesPage(text(item['id'])),
                    ),
                  );
                },
              ),
      ),
    ],
  );
}

class ProfilePage extends StatefulWidget {
  final String id;
  final bool embedded;
  const ProfilePage(this.id, {super.key, this.embedded = false});
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends StoreState<ProfilePage> {
  LelekaRecord? profile;
  List<LelekaRecord> posts = [], collections = [];
  int tab = 0;
  bool loading = true;
  String error = '';
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(ProfilePage old) {
    super.didUpdateWidget(old);
    if (old.id != widget.id) load();
  }

  Future<void> load() async {
    try {
      profile = await app.db
          .from('profiles')
          .select()
          .eq('id', widget.id)
          .maybeSingle();
      collections = await app.db
          .from('series')
          .select()
          .eq('author_id', widget.id)
          .order('created_at', ascending: false);
      if (tab == 2) {
        final reposts = await app.db
            .from('reposts')
            .select('post_id')
            .eq('user_id', widget.id);
        final ids = reposts.map((r) => text(r['post_id'])).toList();
        posts = ids.isEmpty
            ? []
            : await app.db
                  .from('posts')
                  .select(postSelect)
                  .inFilter('id', ids)
                  .order('created_at', ascending: false)
                  .limit(200);
      } else {
        posts = await app.db
            .from('posts')
            .select(postSelect)
            .eq('author_id', widget.id)
            .order('created_at', ascending: false)
            .limit(200);
      }
      final pinned = profile?['pinned_post'];
      posts.sort(
        (a, b) => a['id'] == pinned
            ? -1
            : b['id'] == pinned
            ? 1
            : text(b['created_at']).compareTo(text(a['created_at'])),
      );
      error = '';
    } catch (e) {
      error = app.message(e);
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> moderation(String action) async {
    if (!await ensureAuth(context) || !mounted) return;
    if (action == 'report') {
      final reason = await prompt(context, 'Причина');
      if (reason != null && mounted) {
        await attempt(
          context,
          () => app.action('report', {
            'id': widget.id,
            'target_type': 'profile',
            'reason': reason,
          }),
        );
      }
    } else if (await confirm(
      context,
      app.blocks.any((b) => b['blocked_id'] == widget.id)
          ? 'Розблокувати'
          : 'Заблокувати',
    )) {
      if (mounted) {
        await attempt(context, () => app.action('block', {'id': widget.id}));
      }
      await load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final own = app.uid == widget.id;
    final p = profile;
    if (p == null) {
      final body = loading
          ? const Center(child: CircularProgressIndicator())
          : EmptyState(title: 'Немає результатів', detail: error);
      return widget.embedded ? body : NativePage(title: 'Профіль', body: body);
    }
    final body = RefreshIndicator(
      onRefresh: load,
      child: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    PersonAvatar(p, size: 76),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            text(p['display_name']),
                            style: const TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '@${p['username']}',
                            style: TextStyle(
                              color: app.palette.muted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (own)
                      IconButton(
                        tooltip: app.t('Налаштування'),
                        onPressed: () async {
                          await go(context, const SettingsPage());
                          await load();
                        },
                        icon: const Icon(Icons.settings_outlined),
                      ),
                  ],
                ),
                if (yes(p['is_demo']))
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      app.t('Демонстраційний профіль'),
                      style: TextStyle(fontSize: 11, color: app.palette.muted),
                    ),
                  ),
                if (text(p['bio']).isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      text(p['bio']),
                      style: const TextStyle(height: 1.6),
                    ),
                  ),
                if (text(p['website']).startsWith('https://') ||
                    text(p['website']).startsWith('http://'))
                  TextButton.icon(
                    onPressed: () => launchUrl(
                      Uri.parse(text(p['website'])),
                      mode: LaunchMode.externalApplication,
                    ),
                    icon: const Icon(Icons.link, size: 16),
                    label: Text(
                      text(p['website']),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                Wrap(
                  spacing: 20,
                  children: [
                    Text(
                      '${app.follows.where((f) => f['following_id'] == widget.id).length} ${app.t('Підписники')}',
                      style: TextStyle(fontSize: 12, color: app.palette.muted),
                    ),
                    Text(
                      '${app.follows.where((f) => f['follower_id'] == widget.id).length} ${app.t('Підписки профілю')}',
                      style: TextStyle(fontSize: 12, color: app.palette.muted),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (!own)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton(
                        onPressed: () async {
                          if (await ensureAuth(context) && context.mounted) {
                            await attempt(
                              context,
                              () => app.action('follow', {'id': widget.id}),
                            );
                          }
                        },
                        child: Text(
                          app.t(
                            app.followed(widget.id)
                                ? 'Ви підписані'
                                : 'Підписатися',
                          ),
                        ),
                      ),
                      if (!yes(p['is_demo']))
                        OutlinedButton(
                          onPressed: () async {
                            if (await ensureAuth(context) && context.mounted) {
                              await go(context, ChatPage(recipient: widget.id));
                            }
                          },
                          child: Text(app.t('Повідомлення')),
                        ),
                      PopupMenuButton<String>(
                        onSelected: moderation,
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: 'report',
                            child: Text(app.t('Поскаржитися')),
                          ),
                          PopupMenuItem(
                            value: 'block',
                            child: Text(
                              app.t(
                                app.blocks.any(
                                      (b) => b['blocked_id'] == widget.id,
                                    )
                                    ? 'Розблокувати'
                                    : 'Заблокувати',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                if (collections.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  SizedBox(
                    height: 104,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: collections
                          .map(
                            (s) => SizedBox(
                              width: 92,
                              child: InkWell(
                                onTap: () =>
                                    go(context, SeriesPage(text(s['id']))),
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 12),
                                  child: Column(
                                    children: [
                                      Container(
                                        height: 72,
                                        decoration: BoxDecoration(
                                          color: app.palette.accent,
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                        ),
                                        child: const Center(
                                          child: Icon(
                                            Icons.auto_stories_outlined,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        text(s['title']),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 10),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Row(
            children: [
              for (var i = 0; i < 3; i++)
                Expanded(
                  child: TextButton(
                    onPressed: () {
                      setState(() => tab = i);
                      load();
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: tab == i
                          ? app.palette.primary
                          : app.palette.muted,
                    ),
                    child: Text(app.t(['Пости', 'Ланцюжки', 'Репости'][i])),
                  ),
                ),
            ],
          ),
          line(),
          if (error.isNotEmpty) EmptyState(detail: error),
          if (tab == 1)
            ...app.threads
                .where((t) => t['author_id'] == widget.id)
                .map(
                  (t) => ListTile(
                    leading: const Icon(Icons.link),
                    title: Text(text(t['title'])),
                    trailing: const Icon(Icons.north_east, size: 18),
                    onTap: () => go(context, ThreadPage(text(t['id']))),
                  ),
                )
          else
            ...posts.map((p) => PostCard(p, key: ValueKey(p['id']))),
          if (!loading &&
              (tab == 1
                  ? !app.threads.any((t) => t['author_id'] == widget.id)
                  : posts.isEmpty))
            const EmptyState(),
        ],
      ),
    );
    return widget.embedded
        ? body
        : NativePage(
            title: 'Профіль',
            body: body,
            actions: [
              IconButton(
                onPressed: () => shareLink('profile/${widget.id}'),
                icon: const Icon(Icons.ios_share),
              ),
            ],
          );
  }
}

class SavedPage extends StatefulWidget {
  const SavedPage({super.key});
  @override
  State<SavedPage> createState() => _SavedPageState();
}

class _SavedPageState extends StoreState<SavedPage> {
  List<LelekaRecord> posts = [];
  String error = '';
  bool loading = true;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final ids = app.saves.map((s) => text(s['post_id'])).toList();
      posts = ids.isEmpty
          ? []
          : await app.db
                .from('posts')
                .select(postSelect)
                .inFilter('id', ids)
                .order('created_at', ascending: false);
    } catch (e) {
      error = app.message(e);
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) => NativePage(
    title: 'Збережене',
    body: RefreshIndicator(
      onRefresh: () async {
        await app.refresh();
        await load();
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (loading) const Center(child: CircularProgressIndicator()),
          if (error.isNotEmpty) EmptyState(detail: error),
          for (final p in posts.where((p) => app.saved(p['id']))) PostCard(p),
          if (!loading && posts.where((p) => app.saved(p['id'])).isEmpty)
            const EmptyState(
              detail: 'Збережіть пост або ланцюжок, щоб повернутися до нього.',
            ),
        ],
      ),
    ),
  );
}

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});
  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends StoreState<NotificationsPage> {
  @override
  Widget build(BuildContext context) {
    if (app.uid == null) return AuthRequired();
    final groups = <String, List<LelekaRecord>>{};
    for (final n in app.notices) {
      final key =
          '${n['kind']}:${n['target']}:${text(n['created_at']).split('T').first}';
      groups.putIfAbsent(key, () => []).add(n);
    }
    const verbs = {
      'like': ['вподобали ваш пост', 'liked your post'],
      'repost': ['поширили ваш пост', 'reposted your post'],
      'comment': ['прокоментували ваш пост', 'commented on your post'],
      'reply': ['відповіли на ваш коментар', 'replied to your comment'],
      'follow': ['підписалися на вас', 'followed you'],
      'message': ['надіслали повідомлення', 'sent you a message'],
    };
    return RefreshIndicator(
      onRefresh: app.refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () =>
                  attempt(context, () => app.action('read_notifications')),
              icon: const Icon(Icons.done_all),
              label: Text(app.t('Прочитати все')),
            ),
          ),
          for (final group in groups.values)
            Builder(
              builder: (c) {
                final n = group.first, person = app.person(n['actor_id']);
                final count = group.map((n) => n['actor_id']).toSet().length;
                return Material(
                  color: group.any((n) => !yes(n['read']))
                      ? app.palette.accent.withValues(alpha: .4)
                      : Colors.transparent,
                  child: ListTile(
                    leading: PersonAvatar(person),
                    title: Text(
                      '${person['display_name']}${count > 1
                          ? app.language == 'uk'
                                ? ' та ще ${count - 1}'
                                : ' and ${count - 1} others'
                          : ''} ${verbs[n['kind']]?[app.language == 'uk' ? 0 : 1] ?? ''}',
                      style: const TextStyle(fontSize: 12, height: 1.6),
                    ),
                    subtitle: Text(
                      ago(n['created_at']),
                      style: const TextStyle(fontSize: 10),
                    ),
                    onTap: () => go(
                      context,
                      n['kind'] == 'follow'
                          ? ProfilePage(text(n['actor_id']))
                          : n['kind'] == 'message'
                          ? ChatPage(conversation: text(n['target']))
                          : ThreadPage(text(n['target']), single: true),
                    ),
                  ),
                );
              },
            ),
          if (groups.isEmpty) const EmptyState(title: 'Немає нових сповіщень'),
        ],
      ),
    );
  }
}

class AuthRequired extends StatelessWidget {
  const AuthRequired({super.key});
  @override
  Widget build(BuildContext context) => EmptyState(
    title: 'Увійдіть, щоб долучитися',
    action: FilledButton(
      onPressed: () => showAuth(context),
      child: Text(app.t('Увійти')),
    ),
  );
}

class MessagesPage extends StatefulWidget {
  const MessagesPage({super.key});
  @override
  State<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends StoreState<MessagesPage> {
  @override
  Widget build(BuildContext context) {
    if (app.uid == null) return const AuthRequired();
    return RefreshIndicator(
      onRefresh: app.refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => newChat(context),
              icon: const Icon(Icons.add),
              label: Text(app.t('Новий діалог')),
            ),
          ),
          for (final c in app.conversations)
            Builder(
              builder: (context) {
                final other = c['member_a'] == app.uid
                    ? c['member_b']
                    : c['member_a'];
                final p = app.person(other);
                final unread = app.notices
                    .where(
                      (n) =>
                          n['kind'] == 'message' &&
                          n['target'] == c['id'] &&
                          !yes(n['read']),
                    )
                    .length;
                return ListTile(
                  leading: PersonAvatar(p),
                  title: Text(
                    text(p['display_name']),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    c['status'] == 'pending'
                        ? app.t(
                            c['initiator'] == app.uid
                                ? 'Очікує на прийняття'
                                : 'Запит на спілкування',
                          )
                        : '@${p['username']}',
                    style: TextStyle(fontSize: 11, color: app.palette.muted),
                  ),
                  trailing: unread > 0
                      ? Badge(label: Text('$unread'))
                      : const Icon(Icons.chat_bubble_outline, size: 18),
                  onTap: () =>
                      go(context, ChatPage(conversation: text(c['id']))),
                );
              },
            ),
          if (app.conversations.isEmpty)
            EmptyState(
              title: 'Новий діалог',
              detail: 'Почніть із пошуку людини або відкрийте її профіль.',
              action: OutlinedButton(
                onPressed: () => newChat(context),
                child: Text(app.t('Новий діалог')),
              ),
            ),
        ],
      ),
    );
  }
}

Future<void> newChat(
  BuildContext context, {
  String? post,
  String? series,
}) async {
  if (!await ensureAuth(context) || !context.mounted) return;
  final selected = await showDialog<String>(
    context: context,
    builder: (c) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 450, maxHeight: 550),
        child: PersonChooser(),
      ),
    ),
  );
  if (selected == null || !context.mounted) return;
  if (post != null || series != null) {
    final result = await attempt(
      context,
      () => app.action('send', {
        'recipient_id': selected,
        'body': app.t(post != null ? 'Пост' : 'Серії'),
        'share_post': ?post,
        'share_series': ?series,
      }),
    );
    if (result != null && context.mounted) {
      await go(context, ChatPage(conversation: text(result['id'])));
    }
  } else {
    await go(context, ChatPage(recipient: selected));
  }
}

class PersonChooser extends StatefulWidget {
  const PersonChooser({super.key});
  @override
  State<PersonChooser> createState() => _PersonChooserState();
}

class _PersonChooserState extends State<PersonChooser> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final list = app.profiles
        .where(
          (p) =>
              p['id'] != app.uid &&
              !yes(p['is_demo']) &&
              !app.blocks.any((b) => b['blocked_id'] == p['id']) &&
              '${p['display_name']} ${p['username']}'.toLowerCase().contains(
                query.toLowerCase(),
              ),
        )
        .toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.all(20),
          child: TextField(
            autofocus: true,
            decoration: InputDecoration(labelText: app.t('Пошук')),
            onChanged: (v) => setState(() => query = v),
          ),
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final p in list)
                ListTile(
                  leading: PersonAvatar(p),
                  title: Text(text(p['display_name'])),
                  subtitle: Text('@${p['username']}'),
                  onTap: () => Navigator.pop(context, text(p['id'])),
                ),
              if (list.isEmpty) const EmptyState(title: 'Немає результатів'),
            ],
          ),
        ),
      ],
    );
  }
}

class ChatPage extends StatefulWidget {
  final String? recipient, conversation;
  const ChatPage({super.key, this.recipient, this.conversation});
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends StoreState<ChatPage> {
  final input = TextEditingController(), scroll = ScrollController();
  List<LelekaRecord> messages = [];
  LelekaRecord? selected;
  String? recipient, id;
  String error = '';
  bool busy = false, loading = true;
  RealtimeChannel? subscription;
  Timer? reloadTimer;
  bool reloading = false, reloadAgain = false;
  late final String? accountOwner;
  String get draftKey => 'native.message:$accountOwner:$recipient';
  @override
  void initState() {
    super.initState();
    accountOwner = app.uid;
    recipient = widget.recipient;
    id = widget.conversation;
    initialize();
  }

  Future<void> initialize() async {
    selected = app.conversations.cast<LelekaRecord?>().firstWhere((c) {
      if (c == null) return false;
      if (id != null) return c['id'] == id;
      return c['member_a'] == recipient || c['member_b'] == recipient;
    }, orElse: () => null);
    if (selected != null) {
      id = text(selected!['id']);
      recipient = text(
        selected!['member_a'] == app.uid
            ? selected!['member_b']
            : selected!['member_a'],
      );
    }
    input.text = app.prefs.getString(draftKey) ?? '';
    await load();
    subscribe();
  }

  void subscribe() {
    if (id == null || subscription != null) return;
    subscription = app.db
        .channel('native-chat:$id')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: id!,
          ),
          callback: (_) {
            reloadTimer?.cancel();
            reloadTimer = Timer(const Duration(milliseconds: 250), () async {
              if (!mounted) return;
              if (reloading) {
                reloadAgain = true;
                return;
              }
              reloading = true;
              do {
                reloadAgain = false;
                await load();
              } while (reloadAgain && mounted);
              reloading = false;
            });
          },
        )
        .subscribe();
  }

  Future<void> markRead() async {
    if (app.uid != accountOwner) return;
    if (id != null) {
      try {
        await app.db.rpc(
          'app_action',
          params: {
            'action': 'read_chat',
            'payload': {'id': id},
          },
        );
        if (mounted) app.markChatRead(id!);
      } catch (e) {
        /* Retain the local state for a manual retry. */
      }
    }
  }

  Future<void> load() async {
    if (app.uid != accountOwner) return;
    try {
      if (id != null) {
        messages = await app.db
            .from('messages')
            .select()
            .eq('conversation_id', id!)
            .order('created_at', ascending: false)
            .limit(300);
        messages = messages.reversed.toList();
        selected = await app.db
            .from('conversations')
            .select()
            .eq('id', id!)
            .maybeSingle();
        await markRead();
      }
      error = '';
    } catch (e) {
      error = app.message(e);
    }
    if (mounted) setState(() => loading = false);
    bottom();
  }

  void bottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scroll.hasClients) {
        scroll.animateTo(
          scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    reloadTimer?.cancel();
    if (subscription != null) unawaited(app.db.removeChannel(subscription!));
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final person = app.person(recipient),
        pending = selected?['status'] == 'pending',
        incoming = pending && selected?['initiator'] != app.uid;
    if (app.uid == null || app.uid != accountOwner) {
      return const NativePage(title: 'Повідомлення', body: AuthRequired());
    }
    final disabled =
        selected?['status'] == 'declined' ||
        pending && (incoming || messages.isNotEmpty);
    return NativePage(
      title: text(person['display_name']),
      body: Column(
        children: [
          ListTile(
            dense: true,
            leading: PersonAvatar(person, size: 32),
            title: Text(
              '@${person['username']}',
              style: TextStyle(color: app.palette.muted, fontSize: 12),
            ),
          ),
          if (pending)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              color: app.palette.accent,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    app.t(
                      incoming ? 'Запит на спілкування' : 'Очікує на прийняття',
                    ),
                    style: const TextStyle(fontSize: 12),
                  ),
                  if (incoming)
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final accept in [true, false])
                          TextButton(
                            onPressed: () async {
                              await attempt(
                                context,
                                () => app.action('accept_chat', {
                                  'id': id,
                                  'accept': accept,
                                }),
                              );
                              await load();
                            },
                            child: Text(
                              app.t(accept ? 'Прийняти' : 'Відхилити'),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: load,
                    child: ListView(
                      controller: scroll,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(18),
                      children: [
                        for (final m in messages)
                          Align(
                            alignment: m['sender_id'] == app.uid
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Container(
                              constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.sizeOf(context).width * .78,
                              ),
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: m['sender_id'] == app.uid
                                    ? app.palette.accent
                                    : app.palette.sidebar,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    text(m['body']),
                                    style: const TextStyle(
                                      fontSize: 13,
                                      height: 1.5,
                                    ),
                                  ),
                                  if (m['share_post'] != null)
                                    TextButton(
                                      onPressed: () => go(
                                        context,
                                        ThreadPage(
                                          text(m['share_post']),
                                          single: true,
                                        ),
                                      ),
                                      child: Text('${app.t('Пост')} ↗'),
                                    ),
                                  if (m['share_series'] != null)
                                    TextButton(
                                      onPressed: () => go(
                                        context,
                                        SeriesPage(text(m['share_series'])),
                                      ),
                                      child: Text('${app.t('Серії')} ↗'),
                                    ),
                                  Text(
                                    (DateTime.tryParse(text(m['created_at']))
                                                ?.toLocal()
                                                .toIso8601String()
                                                .split('T')
                                                .last ??
                                            '')
                                        .substring(0, 5),
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: app.palette.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        if (messages.isEmpty)
                          const EmptyState(title: 'Новий діалог'),
                      ],
                    ),
                  ),
          ),
          if (error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (selected?['status'] == 'declined')
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(app.t('Запит відхилено')),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: input,
                      enabled: !disabled,
                      minLines: 1,
                      maxLines: 5,
                      maxLength: 4000,
                      onChanged: (v) => app.prefs.setString(draftKey, v),
                      decoration: InputDecoration(
                        hintText: app.t('Напишіть повідомлення…'),
                        counterText: '',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: app.t('Надіслати'),
                    onPressed: busy || disabled
                        ? null
                        : () async {
                            if (input.text.trim().isEmpty ||
                                recipient == null) {
                              return;
                            }
                            setState(() => busy = true);
                            try {
                              final result = await app.action('send', {
                                'recipient_id': recipient,
                                'body': input.text,
                              });
                              id = text(result['id']);
                              input.clear();
                              await app.prefs.remove(draftKey);
                              await load();
                              subscribe();
                            } catch (e) {
                              if (mounted) {
                                setState(() => error = app.message(e));
                              }
                            } finally {
                              if (mounted) setState(() => busy = false);
                            }
                          },
                    icon: const Icon(Icons.send_outlined),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends StoreState<SettingsPage> {
  late final name = TextEditingController(text: text(app.me?['display_name'])),
      bio = TextEditingController(text: text(app.me?['bio'])),
      websiteInput = TextEditingController(text: text(app.me?['website']));
  late List<String> interests = List<String>.from(app.me?['interests'] ?? []);
  bool busy = false;
  String error = '';
  @override
  void dispose() {
    name.dispose();
    bio.dispose();
    websiteInput.dispose();
    super.dispose();
  }

  Future<void> delete() async {
    final password = TextEditingController(),
        confirmation = TextEditingController();
    final entered = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(app.t('Видалити акаунт')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                app.language == 'uk'
                    ? 'Профіль, публікації та медіа буде видалено. Для Google або входу кодом спочатку повторно увійдіть. Введіть DELETE для підтвердження.'
                    : 'Your profile, posts and media will be deleted. For Google or email-code accounts, sign in again first. Type DELETE to confirm.',
              ),
              const SizedBox(height: 18),
              field(password, 'Пароль', password: true),
              const SizedBox(height: 14),
              field(confirmation, 'DELETE'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(app.t('Скасувати')),
          ),
          FilledButton(
            onPressed: () {
              if (confirmation.text == 'DELETE')
                Navigator.pop(c, password.text);
            },
            child: Text(app.t('Видалити акаунт')),
          ),
        ],
      ),
    );
    password.dispose();
    confirmation.dispose();
    if (entered == null || !mounted) return;
    setState(() => busy = true);
    try {
      if (entered.isNotEmpty)
        await app.db.auth.signInWithPassword(
          email: app.user!.email!,
          password: entered,
        );
      await app.account({'action': 'delete_account'});
      await app.db.auth.signOut();
      if (mounted) Navigator.popUntil(context, (r) => r.isFirst);
    } catch (e) {
      if (mounted) notice(context, app.message(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (app.me == null) {
      return const NativePage(title: 'Налаштування', body: AuthRequired());
    }
    return NativePage(
      title: 'Налаштування',
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            children: [
              PersonAvatar(app.me, size: 70),
              const SizedBox(width: 18),
              TextButton.icon(
                onPressed: busy
                    ? null
                    : () async {
                        await attempt(context, () async {
                          final f = await ImagePicker().pickImage(
                            source: ImageSource.gallery,
                            maxWidth: 1000,
                            imageQuality: 85,
                          );
                          if (f == null) return;
                          final media = await app.upload(f);
                          await app.action('profile', {'avatar': media['src']});
                        });
                      },
                icon: const Icon(Icons.photo_outlined),
                label: Text(app.t('Фото')),
              ),
            ],
          ),
          const SizedBox(height: 20),
          field(name, 'Ім’я', maxLength: 60),
          const SizedBox(height: 14),
          field(bio, 'Біо', lines: 3, maxLength: 240),
          const SizedBox(height: 14),
          field(
            websiteInput,
            'Посилання',
            keyboard: TextInputType.url,
            maxLength: 500,
          ),
          const SizedBox(height: 18),
          Text(app.t('Ваші теми')),
          TopicPicker(
            selected: interests,
            onChanged: (v) => setState(() => interests = v),
          ),
          const SizedBox(height: 18),
          DropdownButtonFormField<String>(
            initialValue: app.language,
            decoration: InputDecoration(labelText: app.t('Мова')),
            items: const [
              DropdownMenuItem(value: 'uk', child: Text('Українська')),
              DropdownMenuItem(value: 'en', child: Text('English')),
            ],
            onChanged: (v) {
              if (v != null) app.setLanguage(v);
            },
          ),
          const SizedBox(height: 24),
          const NativeThemePicker(),
          const SizedBox(height: 24),
          if (error.isNotEmpty) Text(error),
          FilledButton(
            onPressed: busy
                ? null
                : () async {
                    setState(() => busy = true);
                    try {
                      await app.action('profile', {
                        'display_name': name.text,
                        'bio': bio.text,
                        'website': websiteInput.text,
                        'interests': interests,
                        'language': app.language,
                        'theme': app.palette.id,
                      });
                      if (context.mounted) notice(context, app.t('Збережено'));
                    } catch (e) {
                      if (mounted) setState(() => error = app.message(e));
                    } finally {
                      if (mounted) setState(() => busy = false);
                    }
                  },
            child: Text(app.t(busy ? 'Завантаження…' : 'Зберегти')),
          ),
          const SizedBox(height: 18),
          if (app.blocks.isNotEmpty) ...[
            Text(
              app.t('Заблоковані користувачі'),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            for (final b in app.blocks)
              ListTile(
                title: Text(text(app.person(b['blocked_id'])['display_name'])),
                trailing: TextButton(
                  onPressed: () => attempt(
                    context,
                    () => app.action('block', {'id': b['blocked_id']}),
                  ),
                  child: Text(app.t('Розблокувати')),
                ),
              ),
          ],
          OutlinedButton(
            onPressed: () async {
              await app.db.auth.signOut();
              if (context.mounted)
                Navigator.popUntil(context, (r) => r.isFirst);
            },
            child: Text(app.t('Вийти')),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: busy ? null : delete,
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(app.t('Видалити акаунт')),
          ),
        ],
      ),
    );
  }
}

class MyThreadsPage extends StatelessWidget {
  const MyThreadsPage({super.key});
  @override
  Widget build(BuildContext context) => NativePage(
    title: 'Мої ланцюжки',
    body: ListView(
      children: [
        for (final t in app.threads.where((t) => t['author_id'] == app.uid))
          ListTile(
            leading: const Icon(Icons.link),
            title: Text(text(t['title'])),
            trailing: const Icon(Icons.north_east),
            onTap: () => go(context, ThreadPage(text(t['id']))),
          ),
        if (!app.threads.any((t) => t['author_id'] == app.uid))
          const EmptyState(
            detail: 'Створіть перший ланцюжок через «Продовжити» під власним постом.',
          ),
        ListTile(
          leading: const Icon(Icons.edit_note),
          title: Text(app.t('Мої чернетки')),
          onTap: () => go(context, const DraftsPage()),
        ),
      ],
    ),
  );
}

class DraftsPage extends StatefulWidget {
  const DraftsPage({super.key});
  @override
  State<DraftsPage> createState() => _DraftsPageState();
}

class _DraftsPageState extends State<DraftsPage> {
  List<LelekaRecord> drafts = [];
  String error = '';
  @override
  void initState() {
    super.initState();
    app.db
        .from('drafts')
        .select()
        .order('updated_at', ascending: false)
        .then((data) {
          if (mounted) setState(() => drafts = data);
        })
        .catchError((Object e) {
          if (mounted) setState(() => error = app.message(e));
        });
  }

  @override
  Widget build(BuildContext context) => NativePage(
    title: 'Мої чернетки',
    body: ListView(
      children: [
        if (error.isNotEmpty) Text(error),
        for (final d in drafts)
          ListTile(
            title: Text(
              text(d['body']),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(ago(d['updated_at'])),
            onTap: () async {
              LelekaRecord? parent;
              if (d['parent_id'] != null) {
                parent = await app.db
                    .from('posts')
                    .select(postSelect)
                    .eq('id', d['parent_id'])
                    .maybeSingle();
              }
              if (context.mounted) await go(context, Editor(parent: parent));
            },
          ),
        if (drafts.isEmpty) const EmptyState(),
      ],
    ),
  );
}

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});
  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  List<LelekaRecord> reports = [];
  String error = '';
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      reports = await app.db
          .from('reports')
          .select()
          .eq('status', 'open')
          .order('created_at');
    } catch (e) {
      error = app.message(e);
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => NativePage(
    title: 'Адмінпанель',
    body: !app.admin
        ? const EmptyState()
        : ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (error.isNotEmpty) Text(error),
              for (final r in reports)
                Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${r['target_type']} · ${app.person(r['reporter_id'])['username']}',
                        style: TextStyle(
                          color: app.palette.muted,
                          fontSize: 11,
                        ),
                      ),
                      Text(text(r['reason'])),
                      Wrap(
                        spacing: 8,
                        children: [
                          TextButton(
                            onPressed: () => go(
                              context,
                              r['target_type'] == 'profile'
                                  ? ProfilePage(text(r['target_id']))
                                  : ThreadPage(
                                      text(r['target_id']),
                                      single: true,
                                    ),
                            ),
                            child: Text(app.t('Відкрити')),
                          ),
                          TextButton(
                            onPressed: () async {
                              await attempt(
                                context,
                                () => app.action('admin', {
                                  'id': r['target_id'],
                                  'operation': r['target_type'] == 'profile'
                                      ? 'suspend'
                                      : r['target_type'] == 'story'
                                      ? 'hide_story'
                                      : 'hide_post',
                                }),
                              );
                              await load();
                            },
                            child: Text(
                              app.t(
                                r['target_type'] == 'profile'
                                    ? 'Призупинити акаунт'
                                    : 'Приховати',
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () async {
                              await attempt(
                                context,
                                () => app.action('admin', {
                                  'id': r['id'],
                                  'operation': 'resolve',
                                }),
                              );
                              await load();
                            },
                            child: Text(app.t('Розглянуто')),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              if (reports.isEmpty) const EmptyState(),
            ],
          ),
  );
}
