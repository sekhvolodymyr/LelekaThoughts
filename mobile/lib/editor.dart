import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import 'store.dart';
import 'widgets.dart';

class Editor extends StatefulWidget {
  final LelekaRecord? parent, edit, quote;
  final bool story;
  const Editor({
    super.key,
    this.parent,
    this.edit,
    this.quote,
    this.story = false,
  });
  @override
  State<Editor> createState() => _EditorState();
}

class _EditorState extends StoreState<Editor> {
  late final body = TextEditingController(text: text(widget.edit?['body']));
  final title = TextEditingController(), seriesTitle = TextEditingController();
  late bool story = widget.story;
  late List<String> selected = List<String>.from(
    widget.edit?['topics'] ?? widget.parent?['topics'] ?? [],
  );
  late List<LelekaRecord> existing = rows(widget.edit?['media']);
  final files = <XFile>[];
  double? videoDuration;
  String seriesId = '', threadId = '', discussion = '', error = '';
  bool busy = false, ready = false, dirty = false;
  Timer? timer;
  String get slot =>
      widget.parent == null ? 'post' : 'continue:${widget.parent!['id']}';
  String get localKey => 'native.draft:${app.uid}:$slot';
  @override
  void initState() {
    super.initState();
    loadDraft();
  }

  Future<void> loadDraft() async {
    if (widget.edit != null || widget.quote != null) {
      ready = true;
      return;
    }
    final local = app.prefs.getString(localKey);
    if (local != null) {
      try {
        final draft = row(jsonDecode(local));
        body.text = text(draft['body']);
        selected = List<String>.from(draft['topics'] ?? []);
      } catch (e) {
        /* Retain the local state for a manual retry. */
      }
    }
    try {
      final draft = await app.db
          .from('drafts')
          .select()
          .eq('slot', slot)
          .maybeSingle();
      if (mounted && !dirty && local == null && draft != null) {
        body.text = text(draft['body']);
        selected = List<String>.from(draft['topics'] ?? []);
      }
    } catch (e) {
      /* Retain the local state for a manual retry. */
    }
    if (mounted) setState(() => ready = true);
  }

