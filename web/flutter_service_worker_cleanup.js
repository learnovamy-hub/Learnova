// Learnova SW Cleanup — v2026.05.09
// This service worker immediately takes over, wipes ALL old caches,
// then passes every request to the network. On the next normal build
// Flutter will reinstall its own SW with fresh content hashes.

const SW_VERSION = 'cleanup-2026-05-09';

self.addEventListener('install', function(event) {
  // Skip waiting immediately — don't wait for old tabs to close
  self.skipWaiting();
});

self.addEventListener('activate', function(event) {
  event.waitUntil(
    // Delete every cache the old Flutter SW created
    caches.keys().then(function(keys) {
      return Promise.all(keys.map(function(key) {
        console.log('[SW Cleanup] Deleting cache:', key);
        return caches.delete(key);
      }));
    }).then(function() {
      console.log('[SW Cleanup] All caches cleared. Claiming clients...');
      // Take control of all open tabs immediately
      return self.clients.claim();
    }).then(function() {
      // Tell every open tab to reload so they get fresh network content
      return self.clients.matchAll({ type: 'window' }).then(function(clients) {
        clients.forEach(function(client) {
          client.postMessage({ type: 'SW_CLEANUP_DONE' });
        });
      });
    })
  );
});

// NO fetch handler — every request goes straight to the network.
// This ensures fresh content is served while the next Flutter build
// installs its own caching service worker.
