# SEO LelekaThoughts

Публічна головна `/` містить серверний HTML з описом української соцмережі LelekaThoughts («Лелека»), заголовками, поясненням функцій та посиланням на застосунок. Вміст однаковий для відвідувачів і пошуковиків; JavaScript не потрібний для читання опису. Застосунок залишається за старими посиланнями `/#/...`.

Налаштовано title/description, абсолютний canonical на production, Open Graph і Twitter preview, WebSite/Organization JSON-LD, sitemap та robots.txt. Sitemap містить лише реальну індексовану головну. API має X-Robots-Tag noindex; це не засіб захисту, доступ до приватних даних продовжує перевіряти backend.

## Підключити Google Search Console

1. Додати URL-prefix property `https://lelekathoughts.vercel.app/` у [Google Search Console](https://search.google.com/search-console/welcome). Для безкоштовного субдомену Vercel зручно підтвердження через HTML meta tag.
2. З отриманого `<meta name="google-site-verification" content="...">` взяти тільки значення content і додати у production environment variable `GOOGLE_SITE_VERIFICATION` на Vercel. Це публічний verification token, не пароль. Після цього перевипустити сайт і натиснути Verify.
3. У Sitemaps додати `https://lelekathoughts.vercel.app/sitemap.xml`.
4. Перевірити головну в URL Inspection → Test live URL → Request indexing. Перевірити обраний Google canonical після індексації.
5. У Performance відстежувати покази, кліки й середню позицію для `lelekathoughts`, `українська соцмережа`, `лелека`. Не оцінювати результат одразу після деплою: Google сам обирає час обходу, індексації та порядок видачі.

Без підтвердження власності Search Console sitemap ще доступний пошуковику через robots.txt, але статус фактичної індексації й запит на переобхід тут не підтверджені. У цьому патчі property не створено і ownership не підтверджено.

## Подальший розвиток

Для широкого запиту «лелека» є конкуренція з іншими значеннями слова. Використовувати бренд послідовно: LelekaThoughts («Лелека»), українська соцмережа для креаторів. Потрібні корисний публічний контент, природні згадки й посилання з інших сайтів. Не купувати масові посилання й не дублювати ключові слова прихованим текстом.

Hash-маршрути `#/post/...` не є окремими індексованими сторінками. Для пошуку окремих публічних профілів, постів і ланцюжків наступним етапом потрібні звичайні серверні URL, індивідуальні метадані, серверна перевірка видимості й sitemap тільки публічного контенту. Приватні та видалені публікації не можна включати до цього sitemap або серверного кешу.

Жодна технічна оптимізація не гарантує першого місця. Офіційні пояснення: [JavaScript SEO](https://developers.google.com/search/docs/crawling-indexing/javascript/javascript-seo-basics), [site names](https://developers.google.com/search/docs/appearance/site-names), [SEO Starter Guide](https://developers.google.com/search/docs/fundamentals/seo-starter-guide).