  void saveDraft() {
    dirty = true;
    if (!ready || story || widget.edit != null || widget.quote != null) return;
    final draft = {
      'slot': slot,
      'body': body.text,
      'topics': selected,
      'parent_id': widget.parent?['id'],
    };
    unawaited(app.prefs.setString(localKey, jsonEncode(draft)));
    timer?.cancel();
    timer = Timer(const Duration(milliseconds: 900), () {
      app.db
          .rpc('app_action', params: {'action': 'draft', 'payload': draft})
          .catchError((Object e) => null);
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    body.dispose();
    title.dispose();
    seriesTitle.dispose();
    super.dispose();
  }

  Future<void> pick({bool video = false}) async {
    await attempt(context, () async {
      if (story) {
        final file = video
            ? await ImagePicker().pickVideo(
                source: ImageSource.gallery,
                maxDuration: const Duration(seconds: 30),
              )
            : await ImagePicker().pickImage(
                source: ImageSource.gallery,
                maxWidth: 1800,
                imageQuality: 85,
              );
        if (file == null) return;
        double? duration;
        if (video) {
          final controller = VideoPlayerController.file(File(file.path));
          try {
            await controller.initialize();
            duration = controller.value.duration.inMilliseconds / 1000;
            if (duration <= 0 || duration > 30) {
              throw Exception(app.t('Відео має тривати до 30 секунд'));
            }
          } finally {
            await controller.dispose();
          }
        }
        if (mounted) {
          setState(() {
            files.clear();
            files.add(file);
            videoDuration = duration;
          });
        }
      } else {
        final picked = await ImagePicker().pickMultiImage(
          maxWidth: 1800,
          imageQuality: 85,
        );
        if (files.length + existing.length + picked.length > 4) {
          throw Exception(app.t('До 4 фото'));
        }
        if (mounted) setState(() => files.addAll(picked));
      }
    });
  }

  Future<void> publish() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = '';
    });
    timer?.cancel();
    final uploaded = <LelekaRecord>[];
    bool committed = false;
    try {
      if (body.text.length > (story ? 300 : 1000)) {
        throw Exception(app.t('Забагато символів'));
      }
      if (story && files.isEmpty) {
        throw Exception(app.t('Оберіть фото або відео'));
      }
      if (!story &&
          body.text.trim().isEmpty &&
          files.isEmpty &&
          existing.isEmpty) {
        throw Exception(app.t('Розкажіть про свою ідею'));
      }
      if (widget.parent != null &&
          widget.parent!['thread_id'] == null &&
          title.text.trim().isEmpty) {
        throw Exception(app.t('Назва ланцюжка'));
      }
      for (final file in files) {
        uploaded.add(await app.upload(file, duration: videoDuration));
      }
      if (story) {
        await app.action('story', {
          'media': uploaded.first,
          'caption': body.text,
          'series_id': seriesId,
          'series_title': seriesTitle.text,
          'thread_id': threadId,
          'post_id': discussion,
        });
      } else {
        await app.action(widget.edit == null ? 'post' : 'edit_post', {
          'id': widget.edit?['id'],
          'body': body.text,
          'topics': selected,
          'media': [...existing, ...uploaded],
          'parent_id': widget.parent?['id'],
          'thread_title': title.text,
          'quote_id': widget.quote?['id'],
          'slot': slot,
        });
      }
      committed = true;
      if (widget.edit != null) {
        final removed = rows(widget.edit!['media'])
            .where((m) => !existing.any((x) => x['path'] == m['path']))
            .toList();
        try {
          await app.removeMedia(removed);
        } catch (e) {
          if (mounted) {
            notice(
              context,
              app.t('Пост збережено; очищення старих фото потребує повторення'),
            );
          }
        }
      }
      await app.prefs.remove(localKey);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!committed && e is! TimeoutException) {
        try {
          await app.removeMedia(uploaded);
        } catch (ignored) {
          /* A later cleanup can retry removing orphaned media. */
        }
      }
      if (mounted) setState(() => error = app.message(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mySeries = app.series
            .where((s) => s['author_id'] == app.uid)
            .toList(),
        myThreads = app.threads
            .where((s) => s['author_id'] == app.uid)
            .toList();
    Widget select(
      String label,
      String value,
      List<LelekaRecord> choices,
      ValueChanged<String> onChanged,
    ) => DropdownButtonFormField<String>(
      initialValue: value.isEmpty ? null : value,
      isExpanded: true,
      decoration: InputDecoration(labelText: app.t(label)),
      items: [
        DropdownMenuItem(
          value: '',
          child: Text(
            app.t(
              label == 'Серія сторіс'
                  ? 'Без серії'
                  : label == 'Обговорення'
                  ? 'Перший пост'
                  : 'Без ланцюжка',
            ),
          ),
        ),
        ...choices.map(
          (s) => DropdownMenuItem(
            value: text(s['id']),
            child: Text(
              text(s['title'] ?? s['body']),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
      onChanged: busy ? null : (v) => onChanged(v ?? ''),
    );
    return NativePage(
      title: widget.edit != null
          ? 'Редагувати'
          : widget.parent != null
          ? 'Продовжити'
          : 'Створити',
      actions: [
        TextButton(
          key: const ValueKey('publish'),
          onPressed: busy ? null : publish,
          child: Text(app.t(busy ? 'Завантаження…' : 'Опублікувати')),
        ),
      ],
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (widget.parent == null &&
              widget.edit == null &&
              widget.quote == null)
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(value: false, label: Text(app.t('Пост'))),
                ButtonSegment(value: true, label: Text(app.t('Сторіс'))),
              ],
              selected: {story},
              onSelectionChanged: busy
                  ? null
                  : (v) => setState(() {
                      story = v.first;
                      files.clear();
                      videoDuration = null;
                    }),
            ),
          const SizedBox(height: 20),
          Row(
            children: [
              PersonAvatar(app.me),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      text(app.me?['display_name']),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '@${app.me?['username'] ?? ''}',
                      style: TextStyle(fontSize: 12, color: app.palette.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (widget.parent != null && widget.parent!['thread_id'] == null) ...[
            field(title, 'Назва ланцюжка', maxLength: 100),
            const SizedBox(height: 12),
          ],
          if (widget.parent != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                text(
                  row(widget.parent!['thread'])['title'] ??
                      widget.parent!['body'],
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: app.palette.muted, fontSize: 12),
              ),
            ),
          TextField(
            key: const ValueKey('compose-body'),
            controller: body,
            autofocus: true,
            minLines: 5,
            maxLines: 12,
            maxLength: story ? 300 : 1000,
            onChanged: (_) => saveDraft(),
            decoration: InputDecoration(
              hintText: app.t('З чого починається твоя ідея?'),
            ),
          ),
          if (widget.quote != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: app.palette.border),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                text(widget.quote!['body']),
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          if (existing.isNotEmpty || files.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final m in existing)
                    preview(
                      Image.network(text(m['src']), fit: BoxFit.cover),
                      () => setState(() => existing.remove(m)),
                    ),
                  for (final f in files)
                    preview(
                      story && videoDuration != null
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.movie_outlined, size: 30),
                                  Text(
                                    '${videoDuration!.toStringAsFixed(1)} s',
                                  ),
                                ],
                              ),
                            )
                          : Image.file(File(f.path), fit: BoxFit.cover),
                      () => setState(() => files.remove(f)),
                    ),
                ],
              ),
            ),
          Row(
            children: [
              TextButton.icon(
                onPressed: busy ? null : pick,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: Text(app.t('Фото')),
              ),
              if (story)
                TextButton.icon(
                  onPressed: busy ? null : () => pick(video: true),
                  icon: const Icon(Icons.video_library_outlined),
                  label: const Text('≤30 s'),
                ),
            ],
          ),
          if (!story && widget.parent == null) ...[
            const SizedBox(height: 14),
            Text(app.t('До 3 тем')),
            TopicPicker(
              selected: selected,
              max: 3,
              onChanged: (v) {
                setState(() => selected = v);
                saveDraft();
              },
            ),
          ],
          if (story) ...[
            const SizedBox(height: 18),
            select(
              'Серія сторіс',
              seriesId,
              mySeries,
              (v) => setState(() {
                seriesId = v;
                threadId = text(
                  mySeries.firstWhere(
                    (s) => s['id'] == v,
                    orElse: () => {},
                  )['thread_id'],
                );
                discussion = '';
              }),
            ),
            const SizedBox(height: 18),
            if (seriesId.isEmpty)
              field(
                seriesTitle,
                'Назва серії',
                maxLength: 100,
                onChanged: (_) => setState(() {}),
              ),
            if (seriesId.isNotEmpty || seriesTitle.text.trim().isNotEmpty) ...[
              const SizedBox(height: 18),
              if (seriesId.isEmpty)
                select(
                  'Ланцюжки',
                  threadId,
                  myThreads,
                  (v) => setState(() {
                    threadId = v;
                    discussion = '';
                  }),
                ),
              if (threadId.isNotEmpty) ...[
                const SizedBox(height: 18),
                select(
                  'Обговорення',
                  discussion,
                  app.posts
                      .where(
                        (p) => p['thread_id'] == threadId && !yes(p['deleted']),
                      )
                      .toList()
                    ..sort(
                      (a, b) => (a['part'] as int? ?? 0).compareTo(
                        b['part'] as int? ?? 0,
                      ),
                    ),
                  (v) => setState(() => discussion = v),
                ),
              ],
            ],
          ],
          if (error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (!app.online) Text(app.t('Немає інтернету. Спробуйте ще раз.')),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: busy ? null : publish,
            child: Text(app.t(busy ? 'Завантаження…' : 'Опублікувати')),
          ),
        ],
      ),
    );
  }

  Widget preview(Widget child, VoidCallback remove) => SizedBox(
    width: 140,
    height: 120,
    child: Stack(
      fit: StackFit.expand,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: ColoredBox(color: app.palette.accent, child: child),
        ),
        Positioned(
          right: 0,
          top: 0,
          child: IconButton.filledTonal(
            onPressed: busy ? null : remove,
            icon: const Icon(Icons.close, size: 16),
          ),
        ),
      ],
    ),
  );
}
