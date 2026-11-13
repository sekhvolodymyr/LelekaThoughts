# Design system

Reference: `feed-concept.png`, generated with built-in Image Gen from the agreed PRD, 2026-11-08. Primary screen: three-column social feed, not a marketing page.

- Canvas #faf9f6, sidebar #f1efeb, feed #ffffff, text #292824, secondary #77736d, border #e7e3dd, accent #b76049, accent soft #f0e1da. Dark equivalents: #1b1c1d, #222325, #242527, #efeeeb, #aaa7a1, #38393b, #d98c72, #44312b.
- System sans with Inter when available. Body 15px/1.6, controls 14px, captions 12px, page title 25px/1.2 semibold, brand 20px semibold.
- Desktop: left rail 248px, middle feed flexible max 720px, right rail 288px. Feed open rows with hairline separators. No nested card grid. Content inset 24px; avatar 40px; media corner radius 12px.
- Buttons 10px radius; inputs 10px; restrained terracotta selected backgrounds. Visible keyboard focus. Lucide outline icons 20px, stroke 1.7.
- Tablet hides utility rail. Mobile hides sidebar, uses top menu and bottom navigation; width 100%, safe-area insets. Other pages and dialog states extend the same tokens.
- Exact main labels: LelekaThoughts, Створити, Стрічка, Пошук, Сповіщення, Повідомлення, Збережене, Профіль, Мої ланцюжки, Для тебе, Підписки, Історії, що тривають, Знайди своїх, Твої інтереси.
- Intentional functional adaptations from concept: signed-out footer uses Увійти instead of a fictional logged-in account; own thread list is empty until created. Demonstration creators are identified as examples. No fabricated engagement counts. Utility rail starts with demo suggestions until real creators join.
- Main components: AppShell, Sidebar, Feed, StoryStrip/StoryViewer, PostCard/CommentList, Composer, AuthDialog, ProfilePage, SearchPage, MessagesPage, Settings, AdminPage. Shared semantic tokens, avatar and empty-state components.
