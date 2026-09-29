# Changelog

Sve bitne promjene projekta. Format prati
[Keep a Changelog](https://keepachangelog.com/hr/1.1.0/), a verzije
[Semantic Versioning](https://semver.org/lang/hr/).

## [1.0.0] — 2026-09-29

Prva cjelovita verzija: svi storyji faza 0–4 iz [`docs/PLAN.md`](docs/PLAN.md).
Opcionalni epic E8 (administracija) nije dio ove verzije.

### Pretraga i karta

- Najbliže plaže zadanoj točki: KNN nad `geography` tipom uz funkcijski GiST
  indeks ([ADR 0003](docs/adr/0003-knn-nad-geography-tipom.md)). Izmjereni
  učinak indeksa u [`docs/performance.md`](docs/performance.md).
- Plaže unutar vidljivog dijela karte i pretraga u radijusu.
- Interaktivna karta (MapLibre GL JS) s markerima, odabirom plaže i
  klasteriranjem; iznad 500 plaža sažetak se računa na serveru, pa su brojevi
  u klasterima uvijek točni ([ADR 0004](docs/adr/0004-sazetak-klastera-na-serveru.md)).
- Lista najbližih plaža i detalj plaže s navigacijom (Google Maps, Apple Maps).
- Filteri (status psa, podloga, sadržaji, radijus, "bez trajekta") u URL-u,
  pa je svaki prikaz djeljiv linkom.

### Lokacija

- Geolokacija preglednika, uz pitanje za dopuštenje tek na klik; bez nje
  odabir mjesta preko Nominatima (1 zahtjev u sekundi, cache).
- Lokacija korisnika se ne sprema i ne završava u logovima; testovi to
  zaključavaju.
- Jasna stanja greške i praznog rezultata.

### Otoci i udaljenost

- Poligoni otoka iz OSM-a, sastavljeni u PostGIS-u iz nepovezanih segmenata
  relacija ([ADR 0005](docs/adr/0005-poligoni-otoka-iz-osm-a.md)).
- Oznaka "preko mora" i filter "bez trajekta", uz otoke spojene mostom.
- Vrijeme vožnje (OSRM) za prvih deset plaža, asinkrono, sa zračnom
  udaljenošću kao fallbackom ([ADR 0008](docs/adr/0008-osrm-kao-neobavezan-dodatak.md)).
- Sortiranje po zračnoj udaljenosti ili po vremenu vožnje.

### Uvoz podataka

- Uvoz plaža s Overpass API-ja kao Oban job, idempotentan (upsert po
  `osm_id`), s ponavljanjem i eksponencijalnim backoffom.
- Deterministički generirani atributi za plaže bez OSM podataka o psima,
  uvijek označeni kao generirani ([ADR 0007](docs/adr/0007-openstreetmap-kao-izvor-podataka.md)).
- Atribucija izvora i disclaimer na svakoj stranici.

### Mobitel i jezici

- Sučelje na hrvatskom, engleskom i njemačkom; jezik iz `Accept-Language`,
  s ručnim izborom koji se pamti.
- Instalabilna PWA: manifest na jeziku korisnika, ikone, service worker.
- Rad bez mreže: app shell u cacheu, zadnji rezultati u IndexedDB-u
  ([ADR 0009](docs/adr/0009-offline-zadnji-rezultati.md)).
- Lighthouse: accessibility, best practices i SEO 100.

### Kvaliteta i rad

- CI: format, Credo (strict), Dialyzer, provjera prijevoda i testovi s
  pokrivenošću (prag 80 %; domena 90 %).
- Vanjski servisi iza behaviour modula, u testovima mockirani; testovi ne
  idu na mrežu, a prostorni upiti se testiraju na stvarnom PostGIS-u.
- LiveDashboard iza basic autha i telemetry metrike za prostorne upite,
  vanjske servise i uvoz.
- Arhitektonske odluke u [`docs/adr/`](docs/adr/), uključujući
  [LiveView umjesto SPA](docs/adr/0006-liveview-umjesto-spa.md).

### Poznata ograničenja

- Atributi vezani uz pse većinom su generirani: samo 4 % plaža u OSM-u ima
  podatak o psima. Aplikacija je demonstracija, ne vodič.
- Lighthouse performance 64, zbog veličine MapLibrea; predloženo rješenje
  (dinamičko učitavanje) u [`docs/performance.md`](docs/performance.md).
- Ovisnost o javnim servisima (Overpass, OSRM, Nominatim), koji imaju
  ograničenja prometa.

[1.0.0]: https://github.com/CHANGE-ME/dogo/releases/tag/v1.0.0
