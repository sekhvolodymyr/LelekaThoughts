import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'palette.dart';
import 'blog_strings.dart';

typedef LelekaRecord = Map<String, dynamic>;
const apiUrl = 'https://glqsayxjvvnkmhejuqjz.supabase.co';
const publicKey = 'sb_publishable_Qj9arKK4QNhVttXhRMX1kA_qIp7U9Ed';
const website = 'https://lelekathoughts.vercel.app';
const authCallback = 'io.lelekathoughts.app://login-callback';
// Public anon JWT, required by the existing account proxy. No privileged key.
const publicAnonJwt =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImdscXNheXhqdnZua21oZWp1cWp6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTQxNjk4MDEsImV4cCI6MjEwOTc0NTgwMX0.A0HZDgs3VJQ316kxIE0RHX1EraVAMYnqhZ38A19EDcs';
const topics = [
  'Фото',
  'Дизайн',
  'Музика',
  'Письмо',
  'Розробка',
  'Кіно',
  'Мистецтво',
  'Кераміка',
  'Мода',
  'Подорожі',
];
const postSelect =
    '*,author:profiles!posts_author_id_fkey(*),thread:threads(*),likes(user_id),comments(id),reposts(user_id)';
LelekaRecord row(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};
List<LelekaRecord> rows(dynamic value) =>
    value is List ? value.map(row).toList() : [];
String text(dynamic value) => value?.toString() ?? '';
String mediaUrl(dynamic value) {
  final source = text(value);
  if (source.isEmpty) return '';
  final uri = Uri.tryParse(source);
  return uri != null && !uri.hasScheme
      ? Uri.parse('$website/').resolve(source).toString()
      : source;
}

bool yes(dynamic value) => value == true;
final app = AppStore();

class AppStore extends ChangeNotifier {
  late SharedPreferences prefs;
  SupabaseClient get db => Supabase.instance.client;
  User? get user => db.auth.currentUser;
  String? get uid => user?.id;
  LelekaRecord? get me {
    for (final p in profiles) {
      if (p['id'] == uid) return p;
    }
    return null;
  }

  List<LelekaRecord> profiles = [],
      posts = [],
      stories = [],
      series = [],
      threads = [],
      follows = [],
      saves = [],
      notices = [],
      conversations = [],
      blocks = [],
      reads = [];
  LelekaPalette palette = LelekaPalette.all.first;
  String language = 'uk', error = '';
  bool loading = true,
      admin = false,
      hasMore = true,
      online = true,
      recovering = false;
  int limit = 24, _generation = 0;
  String? _sessionOwner;
  RealtimeChannel? _channel;
  Timer? _refreshTimer;
  bool _eventNeedsFullRefresh = false;
  Future<void>? _refreshWork;
  bool _refreshAgain = false, _needsFullRefresh = false;
  Future<void> initialize() async {
    prefs = await SharedPreferences.getInstance();
    palette = LelekaPalette.fromId(prefs.getString('theme'));
    language = prefs.getString('language') ?? 'uk';
    _sessionOwner = uid;
    db.auth.onAuthStateChange.listen(
      (event) {
        if (_sessionOwner != uid) {
          _sessionOwner = uid;
          _generation++;
          profiles = [];
          posts = [];
          stories = [];
          series = [];
          threads = [];
          follows = [];
          saves = [];
          notices = [];
          conversations = [];
          blocks = [];
          reads = [];
          admin = false;
          loading = true;
          error = '';
          limit = 24;
          notifyListeners();
        }
        if (event.event == AuthChangeEvent.passwordRecovery) recovering = true;
        _subscribe();
        unawaited(refresh());
      },
      onError: (Object e) {
        error = message(e);
        notifyListeners();
      },
    );
    _subscribe();
    unawaited(refresh());
  }

