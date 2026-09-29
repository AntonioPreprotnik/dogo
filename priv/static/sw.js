// Service worker (E6-S2, E6-S3).
//
// Cacheira app shell: stranicu i njezine statičke datoteke, da se aplikacija
// otvori i bez mreže. Same rezultate ne cacheira ovdje — njih sprema
// assets/js/offline.js u IndexedDB, jer ih stranica šalje kroz websocket,
// a ne kroz HTTP.
//
// Strategija je network-first: svjež sadržaj uvijek ima prednost, a cache je
// samo rezerva. Za navigacije postoji timeout, jer "slab signal na plaži"
// najčešće ne znači grešku, nego zahtjev koji visi.
//
// Ne cacheira se: websocket i longpoll (/live), live reload, tuđe domene
// (pločice karte, OSRM, Nominatim) i ništa što nije GET.

const CACHE = "dogo-shell-v1"
const SHELL_URL = "/"
const NAVIGATION_TIMEOUT_MS = 3000

self.addEventListener("install", (event) => {
  event.waitUntil(precacheShell().catch(() => {}).then(() => self.skipWaiting()))
})

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) => Promise.all(keys.filter((key) => key !== CACHE).map((key) => caches.delete(key))))
      .then(() => self.clients.claim()),
  )
})

self.addEventListener("fetch", (event) => {
  const request = event.request
  const url = new URL(request.url)

  if (request.method !== "GET" || url.origin !== self.location.origin || !cacheable(url)) return

  if (request.mode === "navigate") {
    event.respondWith(navigation(request, url))
  } else {
    event.respondWith(networkFirst(request))
  }
})

function cacheable(url) {
  return !url.pathname.startsWith("/live") && !url.pathname.startsWith("/phoenix")
}

// Stranica i datoteke koje ona učitava. Imena datoteka u produkciji imaju
// hash (app-3f2a….js), pa se čitaju iz samog HTML-a umjesto da se nabrajaju.
async function precacheShell() {
  const cache = await caches.open(CACHE)
  const response = await fetch(SHELL_URL, {credentials: "same-origin"})
  if (!response.ok) return

  const html = await response.clone().text()
  await cache.put(SHELL_URL, response)

  const assets = [...html.matchAll(/(?:src|href)="(\/(?:assets|icons|images|fonts)\/[^"]+)"/g)].map((match) => match[1])
  await Promise.all(assets.map((asset) => cache.add(asset).catch(() => {})))
}

// Navigacija: mreža s timeoutom, pa cache pod istom putanjom, pa shell.
// Query string se zanemaruje: /?lat=… i / su ista stranica, a pozicija karte
// ne treba završiti u cacheu.
async function navigation(request, url) {
  const cache = await caches.open(CACHE)
  const key = url.pathname
  const network = fetch(request).then((response) => {
    if (response.ok) cache.put(key, response.clone())
    return response
  })
  // Ako je odgovor dan iz cachea, kasni neuspjeh mreže nitko ne čeka.
  network.catch(() => {})

  try {
    return await withTimeout(network, NAVIGATION_TIMEOUT_MS)
  } catch (_error) {
    const cached = (await cache.match(key)) || (await cache.match(SHELL_URL))
    if (cached) return cached

    // Nema ničega u cacheu: pričekaj mrežu do kraja, pa neka preglednik
    // prikaže svoju grešku ako ni ona ne uspije.
    return network
  }
}

async function networkFirst(request) {
  const cache = await caches.open(CACHE)

  try {
    const response = await fetch(request)
    if (response.ok) cache.put(request, response.clone())
    return response
  } catch (error) {
    const cached = await cache.match(request)
    if (cached) return cached
    throw error
  }
}

function withTimeout(promise, ms) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error("timeout")), ms)
    promise.then(
      (value) => {
        clearTimeout(timer)
        resolve(value)
      },
      (error) => {
        clearTimeout(timer)
        reject(error)
      },
    )
  })
}
