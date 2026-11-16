import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'store.dart';
import 'widgets.dart';
import 'auth.dart';
import 'screens.dart';
import 'posts.dart';
import 'editor.dart';
import 'blog.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: apiUrl,
    publishableKey: publicKey,
    debug: false,
  );
  await app.initialize();
  runApp(const LelekaApplication());
}

class LelekaApplication extends StatelessWidget {
  const LelekaApplication({super.key});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: app,
    builder: (_, child) {
      SystemChrome.setSystemUIOverlayStyle(
        SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: app.palette.dark
              ? Brightness.light
              : Brightness.dark,
          systemNavigationBarColor: app.palette.background,
          systemNavigationBarIconBrightness: app.palette.dark
              ? Brightness.light
              : Brightness.dark,
        ),
      );
      return MaterialApp(
        title: 'LelekaThoughts',
        debugShowCheckedModeBanner: false,
        theme: app.palette.theme,
        locale: Locale(app.language),
        supportedLocales: const [Locale('uk'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const HomeShell(),
      );
    },
  );
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends StoreState<HomeShell>
    with WidgetsBindingObserver {
  int selected = 0;
  bool onboarding = false, recovery = false;
  static const labels = [
    'Стрічка',
    'Пошук',
    'Сповіщення',
    'Повідомлення',
    'Профіль',
  ];
  static const icons = [
    Icons.home_outlined,
    Icons.search,
    Icons.notifications_none,
    Icons.mail_outline,
    Icons.person_outline,
  ];
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(app.refresh());
  }

