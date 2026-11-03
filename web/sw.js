// Offline shell. Network first, so a deploy is never served half-old.
// The page falls back to its last cached build when the network fails, errors,
// or stalls for a few seconds; the files that page then loads come from that
// same cached build. Only the renderer this browser actually loads is cached.
const CACHE = 'timer-v2';
const STALL_MS = 4000;
const STALE_WINDOW_MS = 30000;

// Pages answered from cache: their files must come from the same build, not the
// network. Browsers without client ids fall back to a short worker-wide window.
const staleClients = new Set();
let staleUntil = 0;

const sameOrigin = (url) => new URL(url, location.href).origin === location.origin;

self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) =>
  event.waitUntil(
    caches
      .keys()
      .then((keys) => Promise.all(keys.filter((key) => key.startsWith('timer-') && key !== CACHE).map((key) => caches.delete(key))))
      .then(() => self.clients.claim()),
  ),
);

// The page sends what it loaded before this worker existed.
self.addEventListener('message', (event) => {
  if (event.data?.type !== 'precache') return;
  const urls = event.data.urls.filter(sameOrigin);
  event.waitUntil(
    caches.open(CACHE).then((cache) =>
      Promise.all(urls.map(async (url) => (await cache.match(url)) ?? cache.add(url).catch(() => {}))),
    ),
  );
});

self.addEventListener('fetch', (event) => {
  const { request } = event;
  if (request.method !== 'GET' || !sameOrigin(request.url)) return;

  const navigate = request.mode === 'navigate';
  // The page is stored by path alone (no query, `index.html` folded into `/`),
  // so deep links and the installed app's start URL all share one entry.
  const url = new URL(request.url);
  const key = navigate ? url.origin + url.pathname.replace(/index\.html$/, '') : request;
  const cached = () => caches.match(key, { ignoreVary: true });
  let settled = false;
  // Store a fresh copy whenever the network answers, even after the cache already did.
  // Cloned synchronously in the first reaction, before the page starts reading the body.
  const fetchAndStore = () => {
    const network = fetch(request);
    network.finally(() => (settled = true)).catch(() => {});
    event.waitUntil(
      network
        .then((response) => {
          if (!response.ok) return;
          const copy = response.clone();
          return caches.open(CACHE).then((cache) => cache.put(key, copy));
        })
        .catch(() => {}),
    );
    return network;
  };

  if (!navigate) {
    // A page pinned to its cached build never fetches (or overwrites) its files.
    const stale = staleClients.has(event.clientId) || Date.now() < staleUntil;
    event.respondWith(
      stale
        ? cached().then((hit) => hit ?? fetchAndStore())
        : fetchAndStore().catch(async () => (await cached()) ?? Response.error()),
    );
    return;
  }

  const network = fetchAndStore();
  // Serves the cached page (if any) and pins that page's files to the cached build,
  // unless the network answered while the cache was being read.
  const fromCache = async (otherwise, raceNetwork = false) => {
    const hit = await cached();
    if (!hit || (raceNetwork && settled)) return otherwise();
    if (event.resultingClientId) staleClients.add(event.resultingClientId);
    else staleUntil = Date.now() + STALE_WINDOW_MS;
    return hit;
  };
  const usable = (response) => response.ok || response.type === 'opaqueredirect';
  const page = network.then(
    (response) => (usable(response) ? response : fromCache(() => response)),
    () => fromCache(() => Response.error()),
  );
  // The stall timer is cancelled as soon as the network settles.
  const stalled = new Promise((resolve) => {
    const timer = setTimeout(resolve, STALL_MS);
    network.finally(() => clearTimeout(timer)).catch(() => {});
  }).then(() => fromCache(() => page, true));
  event.respondWith(Promise.race([page, stalled]));
});
