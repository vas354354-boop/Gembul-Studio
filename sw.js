const CACHE_NAME = 'gembul-static-v12';
const CACHE_PREFIX = 'gembul-static-';
const CORE_ASSETS = [
  '/',
  '/manifest.webmanifest',
  '/supabase-config.js',
  '/customer-nav.js',
  '/admin-tools.js?v=2',
  '/icon-192.png',
  '/icon-512.png',
  '/og.jpg'
];
const PRIVATE_PATHS = new Set([
  '/account.html',
  '/admin.html',
  '/booking.html',
  '/barbers.html',
  '/pos.html',
  '/customers.html',
  '/inventory.html',
  '/transactions.html',
  '/finance.html',
  '/promotions.html'
]);

self.addEventListener('install', (event) => {
  event.waitUntil(caches.open(CACHE_NAME).then((cache) => cache.addAll(CORE_ASSETS)));
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(
        keys.filter((key) => key.startsWith(CACHE_PREFIX) && key !== CACHE_NAME)
          .map((key) => caches.delete(key))
      ))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (event) => {
  if (event.request.method !== 'GET') return;
  const requestUrl = new URL(event.request.url);
  if (requestUrl.origin !== self.location.origin) return;

  if (PRIVATE_PATHS.has(requestUrl.pathname)) {
    event.respondWith(
      fetch(event.request, {cache: 'no-store'})
        .catch(() => new Response('Halaman ini memerlukan koneksi internet. Data belum dimuat atau disimpan offline.', {
          status: 503,
          headers: {'Content-Type': 'text/plain; charset=utf-8', 'Cache-Control': 'no-store'}
        }))
    );
    return;
  }

  if (event.request.mode === 'navigate') {
    event.respondWith(
      fetch(event.request)
        .then((response) => {
          if (response.ok) {
            const copy = response.clone();
            caches.open(CACHE_NAME).then((cache) => cache.put(event.request, copy));
          }
          return response;
        })
        .catch(async () => (await caches.match(event.request)) || (await caches.match('/')))
    );
    return;
  }

  event.respondWith(
    caches.match(event.request).then(async (cached) => {
      if (cached) return cached;

      const response = await fetch(event.request);
      if (response.ok) {
        const copy = response.clone();
        caches.open(CACHE_NAME).then((cache) => cache.put(event.request, copy));
      }
      return response;
    })
  );
});
