# 8. OSRM kao neobavezan dodatak, sa zračnom udaljenošću kao fallbackom

- **Status:** prihvaćeno
- **Datum:** 2026-09-29 (odluka donesena u E5-S3; zapisana naknadno, u E7-S2)

## Kontekst

Zračna udaljenost na Jadranu vara i kad između nema mora: cesta ide oko uvale,
preko prijevoja ili oko poluotoka. Primjer iz stvarnih podataka: iz Splita je
Matejuška 370 m zračno, a 12 minuta vožnje; susjedne plaže na 900 m su 3
minute. Korisnika zanima koliko mu treba, a ne koliko je daleko.

To daje OSRM. Koristimo javni demo server (`router.project-osrm.org`), koji je
besplatan, ali bez jamstva dostupnosti, s ograničenjem prometa i povremeno spor.

Osnovna funkcija aplikacije, "najbliže plaže", **ne smije ovisiti** o servisu
koji ne kontroliramo.

## Odluka

Vrijeme vožnje je **dodatak koji stiže naknadno**, a zračna udaljenost iz
PostGIS-a je uvijek dostupan fallback.

1. **Lista se prikaže odmah**, sa zračnom udaljenošću označenom "≈".
2. Vrijeme vožnje za prvih deset plaža traži se asinkrono (`start_async`).
   Kad stigne, oznaka "≈" nestaje i pojavljuje se broj minuta.
3. **Svaki neuspjeh vodi u isto stanje**: timeout, HTTP greška, OSRM-ova
   greška (`code` ≠ `Ok`), pad zadatka. U svim slučajevima lista ostaje sa
   zračnom udaljenošću i tooltipom "Zračna udaljenost; vrijeme vožnje nije
   dostupno". Nema poruke o grešci: korisnik je dobio ono što je tražio.
4. Pojedino odredište bez rute (`nil`) prikazuje zračnu udaljenost, a ostala
   svoje vrijeme vožnje.

## Kako je fallback osiguran

- **Timeout 2 s, bez ponavljanja.** Ponavljanje ima smisla za osnovnu funkciju;
  za dodatak samo produlji čekanje i dodatno optereti tuđi servis.
- **Jedan `table` zahtjev** za sva odredišta (`sources=0`), umjesto deset
  zasebnih `route` poziva.
- **OSRM se pita samo kad se vrh liste promijeni.** Svaki pomak karte ne znači
  novi zahtjev; ako je prvih deset plaža isto, stari rezultat vrijedi.
- **Zakasnjeli odgovor se odbacuje.** Ako je korisnik u međuvremenu pomaknuo
  kartu, odgovor za stari pogled se ne prikazuje.
- **Cache** (ETS, TTL 6 h) po zaokruženim koordinatama.
- **Iznimka se hvata na mjestu poziva**, ne prepušta se `Task`u. Pad zadatka bi
  u log ispisao argumente, a polazište je korisnikova lokacija. Test to
  zaključava s mockom koji namjerno baci iznimku s koordinatama u poruci.

## Privatnost

Polazište je korisnikova lokacija i odlazi trećoj strani. Koordinate se zato
**zaokružuju na tri decimale (~110 m)** prije slanja. To istovremeno podiže
pogodak u cacheu i smanjuje preciznost lokacije koja napušta aplikaciju. Na
skali "koliko mi treba do plaže" stotinu metara ne mijenja odgovor.

## Razmotrene opcije

- **Vlastiti OSRM server** s izvozom OSM-a za Hrvatsku. Pouzdanije i bez
  ograničenja prometa, ali traži zaseban servis s nekoliko GB RAM-a i
  održavanje podataka. Za portfolio projekt nesrazmjerno; odluka se lako
  mijenja jer je klijent iza behavioura `Dogo.Geo.Routing`, a adresa u
  konfiguraciji (`:osrm_endpoint`).
- **Čekati OSRM prije prikaza liste.** Točniji prvi prikaz, ali svaki spori
  odgovor znači praznu stranicu. Odbačeno.
- **Poredati listu po vremenu vožnje.** Dosljednije, ali lista bi se
  preslagivala kad odgovor stigne, a bez OSRM-a bi poredak bio drukčiji.
  Poredak zato ostaje po zračnoj udaljenosti, a vrijeme vožnje je informacija
  uz svaku stavku.

## Posljedice

- Aplikacija radi i kad je OSRM potpuno nedostupan; korisnik tada vidi samo
  "≈" udaljenosti.
- Brojevi u listi nisu uvijek monotoni: plaža koja je zračno bliža može
  imati dulje vrijeme vožnje. To je namjerno i upravo je poanta podatka.
- Behaviour + Mox znači da testovi pokrivaju sve grane neuspjeha bez mreže.
