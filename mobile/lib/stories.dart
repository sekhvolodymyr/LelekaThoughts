import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'store.dart';
import 'widgets.dart';
import 'auth.dart';
import 'editor.dart';
import 'posts.dart';
import 'screens.dart' show newChat;

class StoryStrip extends StatelessWidget {
  const StoryStrip({super.key});
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final active = app.stories
        .where(
          (s) => (DateTime.tryParse(text(s['expires_at'])) ?? now).isAfter(now),
        )
        .toList();
    final ids = active.map((s) => text(s['author_id'])).toSet();
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            app.t('Історії, що тривають'),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 87,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                storyPerson(
                  context,
                  null,
                  () => ensureAuth(context).then((ok) {
                    if (ok && context.mounted) {
                      go(context, const Editor(story: true));
                    }
                  }),
                ),
                for (final id in ids)
                  storyPerson(
                    context,
                    app.person(id),
                    () => go(
                      context,
                      StoryViewer(
                        active.where((s) => s['author_id'] == id).toList(),
                      ),
                    ),
                  ),
                if (ids.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 22, left: 18),
                    child: Text(
                      app.t('Розкажіть про свою ідею'),
                      style: TextStyle(color: app.palette.muted, fontSize: 11),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget storyPerson(
    BuildContext context,
    LelekaRecord? person,
    VoidCallback onTap,
  ) => Padding(
    padding: const EdgeInsets.only(right: 16),
    child: SizedBox(
      width: 62,
      child: InkWell(
        onTap: onTap,
        child: Column(
          children: [
            Container(
              width: 61,
              height: 61,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: app.palette.primary, width: 1.5),
              ),
              child: person == null
                  ? Icon(Icons.add, size: 27, color: app.palette.primary)
                  : PersonAvatar(person, size: 53),
            ),
            const SizedBox(height: 6),
            Text(
              person == null
                  ? app.t('Додати')
                  : text(person['display_name']).split(' ').first,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10),
            ),
          ],
        ),
      ),
    ),
  );
}

class VideoClip extends StatefulWidget {
  final String url;
  final bool paused, muted;
  final ValueChanged<VideoPlayerController>? initialized;
  const VideoClip(
    this.url, {
    super.key,
    this.paused = false,
    this.muted = true,
    this.initialized,
  });
  @override
  State<VideoClip> createState() => _VideoClipState();
}

class _VideoClipState extends State<VideoClip> {
  VideoPlayerController? controller;
  String error = '';
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    controller = c;
    try {
      await c.initialize();
      await c.setVolume(widget.muted ? 0 : 1);
      if (!widget.paused) await c.play();
      widget.initialized?.call(c);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => error = app.message(e));
    }
  }

  @override
  void didUpdateWidget(VideoClip old) {
    super.didUpdateWidget(old);
    if (old.paused != widget.paused) {
      if (widget.paused) {
        controller?.pause();
      } else {
        controller?.play();
      }
    }
    if (old.muted != widget.muted) controller?.setVolume(widget.muted ? 0 : 1);
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => error.isNotEmpty
      ? Center(
          child: Text(error, style: const TextStyle(color: Colors.white)),
        )
      : controller?.value.isInitialized == true
      ? Center(
          child: AspectRatio(
            aspectRatio: controller!.value.aspectRatio,
            child: VideoPlayer(controller!),
          ),
        )
      : const Center(child: CircularProgressIndicator());
}

class StoryViewer extends StatefulWidget {
  final List<LelekaRecord> items;
  const StoryViewer(this.items, {super.key});
  @override
  State<StoryViewer> createState() => _StoryViewerState();
}

