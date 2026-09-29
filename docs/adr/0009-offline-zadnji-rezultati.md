# 9. Offline: app shell u service workeru, rezultati u IndexedDB-u

- **Status:** prihvaćeno
- **Datum:** 2026-09-29

## Kontekst

E6-S3: korisnik na plaži sa slabim signalom treba vidjeti zadnje učitane
rezultate. Aplikacija je LiveView (ADR 0006): bez socketa server ne može ništa
renderirati, a rezultati ne stižu HTTP-om nego kroz websocket. Service worker
ih zato ne može sam uhvatiti i spremiti.

"Slab signal" pritom najčešće ne znači grešku, nego zahtjev koji visi.

## Odluka

Dva odvojena dijela, svaki za ono što može:

1. **Service worker cacheira app shell.** Pri instalaciji dohvati `/` i iz
   njegova HTML-a pročita CSS, JS i ikone. Imena u produkciji imaju hash, pa se
   ne nabrajaju ručno. Svi zahtjevi idu **network-first**, a cache je samo
   rezerva. Navigacija ima **timeout od 3 s**, nakon kojeg se koristi cache.
2. **Rezultate šalje server.** Nakon svake promjene liste i kad stigne vrijeme
   vožnje, LiveView šalje `offline_snapshot` (`DogoWeb.OfflineSnapshot`).
   `assets/js/offline.js` ga sprema u IndexedDB i, kad socket javi grešku,
   ispisuje ga u panelu "Izvan mreže". Kad se socket spoji, panel nestaje.

Sažetak nosi **gotove, prevedene tekstove**: ime, opis, udaljenost ili
vrijeme vožnje, link za navigaciju. Klijent samo ispisuje, bez logike i bez
prijevoda. Jedina iznimka je vrijeme spremanja, koje popunjava preglednik u
lokalnom vremenu.

## Razmotrene opcije

- **Cache-first za statičke datoteke.** Brže, ali u razvoju (bez hasha u
  imenu) servira zastarjeli JS. Network-first je ispravan u oba okruženja, a
  pri dobroj vezi razlika je zanemariva.
- **Cacheirati renderirani HTML s rezultatima.** Ne radi: dead render nema
  rezultate, oni stižu tek nakon spajanja socketa.
- **Pločice karte u cacheu.** Odbačeno. Uvjeti OpenFreeMapa i OSM tile policy
  ne predviđaju masovno spremanje, a smisleno pokrivanje obale su stotine MB.
  Offline prikaz je zato lista, ne karta, a svaka stavka ima link za navigaciju
  koji otvara aplikaciju za karte na uređaju.
- **Generički JSON endpoint za rezultate**, koji bi service worker cacheirao.
  Uveo bi API samo za ovu svrhu i duplicirao logiku liste koja već postoji u
  LiveViewu.

## Posljedice

- Aplikacija se otvara bez mreže i prikazuje zadnjih do 20 plaža, uz vrijeme
  kad su spremljene.
- **Privatnost:** sažetak ne sadrži polazište, samo plaže. Test to provjerava s
  korisnikovom lokacijom postavljenom. Sprema se samo u pregledniku korisnika,
  nikad na server.
- Prazna lista (karta pomaknuta na pučinu) se ne šalje, pa ne briše zadnje
  korisne rezultate.
- Imena plaža dolaze iz OSM-a, dakle od bilo koga: klijent ih ispisuje
  isključivo kroz `textContent`.
- Service worker i IndexedDB nisu pokriveni ExUnit testovima. Ugovor (što
  stiže, kojim redom, na kojem jeziku) testiran je na serveru, a ponašanje u
  pregledniku provjereno je ručno kroz Playwright: prva posjeta, prekid mreže,
  ponovno učitavanje, povratak veze.
- Promjena strategije cacheiranja traži novu verziju imena cachea
  (`dogo-shell-vN`), inače korisnici zadrže stari sadržaj.
