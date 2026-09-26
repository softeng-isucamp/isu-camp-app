{{flutter_js}}
{{flutter_build_config}}

// Cache the app shell on web so an installed catalog can be opened offline.
if ('serviceWorker' in navigator) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('campus-sw.js?v=' + {{flutter_service_worker_version}})
        .catch((error) => console.warn('Offline app shell unavailable:', error));
  });
}

_flutter.loader.load({config: {canvasKitBaseUrl: 'canvaskit/'}});
