# Učinak prostornog indeksa

Mjerenje za story **E2-S4**. Skripta: [`bench/nearest.exs`](../bench/nearest.exs).

```sh
mix beaches.import   # napuni bazu stvarnim podacima
mix run bench/nearest.exs
```

## Uvjeti mjerenja

| | |
|---|---|
| Podaci | 3107 plaža, stvarni uvoz iz OpenStreetMapa za cijelu Hrvatsku |
| Upit | `Beaches.nearest/2`, 20 najbližih točki 16.4392, 43.5081 (Split, Riva) |
| Baza | PostgreSQL 16.13, PostGIS 3.4.2 |
| Stroj | AMD Ryzen 5 3600, 12 jezgri, Linux |
| Indeks | `beaches_geom_geography_index`, GiST nad `(geom::geography)` |

"Bez indeksa" se dobiva s `enable_indexscan = off` i `enable_bitmapscan = off`
na razini transakcije. Isti upit i isti podaci, samo drugi plan — indeks se ne
briše, pa je mjerenje ponovljivo i bezopasno.

## Rezultat

| Scenarij | Prosjek | Medijan | 99. percentil | IPS |
|---|---|---|---|---|
| s indeksom | **0,57 ms** | 0,55 ms | 0,89 ms | 1,75 K |
| bez indeksa | 4,37 ms | 4,33 ms | 5,08 ms | 0,23 K |

**7,7× brže** uz indeks, +3,80 ms po upitu bez njega.

## Planovi upita

S indeksom — KNN ide izravno kroz indeks, bez sortiranja:

```
Limit  (cost=0.15..258.43 rows=20) (actual time=1.498..1.571 rows=20)
  Buffers: shared hit=156
  ->  Index Scan using beaches_geom_geography_index on beaches
        Order By: ((geom)::geography <-> '...'::geography)
        Buffers: shared hit=156
Execution Time: 1.639 ms
```

Bez indeksa — cijela tablica se čita i sortira:

```
Limit  (cost=981.26..1236.61 rows=20) (actual time=4.196..4.230 rows=20)
  Buffers: shared hit=625
  ->  Sort  (Sort Method: top-N heapsort  Memory: 27kB)
        Sort Key: (('...'::geography <-> (geom)::geography))
        ->  Seq Scan on beaches  (rows=3107)
              Buffers: shared hit=622
Execution Time: 4.282 ms
```

## Čitanje rezultata

Razlika u vremenu (7,7×) je manje zanimljiva od razlike u **broju pročitanih
blokova**: 156 naspram 625. Seq scan mora dotaknuti svih 3107 redaka bez obzira
na `LIMIT 20`, pa mu trošak raste linearno s brojem plaža. Index scan čita samo
onoliko koliko treba da popuni `LIMIT`, pa mu trošak raste logaritamski.

Na 3107 redaka i tablici koja cijela stane u cache, 4 ms je još uvijek
podnošljivo. Poanta je nagib: s deset puta više podataka seq scan bi bio oko
40 ms po upitu, a index scan bi ostao ispod milisekunde.

## Zašto `geography`, a ne `geometry`

KNN operator `<->` nad `geometry` sortira po stupnjevima, što na 43. paraleli
daje kriv poredak. Objašnjenje i mjerenje posljedica:
[`docs/adr/0003-knn-nad-geography-tipom.md`](adr/0003-knn-nad-geography-tipom.md).

Cast `geom::geography` onemogućuje običan GiST indeks nad `geometry`, pa je
potreban **funkcijski** indeks nad castom. Bez njega bi plan izgledao kao onaj
"bez indeksa" gore, iako indeks na koloni postoji — zamka koju je lako previdjeti.

---

# Lighthouse

Mjerenje za story **E6-S2**, na produkcijskom buildu (`MIX_ENV=prod`,
`mix assets.deploy`), Chrome 141 headless, zadano Lighthouse usporavanje CPU-a.

| Kategorija | Rezultat |
|---|---|
| Performance | 64 |
| Accessibility | **100** |
| Best practices | **100** |
| SEO | **100** |

Instalabilnost se ne mjeri Lighthouseom — PWA kategorija je uklonjena u
Lighthouseu 12. Umjesto toga pitamo sam Chrome, preko
`Page.getInstallabilityErrors`:

```
INSTALABILNOST: bez zamjerki — aplikacija se moze instalirati
MANIFEST greske: []
```

## Što je mjerenje promijenilo

Prvo mjerenje je dalo accessibility 95 i best practices 96, i obje zamjerke su
bile stvarne:

- **"Buttons do not have an accessible name"** — gumbi za temu su bili same
  ikone, bez teksta. Čitač ekrana je čitao "button, button, button".
- **"Requests the geolocation permission on page load"** — aplikacija je tražila
  lokaciju čim se otvori. To je loša praksa i korisnici takav dijalog refleksno
  odbiju, pa je posljedica bila i lošija funkcija, ne samo ocjena. Sada se
  lokacija traži sama **samo ako je korisnik već jednom pristao** (kroz
  Permissions API, bez dijaloga); inače stoji gumb "Koristi moju lokaciju".

Nakon popravaka: 100, 100, 100.

## Performance: 64, i zašto

| Metrika | Vrijednost |
|---|---|
| First Contentful Paint | 0,9 s |
| Largest Contentful Paint | 0,9 s |
| Speed Index | 2,8 s |
| **Total Blocking Time** | **5,2 s** |
| Cumulative Layout Shift | 0,14 |

Stranica se **iscrta brzo** (FCP i LCP ispod sekunde). Ocjenu ruši Total
Blocking Time: MapLibre GL JS je 1,0 MB minificiranog JavaScripta i njegovo
parsiranje drži glavnu dretvu.

Poznato ograničenje, s poznatim rješenjem: MapLibre bi trebao ići u zasebni
chunk i učitavati se dinamički nakon prvog iscrtavanja. To traži prelazak
esbuilda na `--splitting --format=esm` i nije napravljeno u ovoj fazi.

Brojka je uz to pesimistična i zbog okruženja mjerenja: Lighthouse usporava
CPU četiri puta, a headless Chrome ovdje crta kroz softverski SwiftShader.