class _StoryViewerState extends StoreState<StoryViewer>
    with WidgetsBindingObserver {
  int index = 0;
  double progress = 0;
  bool paused = false, muted = true, liked = false, loaded = false;
  Timer? timer;
  VideoPlayerController? video;
  final seen = <String>{};
  String error = '';
  LelekaRecord get story => widget.items[index];
  LelekaRecord? get collection {
    for (final s in app.series) {
      if (s['id'] == story['series_id']) return s;
    }
    return null;
  }

  bool get own => story['author_id'] == app.uid;
  bool get isVideo => text(row(story['media'])['type']).startsWith('video/');
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.items.isNotEmpty) load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) setState(() => paused = true);
  }

  Future<void> load() async {
    timer?.cancel();
    progress = 0;
    video = null;
    loaded = false;
    liked = false;
    final id = text(story['id']);
    if (seen.add(id)) {
      app.db
          .rpc(
            'app_action',
            params: {
              'action': 'view_story',
              'payload': {'id': id},
            },
          )
          .catchError((Object e) => null);
    }
    if (app.uid != null) {
      app.db
          .from('story_likes')
          .select()
          .eq('story_id', id)
          .eq('user_id', app.uid!)
          .maybeSingle()
          .then((value) {
            if (mounted && text(story['id']) == id) {
              setState(() => liked = value != null);
            }
          })
          .catchError((Object e) {});
    }
    timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted || paused || !loaded) return;
      final total = isVideo
          ? (video?.value.duration.inMilliseconds ?? 30000)
          : 6000;
      if (isVideo && video?.value.hasError == true) return;
      if (isVideo && video?.value.isBuffering == true) return;
      setState(() => progress = (progress + 100 / total).clamp(0, 1));
      if (progress >= 1) next();
    });
  }

  void next() {
    if (index + 1 < widget.items.length) {
      setState(() => index++);
      load();
    } else {
      Navigator.pop(context);
    }
  }

  Future<void> views() async {
    setState(() => paused = true);
    final active =
        (DateTime.tryParse(text(story['expires_at'])) ?? DateTime.now())
            .isAfter(DateTime.now());
    List<LelekaRecord> viewers = [];
    if (active) {
      try {
        viewers = await app.db
            .from('story_views')
            .select()
            .eq('story_id', story['id']);
      } catch (e) {
        if (mounted) notice(context, app.message(e));
      }
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              '${app.t('Перегляди')}: ${story['views'] ?? 0}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            Text(
              '${app.t('Анонімні відкриття')}: ${story['anonymous_views'] ?? 0}',
            ),
            if (active)
              for (final v in viewers.where((v) => v['viewer_id'] != null))
                ListTile(
                  leading: PersonAvatar(app.person(v['viewer_id']), size: 32),
                  title: Text(text(app.person(v['viewer_id'])['display_name'])),
                ),
          ],
        ),
      ),
    );
    if (mounted) setState(() => paused = false);
  }

  Future<void> save() async {
    setState(() => paused = true);
    final title = await prompt(context, 'Назва серії', limit: 100);
    if (title != null && mounted) {
      final threads = app.threads
          .where((t) => t['author_id'] == app.uid)
          .toList();
      final thread = await showDialog<String>(
        context: context,
        builder: (c) => SimpleDialog(
          title: Text(app.t('Ланцюжки')),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, ''),
              child: Text(app.t('Без ланцюжка')),
            ),
            for (final t in threads)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(c, text(t['id'])),
                child: Text(text(t['title'])),
              ),
          ],
        ),
      );
      if (mounted && thread != null) {
        await attempt(
          context,
          () => app.action('save_story', {
            'id': story['id'],
            'title': title,
            'thread_id': thread,
          }),
        );
      }
    }
    if (mounted) setState(() => paused = false);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return const NativePage(title: 'Сторіс', body: EmptyState());
    }
    final person = app.person(story['author_id']);
    final media = row(story['media']);
    return NativePage(
      title: app.t('Сторіс'),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                for (var i = 0; i < widget.items.length; i++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: LinearProgressIndicator(
                        value: i < index
                            ? 1
                            : i == index
                            ? progress
                            : 0,
                        color: app.palette.primary,
                        backgroundColor: app.palette.border,
                        minHeight: 3,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                PersonAvatar(person, size: 34),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    text(person['display_name']),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  tooltip: app.t(paused ? 'Продовжити' : 'Пауза'),
                  onPressed: () => setState(() => paused = !paused),
                  icon: Icon(paused ? Icons.play_arrow : Icons.pause),
                ),
                if (isVideo)
                  IconButton(
                    onPressed: () => setState(() => muted = !muted),
                    icon: Icon(muted ? Icons.volume_off : Icons.volume_up),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              color: Colors.black,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (isVideo)
                    VideoClip(
                      mediaUrl(media['src']),
                      key: ValueKey(story['id']),
                      paused: paused,
                      muted: muted,
                      initialized: (v) {
                        video = v;
                        loaded = true;
                      },
                    )
                  else
                    Image.network(
                      mediaUrl(media['src']),
                      fit: BoxFit.contain,
                      frameBuilder: (_, child, frame, sync) {
                        if (frame != null) loaded = true;
                        return child;
                      },
                      errorBuilder: (_, e, s) => const Center(
                        child: Icon(Icons.broken_image, color: Colors.white),
                      ),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTap: () {
                            if (index > 0) {
                              setState(() => index--);
                              load();
                            }
                          },
                          onLongPressStart: (_) =>
                              setState(() => paused = true),
                          onLongPressEnd: (_) => setState(() => paused = false),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTap: next,
                          onLongPressStart: (_) =>
                              setState(() => paused = true),
                          onLongPressEnd: (_) => setState(() => paused = false),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (text(story['caption']).isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                text(story['caption']),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                tooltip: app.t('Вподобати'),
                onPressed: () async {
                  if (await ensureAuth(context) && context.mounted) {
                    final result = await attempt(
                      context,
                      () => app.action('like_story', {'id': story['id']}),
                    );
                    if (result != null) {
                      setState(() => liked = result['active'] == true);
                    }
                  }
                },
                icon: Icon(
                  liked ? Icons.favorite : Icons.favorite_border,
                  color: liked ? app.palette.primary : null,
                ),
              ),
              if (own)
                IconButton(
                  tooltip: app.t('Перегляди'),
                  onPressed: views,
                  icon: const Icon(Icons.visibility_outlined),
                ),
              IconButton(
                tooltip: app.t('Поділитися'),
                onPressed: () => shareLink(
                  story['series_id'] != null
                      ? 'series/${story['series_id']}'
                      : 'profile/${story['author_id']}',
                ),
                icon: const Icon(Icons.ios_share),
              ),
              if (own && story['series_id'] == null)
                IconButton(
                  tooltip: app.t('Зберегти в серію'),
                  onPressed: save,
                  icon: const Icon(Icons.bookmark_add_outlined),
                ),
              if (own)
                IconButton(
                  tooltip: app.t('Видалити'),
                  onPressed: () async {
                    setState(() => paused = true);
                    if (await confirm(context, 'Видалити') && context.mounted) {
                      final result = await attempt(context, () async {
                        await app.action('delete_story', {'id': story['id']});
                        await app.removeMedia([media]);
                        return true;
                      });
                      if (result == true && mounted) {
                        Navigator.pop(context);
                        return;
                      }
                    }
                    if (mounted) setState(() => paused = false);
                  },
                  icon: const Icon(Icons.delete_outline),
                ),
            ],
          ),
          if (collection?['thread_id'] != null)
            TextButton(
              onPressed: () async {
                setState(() => paused = true);
                await attempt(context, () async {
                  var postId = story['post_id'];
                  if (postId == null) {
                    final first = await app.db
                        .from('posts')
                        .select('id')
                        .eq('thread_id', collection!['thread_id'])
                        .order('part')
                        .limit(1)
                        .maybeSingle();
                    postId = first?['id'];
                  }
                  if (context.mounted && postId != null)
                    await go(context, ThreadPage(text(postId), single: true));
                });
              },
              child: Text(app.t('Обговорити в ланцюжку')),
            ),
        ],
      ),
    );
  }
}

