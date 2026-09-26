'use strict';

const version = new URL(self.location.href).searchParams.get('v') || 'dev';
const cacheName = `kumpas-shell-${version}`;
const shell = [
  './', 'index.html', 'flutter_bootstrap.js', 'flutter.js', 'main.dart.js',
  'manifest.json', 'favicon.png', 'icons/Icon-192.png', 'icons/Icon-512.png',
  'icons/Icon-maskable-192.png', 'icons/Icon-maskable-512.png',
  'assets/AssetManifest.bin',
  'assets/AssetManifest.bin.json', 'assets/FontManifest.json',
  'assets/fonts/MaterialIcons-Regular.otf',
  'assets/packages/cupertino_icons/assets/CupertinoIcons.ttf',
  'assets/shaders/ink_sparkle.frag', 'assets/shaders/stretch_effect.frag',
  'assets/assets/images/Appdev_background1.png',
  'assets/assets/images/button_app.png',
  'assets/assets/images/logo_isucamp_app.png',
  'assets/assets/images/logo_isu_png.png',
  'assets/assets/images/logo_kumpas_app.png',
  'canvaskit/canvaskit.js', 'canvaskit/canvaskit.wasm',
  'canvaskit/chromium/canvaskit.js', 'canvaskit/chromium/canvaskit.wasm',
];

self.addEventListener('install', (event) => {
  event.waitUntil(caches.open(cacheName).then((cache) => cache.addAll(
      shell.map((path) => new URL(path, self.registration.scope)),
  )));
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    for (const key of await caches.keys()) {
      if (key.startsWith('kumpas-shell-') && key !== cacheName) {
        await caches.delete(key);
      }
    }
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET' || new URL(request.url).origin !== self.location.origin) return;
  event.respondWith((async () => {
    const cache = await caches.open(cacheName);
    const file = new URL(request.url).pathname.split('/').pop();
    const checkForUpdate = request.mode === 'navigate' ||
        ['flutter_bootstrap.js', 'flutter.js', 'main.dart.js'].includes(file);
    if (!checkForUpdate) {
      const hit = await cache.match(request, {ignoreSearch: true});
      if (hit) return hit;
    }
    try {
      return await fetch(request);
    } catch (error) {
      const hit = await cache.match(request, {ignoreSearch: true});
      if (hit) return hit;
      if (request.mode === 'navigate') {
        const page = await cache.match(new URL('index.html', self.registration.scope));
        if (page) return page;
      }
      throw error;
    }
  })());
});