  @override
  void changed() {
    super.changed();
    if (!mounted) return;
    if (app.recovering && !recovery) {
      recovery = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (mounted) await showAuth(context, mode: 'new-password');
        recovery = false;
      });
    } else if (app.uid != null &&
        app.me == null &&
        !app.loading &&
        app.error.isEmpty &&
        !onboarding) {
      onboarding = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (mounted) {
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              fullscreenDialog: true,
              builder: (_) => const Onboarding(),
            ),
          );
        }
        onboarding = false;
      });
    }
  }

  Future<void> create() async {
    final signedIn = await ensureAuth(context);
    if (!mounted || !signedIn || app.me == null) return;
    await go(context, const Editor());
  }

  void navigate(int value) {
    setState(() => selected = value);
  }

  Widget sidebar(bool drawer) => SizedBox(
    width: 248,
    child: SidebarViewport(
      child: Material(
        color: app.palette.sidebar,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                child: Row(
                  children: [
                    const StorkMark(),
                    const SizedBox(width: 8),
                    Text(
                      'LelekaThoughts',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: app.palette.text,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: FilledButton.icon(
                  onPressed: () {
                    if (drawer) Navigator.pop(context);
                    create();
                  },
                  icon: const Icon(Icons.add),
                  label: Text(app.t('Створити')),
                ),
              ),
              const SizedBox(height: 18),
              for (var i = 0; i < 5; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 2,
                  ),
                  child: ListTile(
                    dense: true,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9),
                    ),
                    selected: selected == i,
                    selectedTileColor: app.palette.accent,
                    selectedColor: app.palette.primary,
                    leading: Icon(icons[i], size: 21),
                    title: Text(
                      app.t(labels[i]),
                      style: const TextStyle(fontSize: 14),
                    ),
                    onTap: () {
                      if (drawer) Navigator.pop(context);
                      navigate(i);
                    },
                  ),
                ),
              ListTile(
                dense: true,
                leading: const Icon(Icons.bookmark_border, size: 21),
                title: Text(
                  app.t('Збережене'),
                  style: const TextStyle(fontSize: 14),
                ),
                onTap: () async {
                  if (drawer) Navigator.pop(context);
                  if (await ensureAuth(context) && context.mounted) {
                    await go(context, const SavedPage());
                  }
                },
              ),
              ListTile(
                key: const ValueKey('my-blog-menu'),
                dense: true,
                leading: const Icon(Icons.menu_book_outlined, size: 21),
                title: Text(
                  app.t('Мій блог'),
                  style: const TextStyle(fontSize: 14),
                ),
                trailing: IconButton(
                  tooltip: app.t('Читати блоги'),
                  icon: const Icon(Icons.public, size: 20),
                  onPressed: () {
                    if (drawer) Navigator.pop(context);
                    go(context, const BlogPage(mine: false));
                  },
                ),
                onTap: () async {
                  if (drawer) Navigator.pop(context);
                  if (await ensureAuth(context) && context.mounted)
                    await go(context, const BlogPage());
                },
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: line(),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                child: Text(
                  app.t('Мої ланцюжки'),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  children: [
                    for (final th
                        in app.threads
                            .where((t) => t['author_id'] == app.uid)
                            .take(7))
                      ListTile(
                        dense: true,
                        leading: Icon(
                          Icons.link,
                          size: 16,
                          color: app.palette.primary,
                        ),
                        title: Text(
                          text(th['title']),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                        onTap: () {
                          if (drawer) Navigator.pop(context);
                          go(context, ThreadPage(text(th['id'])));
                        },
                      ),
                    if (!app.threads.any((t) => t['author_id'] == app.uid))
                      Padding(
                        padding: const EdgeInsets.all(10),
                        child: Text(
                          app.t(
                            'Створіть перший ланцюжок через «Продовжити» під власним постом.',
                          ),
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.7,
                            color: app.palette.muted,
                          ),
                        ),
                      ),
                    if (app.uid != null)
                      TextButton(
                        onPressed: () {
                          if (drawer) Navigator.pop(context);
                          go(context, const MyThreadsPage());
                        },
                        child: Text(
                          app.t('Мої чернетки'),
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                  ],
                ),
              ),
              ListTile(
                key: const ValueKey('theme-menu'),
                dense: true,
                leading: const Icon(Icons.palette_outlined, size: 20),
                title: Text(
                  app.t('Тема'),
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: Text(
                  app.t(app.palette.name),
                  style: TextStyle(fontSize: 10, color: app.palette.muted),
                ),
                onTap: () {
                  if (drawer) Navigator.pop(context);
                  pickTheme(context);
                },
              ),
              ListTile(
                dense: true,
                leading: const Icon(Icons.language, size: 20),
                title: Text(
                  app.language == 'uk' ? 'Українська' : 'English',
                  style: const TextStyle(fontSize: 12),
                ),
                onTap: () =>
                    app.setLanguage(app.language == 'uk' ? 'en' : 'uk'),
              ),
              if (app.admin)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.shield_outlined),
                  title: Text(app.t('Адмінпанель')),
                  onTap: () {
                    if (drawer) Navigator.pop(context);
                    go(context, const AdminPage());
                  },
                ),
              line(),
              if (app.me == null)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: OutlinedButton.icon(
                    key: const ValueKey('sign-in'),
                    onPressed: () {
                      if (drawer) Navigator.pop(context);
                      showAuth(context);
                    },
                    icon: const Icon(Icons.person_outline),
                    label: Text(app.t('Увійти')),
                  ),
                )
              else
                ListTile(
                  leading: PersonAvatar(app.me, size: 34),
                  title: Text(
                    text(app.me!['display_name']),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    '@${app.me!['username']}',
                    style: const TextStyle(fontSize: 10),
                  ),
                  trailing: IconButton(
                    tooltip: app.t('Налаштування'),
                    onPressed: () {
                      if (drawer) Navigator.pop(context);
                      go(context, const SettingsPage());
                    },
                    icon: const Icon(Icons.settings_outlined, size: 20),
                  ),
                  onTap: () {
                    if (drawer) Navigator.pop(context);
                    navigate(4);
                  },
                ),
            ],
          ),
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 800;
    final body = switch (selected) {
      1 => const SearchPage(),
      2 => const NotificationsPage(),
      3 => const MessagesPage(),
      4 =>
        app.uid == null
            ? const AuthRequired()
            : ProfilePage(app.uid!, key: ValueKey(app.uid), embedded: true),
      _ => const FeedPage(),
    };
    final unread = app.notices.where((n) => !yes(n['read'])).toList();
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: app.palette.gradient,
        ),
      ),
      child: Scaffold(
        drawer: wide ? null : Drawer(width: 270, child: sidebar(true)),
        appBar: AppBar(
          bottom: app.palette.id == 'vyshyvanka'
              ? const PreferredSize(
                  preferredSize: Size.fromHeight(10),
                  child: EmbroideryBand(),
                )
              : null,
          title: wide
              ? Text(app.t(labels[selected]))
              : const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    StorkMark(size: 26),
                    SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'LelekaThoughts',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
          actions: [
            IconButton(
              key: const ValueKey('create'),
              tooltip: app.t('Створити'),
              onPressed: create,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Row(
            children: [
              if (wide) sidebar(false),
              Expanded(
                child: Column(
                  children: [
                    if (!app.online)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(8),
                        color: app.palette.accent,
                        child: Text(
                          app.t('Немає інтернету. Спробуйте ще раз.'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                    if (!wide)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
                          child: Text(
                            app.t(labels[selected]),
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    Expanded(child: body),
                  ],
                ),
              ),
              if (MediaQuery.sizeOf(context).width >= 1200)
                SizedBox(
                  width: 280,
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      Text(
                        app.t('Знайди своїх'),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ...app.profiles
                          .where(
                            (p) => p['id'] != app.uid && !app.followed(p['id']),
                          )
                          .take(3)
                          .map(PersonTile.new),
                      const SizedBox(height: 24),
                      line(),
                      const SizedBox(height: 24),
                      Text(
                        app.t('Твої інтереси'),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Wrap(
                        spacing: 6,
                        children:
                            List<String>.from(
                                  app.me?['interests'] ??
                                      topics.take(3).toList(),
                                )
                                .map(
                                  (t) => Chip(
                                    label: Text(
                                      app.t(t),
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                  ),
                                )
                                .toList(),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        bottomNavigationBar: wide
            ? null
            : NavigationBar(
                selectedIndex: selected,
                onDestinationSelected: navigate,
                destinations: [
                  for (var i = 0; i < 5; i++)
                    NavigationDestination(
                      icon: Badge(
                        isLabelVisible: i == 2
                            ? unread.any((n) => n['kind'] != 'message')
                            : i == 3
                            ? unread.any((n) => n['kind'] == 'message')
                            : false,
                        child: Icon(icons[i], size: 23),
                      ),
                      label: app.t(labels[i]),
                    ),
                ],
              ),
      ),
    );
  }
}
