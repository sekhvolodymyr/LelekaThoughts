import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:share_plus/share_plus.dart';

import 'store.dart';
import 'palette.dart';

abstract class StoreState<T extends StatefulWidget> extends State<T> {
  @override
  void initState() {
    super.initState();
    app.addListener(changed);
  }

  void changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    app.removeListener(changed);
    super.dispose();
  }
}

Future<void> go(BuildContext context, Widget page) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
void notice(BuildContext context, String value) {
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }
}

Future<T?> attempt<T>(BuildContext context, Future<T> Function() task) async {
  try {
    return await task();
  } catch (e) {
    if (context.mounted) notice(context, app.message(e));
    return null;
  }
}

Future<bool> confirm(BuildContext context, String title) => showDialog<bool>(
  context: context,
  builder: (c) => AlertDialog(
    title: Text(app.t(title)),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(c, false),
        child: Text(app.t('Скасувати')),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(c, true),
        child: Text(app.t('Готово')),
      ),
    ],
  ),
).then((v) => v ?? false);
Future<String?> prompt(
  BuildContext context,
  String label, {
  String initial = '',
  int limit = 1000,
}) async {
  final controller = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(app.t(label)),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: limit,
        minLines: 1,
        maxLines: 4,
        decoration: InputDecoration(labelText: app.t(label)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: Text(app.t('Скасувати')),
        ),
        FilledButton(
          onPressed: () {
            if (controller.text.trim().isNotEmpty) {
              Navigator.pop(c, controller.text.trim());
            }
          },
          child: Text(app.t('Готово')),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}

Future<void> shareLink(String route) => SharePlus.instance
    .share(ShareParams(text: '$website/#/$route'))
    .then((_) {});
String ago(dynamic value) {
  final date = DateTime.tryParse(text(value));
  if (date == null) return '';
  final diff = DateTime.now().difference(date);
  if (diff.inMinutes < 60) {
    return '${diff.inMinutes < 1 ? 1 : diff.inMinutes} ${app.language == 'uk' ? 'хв' : 'min'}';
  }
  if (diff.inHours < 24) {
    return '${diff.inHours} ${app.language == 'uk' ? 'год' : 'h'}';
  }
  return '${date.day}.${date.month.toString().padLeft(2, '0')}';
}

Widget line() => Divider(height: 1, color: app.palette.border);
Widget field(
  TextEditingController controller,
  String label, {
  bool password = false,
  int? maxLength,
  int lines = 1,
  TextInputType? keyboard,
  void Function(String)? onChanged,
  String? hint,
  bool enabled = true,
}) => TextField(
  controller: controller,
  obscureText: password,
  maxLength: maxLength,
  minLines: lines,
  maxLines: lines == 1 ? 1 : lines + 3,
  keyboardType: keyboard,
  enabled: enabled,
  onChanged: onChanged,
  decoration: InputDecoration(labelText: app.t(label), hintText: hint),
);

class NativePage extends StatelessWidget {
  final String title;
  final Widget body;
  final List<Widget>? actions;
  const NativePage({
    super.key,
    required this.title,
    required this.body,
    this.actions,
  });
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: app.palette.gradient,
      ),
    ),
    child: Scaffold(
      appBar: AppBar(title: Text(app.t(title)), actions: actions),
      body: SafeArea(top: false, child: body),
    ),
  );
}

class StorkMark extends StatelessWidget {
  final double size;
  const StorkMark({super.key, this.size = 34});
  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    'assets/stork.svg',
    width: size,
    height: size,
    colorFilter: ColorFilter.mode(app.palette.text, BlendMode.srcIn),
  );
}

class PersonAvatar extends StatelessWidget {
  final LelekaRecord? person;
  final double size;
  const PersonAvatar(this.person, {super.key, this.size = 40});
  @override
  Widget build(BuildContext context) {
    final name = text(person?['display_name']);
    final url = mediaUrl(person?['avatar']);
    final fallback = Center(
      child: Text(
        name.isEmpty
            ? 'L'
            : name.substring(0, name.length > 1 ? 2 : 1).toUpperCase(),
        style: TextStyle(color: app.palette.primary, fontSize: size * .3),
      ),
    );
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: app.palette.accent,
        shape: BoxShape.circle,
      ),
      child: url.isEmpty
          ? fallback
          : Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, e, s) => fallback,
            ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final String title;
  final String? detail;
  final Widget? action;
  const EmptyState({
    super.key,
    this.title = 'Поки порожньо',
    this.detail,
    this.action,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome_outlined, size: 32, color: app.palette.muted),
          const SizedBox(height: 14),
          Text(
            app.t(title),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          if (detail != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                app.t(detail!),
                textAlign: TextAlign.center,
                style: TextStyle(color: app.palette.muted),
              ),
            ),
          if (action != null)
            Padding(padding: const EdgeInsets.only(top: 18), child: action!),
        ],
      ),
    ),
  );
}

class TopicPicker extends StatelessWidget {
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;
  final int max;
  const TopicPicker({
    super.key,
    required this.selected,
    required this.onChanged,
    this.max = 12,
  });
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 7,
    runSpacing: 2,
    children: topics
        .map(
          (topic) => FilterChip(
            label: Text(app.t(topic), style: const TextStyle(fontSize: 12)),
            selected: selected.contains(topic),
            onSelected: (v) {
              if (!v) {
                onChanged(selected.where((s) => s != topic).toList());
              } else if (selected.length < max)
                onChanged([...selected, topic]);
            },
          ),
        )
        .toList(),
  );
}

class NativeThemePicker extends StatelessWidget {
  const NativeThemePicker({super.key});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        app.t('Оформлення'),
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 17),
      ),
      const SizedBox(height: 14),
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.5,
        children: LelekaPalette.all
            .map(
              (p) => Semantics(
                selected: app.palette.id == p.id,
                button: true,
                label: app.t(p.name),
                child: InkWell(
                  key: ValueKey('theme-${p.id}'),
                  onTap: () => app.setTheme(p.id),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: app.palette.background,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: app.palette.id == p.id
                            ? app.palette.primary
                            : app.palette.border,
                        width: app.palette.id == p.id ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(7),
                              gradient: LinearGradient(
                                colors: [p.sidebar, p.gradient.last],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 7),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                app.t(p.name),
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                            if (app.palette.id == p.id)
                              Icon(
                                Icons.check,
                                size: 16,
                                color: app.palette.primary,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    ],
  );
}

Future<void> pickTheme(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (c) => AnimatedBuilder(
    animation: app,
    builder: (_, child) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const NativeThemePicker(),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.pop(c),
              child: Text(app.t('Готово')),
            ),
          ],
        ),
      ),
    ),
  ),
);
