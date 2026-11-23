// Mastodonte Gestão — avisos no celular (indicações para votar).
// Fica separado do sw.js do app para não mexer no funcionamento dele.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', e => e.waitUntil(self.clients.claim()));

self.addEventListener('push', e => {
  let d = {};
  try { d = e.data ? e.data.json() : {}; } catch (_) { d = { body: e.data && e.data.text() }; }
  const titulo = d.title || 'Mastodonte';
  e.waitUntil(self.registration.showNotification(titulo, {
    body: d.body || '',
    icon: new URL('icon-192.png', self.location).href,
    badge: new URL('icon-192.png', self.location).href,
    tag: d.tag || undefined,
    renotify: !!d.tag,
    data: { url: d.url || new URL('./', self.location).href }
  }));
});

self.addEventListener('notificationclick', e => {
  e.notification.close();
  const url = (e.notification.data && e.notification.data.url) || new URL('./', self.location).href;
  e.waitUntil((async () => {
    const abas = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    const app = abas.find(c => c.url.startsWith(new URL('./', self.location).href));
    if (app) { await app.focus(); try { await app.navigate(url); } catch (_) { app.postMessage({ abrir: url }); } return; }
    await self.clients.openWindow(url);
  })());
});
