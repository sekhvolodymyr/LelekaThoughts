import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'store.dart';
import 'widgets.dart';

Future<bool> ensureAuth(BuildContext context) async {
  if (app.uid != null) return true;
  await showAuth(context);
  return app.uid != null;
}

Future<void> showAuth(BuildContext context, {String mode = 'login'}) =>
    showDialog<void>(
      context: context,
      builder: (c) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 470),
          child: AuthPanel(initialMode: mode),
        ),
      ),
    );

class AuthPanel extends StatefulWidget {
  final String initialMode;
  const AuthPanel({super.key, this.initialMode = 'login'});
  @override
  State<AuthPanel> createState() => _AuthPanelState();
}

class _AuthPanelState extends StoreState<AuthPanel> {
  final email = TextEditingController(),
      password = TextEditingController(),
      code = TextEditingController(),
      name = TextEditingController(),
      username = TextEditingController();
  late String mode;
  bool busy = false, sent = false;
  String error = '';
  @override
  void initState() {
    super.initState();
    mode = widget.initialMode;
  }

  @override
  void dispose() {
    for (final c in [email, password, code, name, username]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> run(Future<void> Function() task) async {
    setState(() {
      busy = true;
      error = '';
    });
    try {
      await task();
    } catch (e) {
      if (mounted) setState(() => error = app.message(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> submit() => run(() async {
    if (mode == 'login') {
      await app.signIn(email.text, password.text);
      if (mounted) Navigator.pop(context);
    } else if (mode == 'signup') {
      if (password.text.length < 8) {
        throw Exception(app.t('Пароль має містити щонайменше 8 символів'));
      }
      if (!RegExp(r'^[a-z0-9_.]{3,30}$').hasMatch(username.text)) {
        throw Exception(
          app.t('Нік: 3–30 латинських літер, цифр, крапок або підкреслень'),
        );
      }
      await app.db.auth.signUp(
        email: email.text.trim(),
        password: password.text,
        data: {
          'display_name': name.text.trim(),
          'username': username.text.trim(),
        },
        emailRedirectTo: website,
      );
      setState(() => sent = true);
    } else if (mode == 'otp') {
      if (sent) {
        await app.db.auth.verifyOTP(
          email: email.text.trim(),
          token: code.text.trim(),
          type: OtpType.email,
        );
        await app.refresh();
        if (mounted) Navigator.pop(context);
      } else {
        await app.db.auth.signInWithOtp(
          email: email.text.trim(),
          emailRedirectTo: website,
        );
        setState(() => sent = true);
      }
    } else if (mode == 'new-password') {
      if (password.text.length < 8) {
        throw Exception(app.t('Пароль має містити щонайменше 8 символів'));
      }
      await app.db.auth.updateUser(UserAttributes(password: password.text));
      app.recovering = false;
      if (mounted) Navigator.pop(context);
    } else {
      await app.db.auth.resetPasswordForEmail(
        email.text.trim(),
        redirectTo: website,
      );
      setState(() => sent = true);
    }
  });
  @override
  Widget build(BuildContext context) {
    final title = mode == 'signup'
        ? 'Реєстрація'
        : mode == 'otp'
        ? 'Код на email'
        : mode == 'reset'
        ? 'Відновити пароль'
        : mode == 'new-password'
        ? 'Новий пароль'
        : 'Увійти';
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    app.t(title),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const Text('LelekaThoughts'),
            const SizedBox(height: 18),
            if (mode != 'new-password') ...[
              OutlinedButton.icon(
                onPressed: busy ? null : () => run(() => app.google()),
                icon: const Text(
                  'G',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                label: Text(app.t('Продовжити з Google')),
              ),
              Wrap(
                spacing: 4,
                children: [
                  for (final value in ['login', 'signup', 'otp'])
                    TextButton(
                      onPressed: () => setState(() {
                        mode = value;
                        sent = false;
                        error = '';
                      }),
                      style: TextButton.styleFrom(
                        foregroundColor: mode == value
                            ? app.palette.primary
                            : app.palette.muted,
                      ),
                      child: Text(
                        app.t(
                          value == 'login'
                              ? 'Увійти'
                              : value == 'signup'
                              ? 'Реєстрація'
                              : 'Код на email',
                        ),
                      ),
                    ),
                ],
              ),
            ],
            if (error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Text(
                  error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (mode != 'new-password')
              field(
                email,
                mode == 'login' ? 'Email або @нік' : 'Email',
                keyboard: TextInputType.emailAddress,
              ),
            if (['login', 'signup', 'new-password'].contains(mode)) ...[
              const SizedBox(height: 16),
              field(password, 'Пароль', password: true),
            ],
            if (mode == 'signup') ...[
              const SizedBox(height: 16),
              field(name, 'Ім’я', maxLength: 60),
              const SizedBox(height: 16),
              field(username, 'Унікальний @нік', maxLength: 30),
            ],
            if (mode == 'otp' && sent) ...[
              const SizedBox(height: 16),
              field(
                code,
                'Код із листа',
                keyboard: TextInputType.number,
                maxLength: 10,
              ),
            ],
            if (sent)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Text(
                  app.t('Перевірте пошту'),
                  style: TextStyle(color: app.palette.primary),
                ),
              ),
            const SizedBox(height: 18),
            FilledButton(
              key: const ValueKey('auth-submit'),
              onPressed: busy || (sent && mode != 'otp') ? null : submit,
              child: Text(
                app.t(
                  busy
                      ? 'Завантаження…'
                      : mode == 'otp'
                      ? (sent ? 'Підтвердити код' : 'Надіслати код')
                      : title,
                ),
              ),
            ),
            if (mode == 'login')
              TextButton(
                onPressed: () => setState(() {
                  mode = 'reset';
                  sent = false;
                  error = '';
                }),
                child: Text(app.t('Відновити пароль')),
              ),
          ],
        ),
      ),
    );
  }
}

class Onboarding extends StatefulWidget {
  const Onboarding({super.key});
  @override
  State<Onboarding> createState() => _OnboardingState();
}

class _OnboardingState extends StoreState<Onboarding> {
  late final name = TextEditingController(
    text: text(
      app.user?.userMetadata?['display_name'] ??
          app.user?.userMetadata?['full_name'],
    ),
  );
  late final username = TextEditingController(
    text: text(app.user?.userMetadata?['username']),
  );
  DateTime? birth;
  List<String> interests = [];
  bool busy = false;
  String error = '';
  @override
  void dispose() {
    name.dispose();
    username.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => NativePage(
    title: 'Завершити реєстрацію',
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          app.t('Мінімальний вік — 16 років'),
          style: TextStyle(color: app.palette.muted),
        ),
        const SizedBox(height: 20),
        field(name, 'Ім’я', maxLength: 60),
        const SizedBox(height: 14),
        field(username, 'Унікальний @нік', maxLength: 30),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: () async {
            final now = DateTime.now();
            final value = await showDatePicker(
              context: context,
              initialDate: birth ?? DateTime(2002),
              firstDate: DateTime(1900),
              lastDate: DateTime(now.year - 16, now.month, now.day),
            );
            if (value != null) setState(() => birth = value);
          },
          icon: const Icon(Icons.calendar_today_outlined),
          label: Text(
            birth == null
                ? app.t('Дата народження')
                : birth!.toIso8601String().split('T').first,
          ),
        ),
        const SizedBox(height: 20),
        Text(app.t('Оберіть інтереси')),
        const SizedBox(height: 8),
        TopicPicker(
          selected: interests,
          onChanged: (v) => setState(() => interests = v),
        ),
        if (error.isNotEmpty)
          Text(
            error,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: busy
              ? null
              : () async {
                  setState(() => busy = true);
                  try {
                    if (birth == null) {
                      throw Exception(app.t('Дата народження'));
                    }
                    await app.action('onboard', {
                      'username': username.text.trim().toLowerCase(),
                      'display_name': name.text.trim(),
                      'birth_date': birth!.toIso8601String().split('T').first,
                      'interests': interests,
                    });
                    if (context.mounted) Navigator.pop(context);
                  } catch (e) {
                    setState(() => error = app.message(e));
                  } finally {
                    if (mounted) setState(() => busy = false);
                  }
                },
          child: Text(app.t(busy ? 'Завантаження…' : 'Завершити реєстрацію')),
        ),
        TextButton(
          onPressed: () async {
            await app.db.auth.signOut();
            if (context.mounted) Navigator.pop(context);
          },
          child: Text(app.t('Вийти')),
        ),
      ],
    ),
  );
}
