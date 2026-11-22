/* СТОИТ — офлайн-кэш сайта. */
const CACHE = "stoit-v31";
const SHELL = [
  "./",
  "index.html",
  "assets/app.css?v=31",
  "assets/config.js?v=1",
  "assets/app.js?v=31",
  "assets/favicon.svg",
  "assets/icon-192.png",
  "assets/icon-512.png",
  "assets/icon-maskable-512.png",
  "manifest.webmanifest",
  "data/feed.json",
];

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(CACHE)
      .then((cache) => Promise.all(SHELL.map((url) => cache.add(url).catch(() => {}))))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((keys) => Promise.all(keys.filter((key) => key !== CACHE).map((key) => caches.delete(key)))).then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", (event) => {
  const request = event.request;
  if (request.method !== "GET") return;
  const url = new URL(request.url);
  if (url.origin !== location.origin) return;
  if (url.pathname.includes("/api/")) return;

  if (url.pathname.endsWith("/data/feed.json")) {
    event.respondWith(
      fetch(request, { cache: "no-store" })
        .then((response) => {
          if (!response.ok) throw new Error("HTTP " + response.status);
          const copy = response.clone();
          caches.open(CACHE).then((cache) => cache.put("data/feed.json", copy)).catch(() => {});
          return response;
        })
        .catch(() => caches.match("data/feed.json").then((cached) => cached || Response.error()))
    );
    return;
  }

  if (request.mode === "navigate") {
    event.respondWith(
      fetch(request)
        .then((response) => {
          if (!response.ok) throw new Error("HTTP " + response.status);
          const copy = response.clone();
          caches.open(CACHE).then((cache) => cache.put("index.html", copy)).catch(() => {});
          return response;
        })
        .catch(() => caches.match("index.html").then((cached) => cached || caches.match("./")))
    );
    return;
  }

  const isCode = /\.(?:css|js|html)$/.test(url.pathname) || url.pathname === "/";
  if (isCode) {
    event.respondWith(
      fetch(request)
        .then((response) => {
          if (!response.ok) throw new Error("HTTP " + response.status);
          const copy = response.clone();
          caches.open(CACHE).then((cache) => cache.put(request, copy)).catch(() => {});
          return response;
        })
        .catch(() => caches.match(request).then((cached) => cached || caches.match("index.html")))
    );
    return;
  }

  event.respondWith(
    caches.match(request).then((cached) => {
      if (cached) return cached;
      return fetch(request).then((response) => {
        if (response && response.ok) {
          const copy = response.clone();
          caches.open(CACHE).then((cache) => cache.put(request, copy)).catch(() => {});
        }
        return response;
      });
    })
  );
});

self.addEventListener("message", (event) => {
  if (event.data === "SKIP_WAITING") self.skipWaiting();
});
