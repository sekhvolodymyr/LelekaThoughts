# Підключення входу перед відкритою реєстрацією

Застосунок, база, сховище й серверні функції створені. Google OAuth та поштовий відправник ще потребують облікових даних власника. Не вимикайте підтвердження email для обходу цього кроку. Секрети вводьте лише на сторінках провайдерів, не в репозиторій або чат.

## 1. Адреса застосунку

У [Supabase URL Configuration](https://supabase.com/dashboard/project/glqsayxjvvnkmhejuqjz/auth/url-configuration):

- Site URL: `https://lelekathoughts.vercel.app`
- Redirect URLs: `https://lelekathoughts.vercel.app/`, `http://127.0.0.1:5173/`, `http://localhost:5173/`.
- Для паролів залиште увімкненим підтвердження email.

## 2. Email і коди

У [Supabase SMTP Settings](https://supabase.com/dashboard/project/glqsayxjvvnkmhejuqjz/auth/smtp) підключіть власного поштового відправника. Перевірте його актуальний безкоштовний тариф, ліміти та вимоги до підтвердження адреси/домену перед підключенням. Вбудований відправник Supabase має обмеження для використання поза командою проєкту й не є готовим відкритим поштовим каналом.

Заповніть Sender email, Sender name `LelekaThoughts`, SMTP host, port, username та password безпосередньо в панелі Supabase. Не додавайте SMTP password у браузерний код або репозиторій.

У [Email Templates](https://supabase.com/dashboard/project/glqsayxjvvnkmhejuqjz/auth/templates) замініть шаблон Magic Link на вміст `supabase/templates/magic-link.html`. Змінна `{{ .Token }}` потрібна для входу кодом. Для Confirm Signup і Reset Password використайте відповідні підготовлені шаблони з посиланням `{{ .ConfirmationURL }}`.

Перевірте реальним email поза командою: реєстрацію → отримання листа → підтвердження → створення профілю; вхід кодом; відновлення пароля. Код у UI й робота API реалізовані, але доставку листів без вашого відправника не підтверджено.

## 3. Google

Перевірка 14 листопада 2026: публічний `/auth/v1/settings` повертає `external.google: false`, а `/authorize` — `400 provider is not enabled`. Це конфігураційна причина збою Google-входу та реєстрації. Зміна коду або повторний деплой самі по собі не увімкнуть провайдера.

У [Google Auth Platform](https://console.cloud.google.com/auth/clients) створіть OAuth-клієнт типу Web application:

- Authorized JavaScript origin: `https://lelekathoughts.vercel.app`
- Authorized redirect URI: `https://glqsayxjvvnkmhejuqjz.supabase.co/auth/v1/callback`

Налаштуйте назву застосунку LelekaThoughts, контактний email та потрібні параметри consent screen. Скопіюйте Client ID і Client Secret у [Supabase Auth Providers](https://supabase.com/dashboard/project/glqsayxjvvnkmhejuqjz/auth/providers), Google, та увімкніть провайдера. Секрет зберігається лише у Supabase.

Для відкритого запуску перевірте статус публікації Google consent screen: у режимі Testing доступ мають лише додані тестові користувачі. У Supabase також обов’язково встановіть production Site URL і Redirect URLs з розділу 1: у логах ще трапляється типовий fallback `http://localhost:3000`.

Після підключення перевірте:

1. `/auth/v1/settings` з публічним `apikey` повертає `external.google: true`.
2. «Продовжити з Google» з входу і реєстрації відкриває Google, після згоди повертає на `https://lelekathoughts.vercel.app/`.
3. Новий користувач заповнює ім’я, @нік, дату народження й інтереси; повторний вхід відкриває той самий профіль.
4. Повторний вхід тим самим підтвердженим email іншим способом веде в один акаунт. Не прив’язуйте акаунти самостійно на основі непідтвердженого email.
5. Відмова або помилка входу показується у діалозі застосунку; параметри помилки прибираються з адреси. Успішний фрагмент сесії обробляє Supabase SDK.

До ввімкнення провайдера застосунок перевіряє налаштування та показує зрозумілу помилку без переходу на JSON-сторінку Supabase. Налаштування перевіряються під час кожної спроби, тому після ввімкнення Google повторний деплой не потрібний.

## 4. Перший адміністратор

Після власної реєстрації додайте свій UUID, скопійований з Auth Users, до `app_private.admins` через SQL Editor:

```sql
insert into app_private.admins(user_id)
select id from auth.users where id = '<YOUR_VERIFIED_USER_UUID>'::uuid
and email_confirmed_at is not null
on conflict do nothing;
```

Перша людина, що зареєструвалася, навмисно не отримує адміністративних прав автоматично. Після додавання адміністратора перезавантажте застосунок; з’явиться «Адмінпанель».

## Документація

- [Custom SMTP](https://supabase.com/docs/guides/auth/auth-smtp)
- [Email templates](https://supabase.com/docs/guides/auth/auth-email-templates)
- [Email OTP](https://supabase.com/docs/guides/auth/auth-email-passwordless)
- [Google OAuth](https://supabase.com/docs/guides/auth/social-sign-in/auth-google)
- [Redirect URLs](https://supabase.com/docs/guides/auth/redirect-urls)