class SeriesPage extends StatefulWidget {
  final String id;
  const SeriesPage(this.id, {super.key});
  @override
  State<SeriesPage> createState() => _SeriesPageState();
}

class _SeriesPageState extends StoreState<SeriesPage> {
  LelekaRecord? collection;
  List<LelekaRecord> items = [];
  String error = '';
  bool loading = true;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      collection = await app.db
          .from('series')
          .select()
          .eq('id', widget.id)
          .maybeSingle();
      items = await app.db
          .from('stories')
          .select()
          .eq('series_id', widget.id)
          .order('created_at');
    } catch (e) {
      error = app.message(e);
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) => NativePage(
    title: text(collection?['title']).isEmpty
        ? 'Серії'
        : text(collection!['title']),
    actions: [
      IconButton(
        tooltip: app.t('Надіслати в повідомлення'),
        onPressed: () => newChat(context, series: widget.id),
        icon: const Icon(Icons.send_outlined),
      ),
      IconButton(
        onPressed: () => shareLink('series/${widget.id}'),
        icon: const Icon(Icons.ios_share),
      ),
    ],
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (error.isNotEmpty) Text(error),
              if (collection?['thread_id'] != null)
                OutlinedButton.icon(
                  onPressed: () =>
                      go(context, ThreadPage(text(collection!['thread_id']))),
                  icon: const Icon(Icons.link),
                  label: Text(app.t('Читати ланцюжок')),
                ),
              const SizedBox(height: 18),
              if (items.isNotEmpty)
                FilledButton.icon(
                  onPressed: () => go(context, StoryViewer(items)),
                  icon: const Icon(Icons.play_arrow),
                  label: Text(app.t('Дивитися процес')),
                ),
              const SizedBox(height: 18),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: items.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: .65,
                ),
                itemBuilder: (c, i) {
                  final s = items[i], media = row(s['media']);
                  return InkWell(
                    onTap: () => go(context, StoryViewer(items.sublist(i))),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (text(media['type']).startsWith('video/'))
                            ColoredBox(
                              color: app.palette.accent,
                              child: const Icon(Icons.movie_outlined),
                            )
                          else
                            Image.network(
                              mediaUrl(media['src']),
                              fit: BoxFit.cover,
                              errorBuilder: (_, e, s) =>
                                  const Icon(Icons.broken_image),
                            ),
                          Align(
                            alignment: Alignment.bottomLeft,
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(8),
                              color: Colors.black54,
                              child: Text(
                                '${i + 1}. ${s['caption'] ?? ''}',
                                maxLines: 2,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              if (items.isEmpty) const EmptyState(),
            ],
          ),
  );
}
