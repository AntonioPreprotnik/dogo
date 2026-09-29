// Service worker.
//
// Zasad samo toliko da se aplikacija moze instalirati: Chrome trazi fetch
// handler prije nego ponudi instalaciju. Cacheiranje app shella i zadnjih
// rezultata dolazi s E6-S3; dok toga nema, ovdje se namjerno nista ne
// cacheira, jer cache koji se ne osvjezava je gori od nikakvog.
self.addEventListener("install", () => self.skipWaiting())
self.addEventListener("activate", (event) => event.waitUntil(self.clients.claim()))
self.addEventListener("fetch", (event) => event.respondWith(fetch(event.request)))
