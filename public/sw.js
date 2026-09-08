const CACHE = 'sideleaf-shell-BUILD_VERSION';
const BRAND_ASSETS = [
  '/brand/sideleaf-logo.png',
  '/brand/sideleaf-logo-tagline.png',
  '/brand/sideleaf-wordmark.png',
  '/brand/sideleaf-icon.png',
  '/brand/sideleaf-favicon-32.png',
  '/brand/sideleaf-apple-touch-icon-180.png',
  '/brand/sideleaf-pwa-icon-192.png',
  '/brand/sideleaf-pwa-icon-512.png',
];
self.addEventListener('install', (event) => {
  event.waitUntil(
    (async () => {
      const response = await fetch('/', { cache: 'reload' });
      if (!response.ok) throw new Error('Notebook shell unavailable');
      const html = await response.clone().text();
      const assets = [...html.matchAll(/(?:src|href)="(\/assets\/[^\"]+)"/g)].map(
        (match) => match[1],
      );
      const cache = await caches.open(CACHE);
      await cache.addAll([...assets, ...BRAND_ASSETS, '/manifest.webmanifest']);
      await cache.put('/', response);
    })(),
  );
});
self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)))),
  );
});
self.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url);
  if (
    event.request.method !== 'GET' ||
    url.origin !== self.location.origin ||
    url.pathname.startsWith('/api/')
  )
    return;
  if (event.request.mode === 'navigate') {
    event.respondWith(fetch(event.request).catch(() => caches.match('/')));
    return;
  }
  if (
    !url.pathname.startsWith('/assets/') &&
    ![...BRAND_ASSETS, '/manifest.webmanifest'].includes(url.pathname)
  )
    return;
  event.respondWith(
    caches.match(event.request).then(
      (cached) =>
        cached ||
        fetch(event.request).then((response) => {
          if (response.ok) {
            const copy = response.clone();
            caches.open(CACHE).then((cache) => cache.put(event.request, copy));
          }
          return response;
        }),
    ),
  );
});
