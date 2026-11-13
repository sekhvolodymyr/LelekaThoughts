// Online-first by design. Never cache authentication responses, private records,
// messages, birth dates or media which may later be deleted.
self.addEventListener('install',()=>self.skipWaiting());
self.addEventListener('activate',event=>event.waitUntil(self.clients.claim()));
self.addEventListener('fetch',event=>{if(event.request.mode==='navigate')event.respondWith(fetch(event.request).catch(()=>new Response('<!doctype html><html lang="uk"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>LelekaThoughts</title><body style="font:16px system-ui;padding:48px;background:#faf9f6;color:#292824"><h1>Немає інтернету</h1><p>Текст залишився на цьому пристрої. Відновіть зв’язок і відкрийте LelekaThoughts знову.</p><button onclick="location.reload()">Спробувати ще</button></body></html>',{headers:{'Content-Type':'text/html; charset=utf-8'}})))});
