const CACHE_PREFIX = "versiondeck-";
const CACHE_NAME = `${CACHE_PREFIX}shell-__VERSIONDECK_CACHE_REVISION__`;
const APP_SHELL = [
  "./",
  "./index.html",
  "./styles.css",
  "./enhancements.css",
  "./security.css",
  "./build-status.css",
  "./build-status-ui.css",
  "./build-status-timeline.css",
  "./sticky-download-fix.css",
  "./app.js",
  "./build-status.js",
  "./build-status-ui.js",
  "./build-status-timeline.js",
  "./sticky-download-fix.js",
  "./manifest-schema.js",
  "./cache-policy.js",
  "./relative-time.js",
  "./manifest.webmanifest",
  "./assets/versiondeck-mark.svg",
  "./assets/versiondeck-192.png",
  "./assets/versiondeck-512.png",
];

function cacheable(response) {
  return response?.ok && response.type === "basic";
}

async function networkFirstNavigation(request) {
  try {
    const response = await fetch(request);
    if (cacheable(response)) {
      const cache = await caches.open(CACHE_NAME);
      await cache.put("./index.html", response.clone());
    }
    return response;
  } catch {
    return (
      (await caches.match("./index.html")) ||
      new Response("VersionDeck is unavailable offline.", {
        status: 503,
        headers: { "Content-Type": "text/plain; charset=utf-8" },
      })
    );
  }
}

async function networkOnlyAccountDeletionNavigation(request) {
  try {
    return await fetch(request, { cache: "no-store" });
  } catch {
    return new Response(
      "Account deletion requires a network connection. Reconnect and reload this page.",
      {
        status: 503,
        headers: {
          "Content-Type": "text/plain; charset=utf-8",
          "Cache-Control": "no-store",
        },
      },
    );
  }
}

function scopeRelativePath(url) {
  const scopePath = new URL(self.registration.scope).pathname;
  return url.pathname.startsWith(scopePath)
    ? url.pathname.slice(scopePath.length)
    : null;
}

self.addEventListener("install", (event) => {
  event.waitUntil(caches.open(CACHE_NAME).then((cache) => cache.addAll(APP_SHELL)));
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(
        keys
          .filter((key) => key.startsWith(CACHE_PREFIX) && key !== CACHE_NAME)
          .map((key) => caches.delete(key)),
      ),
    ),
  );
  self.clients.claim();
});

self.addEventListener("message", (event) => {
  if (event.data?.type === "SKIP_WAITING") self.skipWaiting();
});

self.addEventListener("fetch", (event) => {
  const request = event.request;
  if (request.method !== "GET") return;

  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;

  if (request.mode === "navigate") {
    const relativePath = scopeRelativePath(url);
    if (relativePath === "account-deletion.html") {
      event.respondWith(networkOnlyAccountDeletionNavigation(request));
      return;
    }
    if (relativePath === "" || relativePath === "index.html") {
      event.respondWith(networkFirstNavigation(request));
      return;
    }
    event.respondWith(fetch(request));
    return;
  }

  if (url.pathname.endsWith("/releases.json")) {
    event.respondWith(fetch(request, { cache: "no-store" }));
    return;
  }

  const shellPath = `.${url.pathname.slice(self.registration.scope
    ? new URL(self.registration.scope).pathname.length - 1
    : 0)}`;
  const isShellRequest = APP_SHELL.includes(shellPath) || APP_SHELL.includes(request.url);
  if (!isShellRequest) return;

  event.respondWith(
    caches.match(request).then(async (cached) => {
      if (cached) return cached;
      const response = await fetch(request);
      if (cacheable(response)) {
        const cache = await caches.open(CACHE_NAME);
        await cache.put(request, response.clone());
      }
      return response;
    }),
  );
});
