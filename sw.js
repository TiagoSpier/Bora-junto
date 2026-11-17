// Bora Junto: service worker simples (rede primeiro, cache como reserva)
const CACHE = 'bora-junto-v2';
const BASE = ['./', 'index.html', 'manifest.json', 'icon-192.png', 'icon-512.png', 'foto-capa.jpg', 'foto-trilha.jpg', 'foto-cachoeira.jpg', 'foto-camping.jpg', 'foto-passeio.jpg', 'foto-viagem.jpg'];
self.addEventListener('install', e => {
  e.waitUntil(caches.open(CACHE).then(c => Promise.all(BASE.map(u => c.add(u).catch(() => {})))));
  self.skipWaiting();
});
self.addEventListener('activate', e => {
  e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== CACHE).map(k => caches.delete(k)))).then(() => self.clients.claim()));
});
self.addEventListener('fetch', e => {
  const r = e.request;
  if (r.method !== 'GET' || new URL(r.url).origin !== location.origin) return; // Supabase e CDN passam direto
  e.respondWith(fetch(r).then(res => {
    const copia = res.clone(); caches.open(CACHE).then(c => c.put(r, copia)); return res;
  }).catch(() => caches.match(r).then(m => m || caches.match('index.html'))));
});