  void _subscribe() {
    if (_channel != null) unawaited(db.removeChannel(_channel!));
    final channel = db.channel('native:${uid ?? 'public'}');
    void changed(PostgresChangePayload payload) {
      _eventNeedsFullRefresh =
          _eventNeedsFullRefresh || payload.table != 'posts';
      _refreshTimer?.cancel();
      _refreshTimer = Timer(const Duration(milliseconds: 400), () {
        final full = _eventNeedsFullRefresh;
        _eventNeedsFullRefresh = false;
        unawaited(refresh(postsOnly: !full));
      });
    }

    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'posts',
      callback: changed,
    );
    if (uid != null) {
      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'notifications',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'recipient_id',
          value: uid!,
        ),
        callback: changed,
      );
    }
    _channel = channel.subscribe();
  }

  Future<void> refresh({bool more = false, bool postsOnly = false}) {
    if (more) limit += 24;
    _refreshAgain = true;
    _needsFullRefresh = _needsFullRefresh || !postsOnly;
    return _refreshWork ??= _drainRefresh();
  }

  Future<void> _drainRefresh() async {
    try {
      while (_refreshAgain) {
        _refreshAgain = false;
        final full = _needsFullRefresh;
        _needsFullRefresh = false;
        await _refreshOnce(postsOnly: !full);
      }
    } finally {
      _refreshWork = null;
    }
  }

  Future<void> _refreshOnce({required bool postsOnly}) async {
    final generation = ++_generation;
    final requestedUid = uid;
    try {
      if (postsOnly) {
        final result = await Future.wait([
          db
              .from('posts')
              .select(postSelect)
              .order('created_at', ascending: false)
              .limit(limit),
          db
              .from('threads')
              .select()
              .order('created_at', ascending: false)
              .limit(100),
        ]).timeout(const Duration(seconds: 25));
        if (generation != _generation || requestedUid != uid) return;
        posts = rows(result[0]);
        threads = rows(result[1]);
        hasMore = posts.length == limit;
        error = '';
        online = true;
        return;
      }
      final result = await Future.wait<dynamic>([
        db.from('profiles').select().order('created_at').limit(200),
        db
            .from('posts')
            .select(postSelect)
            .order('created_at', ascending: false)
            .limit(limit),
        db.from('stories').select().order('created_at').limit(200),
        db
            .from('series')
            .select()
            .order('created_at', ascending: false)
            .limit(100),
        db
            .from('threads')
            .select()
            .order('created_at', ascending: false)
            .limit(100),
        db.from('follows').select().limit(3000),
        if (uid != null) db.from('saves').select() else Future.value([]),
        if (uid != null)
          db
              .from('notifications')
              .select()
              .order('created_at', ascending: false)
              .limit(100)
        else
          Future.value([]),
        if (uid != null)
          db
              .from('conversations')
              .select()
              .order('created_at', ascending: false)
        else
          Future.value([]),
        if (uid != null) db.from('blocks').select() else Future.value([]),
        if (uid != null)
          db.from('message_reads').select()
        else
          Future.value([]),
      ]).timeout(const Duration(seconds: 25));
      if (generation != _generation || requestedUid != uid) return;
      profiles = rows(result[0]);
      posts = rows(result[1]);
      stories = rows(result[2]);
      series = rows(result[3]);
      threads = rows(result[4]);
      follows = rows(result[5]);
      saves = rows(result[6]);
      notices = rows(result[7]);
      conversations = rows(result[8]);
      blocks = rows(result[9]);
      reads = rows(result[10]);
      hasMore = posts.length == limit;
      if (uid != null) {
        final own = await db
            .from('profiles')
            .select()
            .eq('id', uid!)
            .maybeSingle();
        if (generation != _generation || requestedUid != uid) return;
        if (own != null && !profiles.any((p) => p['id'] == uid)) {
          profiles.add(own);
        }
        final isAdmin = await db.rpc('my_admin_status') == true;
        if (generation != _generation || requestedUid != uid) return;
        admin = isAdmin;
      } else {
        admin = false;
      }
      error = '';
      online = true;
    } catch (e) {
      if (generation != _generation || requestedUid != uid) return;
      error = message(e);
      if (e is SocketException || e is TimeoutException) online = false;
    } finally {
      if (generation == _generation) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<dynamic> action(String name, [LelekaRecord payload = const {}]) async {
    final result = await db
        .rpc('app_action', params: {'action': name, 'payload': payload})
        .timeout(const Duration(seconds: 25));
    await refresh();
    return result;
  }

  Future<LelekaRecord> account(LelekaRecord payload) async {
    final response = await http
        .post(
          Uri.parse('$website/api/account'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization':
                'Bearer ${db.auth.currentSession?.accessToken ?? publicAnonJwt}',
          },
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 25));
    final result = row(jsonDecode(response.body));
    if (response.statusCode >= 400) {
      throw Exception(result['error'] ?? t('Не вдалося завершити дію'));
    }
    return result;
  }

  Future<void> signIn(String login, String password) async {
    if (login.contains('@') && !login.startsWith('@')) {
      await db.auth.signInWithPassword(email: login.trim(), password: password);
    } else {
      final result = await account({
        'action': 'username_login',
        'username': login.trim().replaceFirst(RegExp(r'^@'), ''),
        'password': password,
      });
      await db.auth.setSession(text(row(result['session'])['refresh_token']));
    }
    await refresh();
  }

  Future<void> google() async {
    final response = await http
        .get(
          Uri.parse('$apiUrl/auth/v1/settings'),
          headers: {'apikey': publicKey},
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception(t('Не вдалося підключитися до сервісу входу'));
    }
    if (row(jsonDecode(response.body))['external']?['google'] != true) {
      throw Exception(
        t('Вхід через Google ще не налаштовано. Скористайтеся email.'),
      );
    }
    await db.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: authCallback,
      authScreenLaunchMode: LaunchMode.externalApplication,
    );
  }

  Future<LelekaRecord> upload(XFile file, {double? duration}) async {
    final status = row(
      await db.rpc(
        'app_action',
        params: {'action': 'upload_status', 'payload': {}},
      ),
    );
    if (status['enabled'] != true) {
      throw Exception(t('Завантаження медіа тимчасово призупинено'));
    }
    final bytes = await file.readAsBytes();
    if (bytes.length > 50 * 1024 * 1024) {
      throw Exception(t('Один файл має бути до 50 МБ'));
    }
    final type =
        lookupMimeType(file.name, headerBytes: bytes.take(20).toList()) ??
        'application/octet-stream';
    if (!type.startsWith('image/') && !type.startsWith('video/')) {
      throw Exception(t('Оберіть фото або відео'));
    }
    if (type.startsWith('video/') &&
        (duration == null || duration <= 0 || duration > 30)) {
      throw Exception(t('Відео має тривати до 30 секунд'));
    }
    final response = await http
        .post(
          Uri.parse('$apiUrl/functions/v1/media'),
          headers: {
            'apikey': publicKey,
            'Authorization': 'Bearer ${db.auth.currentSession?.accessToken}',
            'Content-Type': type,
          },
          body: bytes,
        )
        .timeout(const Duration(seconds: 90));
    final media = row(jsonDecode(response.body));
    if (response.statusCode != 200)
      throw Exception(media['error'] ?? 'Upload failed');
    return {...media, 'duration': ?duration};
  }

  Future<void> removeMedia(List<LelekaRecord> media) async {
    final paths = media
        .map((m) => text(m['path']))
        .where((p) => p.isNotEmpty)
        .toList();
    if (paths.isNotEmpty) await db.storage.from('media').remove(paths);
  }

  LelekaRecord person(dynamic id) => profiles.firstWhere(
    (p) => p['id'] == id,
    orElse: () => {
      'display_name': t('Видалений користувач'),
      'username': 'deleted',
    },
  );
  bool followed(dynamic id) =>
      follows.any((f) => f['follower_id'] == uid && f['following_id'] == id);
  bool saved(dynamic id) => saves.any((s) => s['post_id'] == id);
  void markChatRead(String id) {
    var changed = false;
    for (final n in notices) {
      if (n['kind'] == 'message' && n['target'] == id && !yes(n['read'])) {
        n['read'] = true;
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  void setTheme(String id) {
    palette = LelekaPalette.fromId(id);
    unawaited(prefs.setString('theme', palette.id));
    notifyListeners();
  }

  void setLanguage(String value) {
    language = value;
    unawaited(prefs.setString('language', value));
    notifyListeners();
  }

  String t(String value) =>
      language == 'en' ? (translations[value] ?? value) : value;
  String message(Object e) {
    if (e is SocketException ||
        e is TimeoutException ||
        e is http.ClientException) {
      return t('Немає інтернету. Спробуйте ще раз.');
    }
    if (e is AuthException) return e.message;
    if (e is PostgrestException) return e.message;
    return e.toString().replaceFirst('Exception: ', '');
  }
}

const translations = <String, String>{
  ...blogTranslations,
  "Оформлення": "Appearance",
  "Захід сонця": "Sunset",
  "Лаванда": "Lavender",
  "Океан": "Ocean",
  "Ліс": "Forest",
  "Застосовується одразу та зберігається на цьому пристрої.":
      "Applies immediately and is saved on this device.",
  "Вхід через Google ще не налаштовано. Скористайтеся email або спробуйте пізніше.":
      "Google sign-in is not set up yet. Use email or try again later.",
  "Не вдалося підключитися до сервісу входу. Перевірте інтернет і спробуйте ще раз.": "Could not connect to the sign-in service. Check your connection and try again.",
  "Не вдалося завершити вхід. Спробуйте ще раз.":
      "Could not complete sign-in. Please try again.",
  "Вхід скасовано. Можна спробувати ще раз або увійти через email.":
      "Sign-in was cancelled. Try again or sign in with email.",
  "Посилання для входу недійсне або застаріло. Запросіть нове.":
      "This sign-in link is invalid or has expired. Request a new one.",
  "Створити": "Create",
  "Стрічка": "Feed",
  "Пошук": "Search",
  "Сповіщення": "Notifications",
  "Повідомлення": "Messages",
  "Збережене": "Saved",
  "Профіль": "Profile",
  "Мої ланцюжки": "My threads",
  "Для тебе": "For you",
  "Підписки": "Following",
  "Історії, що тривають": "Stories in progress",
  "Знайди своїх": "Find your people",
  "Твої інтереси": "Your interests",
  "Пошук креаторів": "Search creators",
  "З чого починається твоя ідея?": "Where does your idea begin?",
  "Додати": "Add",
  "Увійти": "Sign in",
  "Вийти": "Sign out",
  "Тема": "Theme",
  "Налаштування": "Settings",
  "Пост": "Post",
  "Сторіс": "Story",
  "Люди": "People",
  "Пости": "Posts",
  "Ланцюжки": "Threads",
  "Серії": "Series",
  "Репости": "Reposts",
  "Продовжити": "Continue",
  "Читати від початку": "Read from the beginning",
  "Продовження ланцюжка": "Thread continuation",
  "Частина": "Part",
  "Змінено": "Edited",
  "Пост видалено": "Post deleted",
  "Дивитися процес": "Watch the process",
  "Читати ланцюжок": "Read the thread",
  "Обговорити в ланцюжку": "Discuss in thread",
  "Коментарі": "Comments",
  "Написати коментар…": "Write a comment…",
  "Відповісти": "Reply",
  "Показати відповіді": "Show replies",
  "Видалити": "Delete",
  "Редагувати": "Edit",
  "Закріпити": "Pin",
  "Поскаржитися": "Report",
  "Заблокувати": "Block",
  "Репост": "Repost",
  "Цитувати": "Quote",
  "Опублікувати": "Publish",
  "Зберегти": "Save",
  "Скасувати": "Cancel",
  "Закрити": "Close",
  "Підписатися": "Follow",
  "Ви підписані": "Following",
  "Підписники": "Followers",
  "Підписки профілю": "Following",
  "Біо": "Bio",
  "Ім’я": "Name",
  "Посилання": "Website",
  "Поки порожньо": "Nothing here yet",
  "Немає інтернету": "You are offline",
  "Текст збережено на цьому пристрої": "Text is saved on this device",
  "Завантажити ще": "Load more",
  "Пошук…": "Search…",
  "Напишіть повідомлення…": "Write a message…",
  "Надіслати": "Send",
  "Прийняти": "Accept",
  "Відхилити": "Decline",
  "Запит на спілкування": "Message request",
  "Очікує на прийняття": "Waiting for acceptance",
  "Прочитати все": "Mark all as read",
  "Демонстраційний профіль": "Demo profile",
  "Приклад контенту": "Sample content",
  "Демонстраційні приклади": "Demo examples",
  "Про LelekaThoughts": "About LelekaThoughts",
  "Розкажіть про свою ідею": "Share your idea",
  "Увійдіть, щоб долучитися": "Sign in to join in",
  "Завантаження…": "Loading…",
  "Немає результатів": "No results",
  "Новий діалог": "New conversation",
  "Адмінпанель": "Moderation",
  "Перегляди": "Views",
  "Зберегти в серію": "Save to series",
  "Назва серії": "Series title",
  "Без серії": "No series",
  "Без ланцюжка": "No thread",
  "Назва ланцюжка": "Thread title",
  "До 3 тем": "Up to 3 topics",
  "Фото": "Photo",
  "Дизайн": "Design",
  "Музика": "Music",
  "Письмо": "Writing",
  "Розробка": "Development",
  "Кіно": "Film",
  "Мистецтво": "Art",
  "Кераміка": "Ceramics",
  "Мода": "Fashion",
  "Подорожі": "Travel",
  "Коментар видалено": "Comment deleted",
  "Видалений користувач": "Deleted user",
  "Поділитися": "Share",
  "Додайте першу публікацію": "Create your first post",
  "Закріплено": "Pinned",
  "Вподобати": "Like",
  "Серія сторіс": "Story series",
  "Вподобання": "Likes",
  "Читати": "Read",
  "Відкрити меню": "Open menu",
  "Повернутися": "Back",
  "Запит відхилено": "Request declined",
  "Не вдалося завантажити дані": "Could not load data",
  "Спробувати ще": "Try again",
  "Ваші теми": "Your topics",
  "Далі": "Continue",
  "Завершити реєстрацію": "Complete sign-up",
  "Дата народження": "Date of birth",
  "Унікальний @нік": "Unique @username",
  "Мінімальний вік — 16 років": "Minimum age is 16",
  "Email або @нік": "Email or @username",
  "Пароль": "Password",
  "Реєстрація": "Sign up",
  "Код на email": "Email code",
  "Відновити пароль": "Reset password",
  "Надіслати код": "Send code",
  "Підтвердити код": "Verify code",
  "Новий пароль": "New password",
  "Змінити пароль": "Change password",
  "Продовжити з Google": "Continue with Google",
  "Налаштування входу": "Sign-in setup",
  "Підтвердіть email за посиланням у листі":
      "Confirm your email using the link in your inbox",
  "Перевірте пошту": "Check your inbox",
  "Немає нових сповіщень": "No notifications yet",
  "Мої чернетки": "My drafts",
  "Повернути чернетку": "Restore draft",
  "Видалити акаунт": "Delete account",
  "Поширити пост": "Share post",
  "Поширити серію": "Share series",
  "Розблокувати": "Unblock",
  "Заблоковані користувачі": "Blocked users",
  "Анонімні відкриття": "Anonymous opens",
  "Авторизовані глядачі": "Signed-in viewers",
  "Підписуйтесь на креаторів, щоб бачити їхні пости тут.":
      "Follow creators to see their posts here.",
  "Збережіть пост або ланцюжок, щоб повернутися до нього.":
      "Save a post or thread to come back to it.",
  "Почніть із пошуку людини або відкрийте її профіль.":
      "Find someone or open their profile to start.",
  "Скаргу надіслано": "Report submitted",
  "Збережено": "Saved",
  "Готово": "Done",
  "Зберігаємо…": "Saving…",
  "Помилка": "Error",
  "Завантажте фото або відео до 30 секунд":
      "Upload a photo or video up to 30 seconds",
  "До 4 фото": "Up to 4 photos",
  "Обговорення": "Discussion",
  "Перший пост": "First post",
  "Скарги": "Reports",
  "Приховати": "Hide",
  "Призупинити акаунт": "Suspend account",
  "Розглянуто": "Resolved",
  "Відкрити": "Open",
  "Оберіть інтереси": "Choose interests",
  "Мова": "Language",
  "Світла": "Light",
  "Темна": "Dark",
  "Увійти, щоб написати": "Sign in to message",
  "Створіть перший ланцюжок через «Продовжити» під власним постом.":
      "Create a thread by choosing Continue on your post.",
  "Причина": "Reason",
  "Код із листа": "Code from email",
  "Немає інтернету. Спробуйте ще раз.": "You are offline. Please try again.",
  "Вхід через Google ще не налаштовано. Скористайтеся email.":
      "Google sign-in is not set up yet. Use email.",
  "Пауза": "Pause",
  "Відео має тривати до 30 секунд": "Video must be at most 30 seconds",
  "Оберіть фото або відео": "Choose a photo or video",
  "Завантаження медіа тимчасово призупинено":
      "Media uploads are temporarily paused",
  "Один файл має бути до 50 МБ": "A file must be at most 50 MB",
  "Пароль має містити щонайменше 8 символів":
      "Password must contain at least 8 characters",
  "Нік: 3–30 латинських літер, цифр, крапок або підкреслень":
      "Username: 3–30 Latin letters, digits, dots or underscores",
  "Забагато символів": "Too many characters",
  "Не вдалося підключитися до сервісу входу":
      "Could not connect to the sign-in service",
  "Надіслати в повідомлення": "Send in a message",
};
