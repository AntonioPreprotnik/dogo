# Dogo: plan izrade

> Naziv: **Dogo** (Elixir app: `:dogo`, moduli `Dogo` / `DogoWeb`)
> Namjena: portfolio projekt. Web aplikacija koja korisniku pronalazi najbliže plaže prikladne za pse na hrvatskom Jadranu.
> Alat za izradu: Claude Code, story po story.

---

## 1. Vizija proizvoda

Vlasnik psa na odmoru otvori aplikaciju na mobitelu i za nekoliko sekundi vidi najbliže plaže na kojima može biti sa psom. Uz svaku plažu vidi koliko je stvarno daleko, uključujući upozorenje ako je plaža preko mora, i koji su sadržaji dostupni.

**Cilj projekta (za CV):** javno dostupna, dovršena aplikacija i čist repozitorij koji pokazuju:

- prostorne upite u PostGIS-u s mjerljivim učinkom indeksa
- Phoenix LiveView sa stvarnom interaktivnom kartom
- pozadinske poslove (Oban) za uvoz podataka
- rješavanje jednog netrivijalnog domenskog problema (otoci i udaljenost)
- inženjersku higijenu: testove, CI, deploy, dokumentaciju

## 2. Opseg

### U opsegu

- uvoz plaža iz OpenStreetMapa (Overpass API)
- demo atributi (psi dozvoljeni, sadržaji) generirani deterministički
- pretraga najbližih plaža, karta, lista, detalj plaže, filteri
- geolokacija s fallbackom na ručni odabir mjesta
- detekcija otoka i procjena udaljenosti vožnjom
- PWA, tri jezika (hr, en, de)
- deploy, CI, README s arhitekturom i benchmarkom

### Izvan opsega (non-goals)

- točnost stvarnih propisa i pravila za pse
- korisnički računi, recenzije, ocjene, korisničke prijave
- moderacija sadržaja
- monetizacija
- nativne mobilne aplikacije

### Disclaimer (obavezan u aplikaciji i README-u)

> Podaci su demonstracijski. Lokacije plaža potječu iz OpenStreetMapa (© OpenStreetMap contributors, ODbL). Atributi vezani uz pse djelomično su generirani i ne odražavaju stvarna pravila.

## 3. Tehnološki stack

| Sloj | Izbor |
|---|---|
| Backend | Elixir, Phoenix, LiveView |
| Baza | PostgreSQL + PostGIS (`geo_postgis`) |
| Pozadinski poslovi | Oban |
| HTTP klijent | Req |
| Karta | MapLibre GL JS (LiveView hook) |
| Tile-ovi | OpenFreeMap ili MapTiler (free tier) |
| Geokodiranje mjesta | Nominatim (uz poštivanje usage policyja i cache) |
| Rutiranje | OSRM (javni demo server, uz cache i fallback) |
| i18n | Gettext |
| Kvaliteta | ExUnit, Credo, Dialyxir, `mix format --check-formatted` |
| CI | GitHub Actions |
| Deploy | Fly.io (app) + Postgres s PostGIS ekstenzijom |

## 4. Konvencije

### Format user storyja

> **Kao** <uloga>, **želim** <cilj>, **kako bih** <korist>.

Kriteriji prihvaćanja pišu se u obliku **Zadano / Kada / Tada**.

### Uloge

- **Korisnik**: vlasnik psa koji traži plažu
- **Developer**: ja, kao održavatelj projekta
- **Recenzent**: poslodavac ili tehnički intervjuer koji pregledava repozitorij

### Procjena

Story pointovi po Fibonacciju (1, 2, 3, 5, 8). Story veći od 5 dijeli se prije početka rada.

### Prioritet (MoSCoW)

**M** = must, **S** = should, **C** = could, **W** = won't (ovaj put)

### Definition of Ready

- story ima jasne kriterije prihvaćanja
- ovisnosti su završene ili eksplicitno navedene
- procjena je ≤ 5 SP

### Definition of Done

- kriteriji prihvaćanja su ispunjeni
- testovi napisani i prolaze
- `mix format`, Credo i Dialyzer bez upozorenja
- CI zelen
- ako story mijenja ponašanje vidljivo korisniku, prijevodi (hr/en/de) su dodani
- ako story uvodi arhitektonsku odluku, dodan je ADR u `docs/adr/`
- merge u `main`, automatski deploy prolazi

---

## 5. Pregled faza

| Faza | Naziv | Epici | Ishod | Procjena |
|---|---|---|---|---|
| 0 | Temelji | E0 | Prazna aplikacija deployana, CI radi | ~1 tjedan |
| 1 | Podaci i prostorni upiti | E1, E2 | Baza puna plaža, brzi upiti "najbliže" | ~1 tjedan |
| 2 | Karta i korisničko iskustvo | E3, E4 | Upotrebljiva aplikacija na mobitelu | ~1–1,5 tjedan |
| 3 | Diferencijator | E5 | Otoci i udaljenost vožnjom | ~0,5–1 tjedan |
| 4 | Dorada i objava | E6, E7 | PWA, i18n, dokumentacija, v1.0 | ~0,5–1 tjedan |

**Milestoneovi:**

- **M0**: "Hello world" na produkcijskom URL-u (kraj faze 0)
- **M1**: API/konzola vraća najbliže plaže za zadanu točku (kraj faze 1)
- **M2**: interna demo verzija, upotrebljiva na mobitelu (kraj faze 2)
- **M3**: v1.0 javno objavljena, link na CV-u (kraj faze 4)

---

## 6. Epici i storyji

### E0: Temelji projekta

**Cilj:** projekt koji se od prvog dana gradi, testira i deploya automatski.
**Faza:** 0

#### E0-S1: Inicijalizacija Phoenix projekta · 2 SP · M

**Kao** developer, **želim** generiran Phoenix projekt s LiveViewom i PostgreSQL-om, **kako bih** imao temelj za razvoj.

- **Zadano** prazan repozitorij, **kada** pokrenem `mix phx.server`, **tada** početna stranica se učitava na `localhost:4000`.
- Projekt koristi `Dogo` / `DogoWeb` namespace.
- Dodan `.tool-versions` (ili ekvivalent) s fiksnim verzijama Elixira i Erlanga.

#### E0-S2: PostGIS ekstenzija i Geo tipovi · 2 SP · M

**Kao** developer, **želim** omogućen PostGIS i Ecto tipove za geometriju, **kako bih** mogao spremati i upitati lokacije.

- Migracija izvršava `CREATE EXTENSION IF NOT EXISTS postgis`.
- `geo_postgis` konfiguriran kao Postgrex extension.
- **Zadano** testna tablica s `geometry(Point, 4326)`, **kada** spremim i pročitam točku, **tada** koordinate su identične.
- Lokalni razvoj ima `docker-compose.yml` s `postgis/postgis` imageom.

#### E0-S3: CI pipeline · 2 SP · M

**Kao** recenzent, **želim** vidjeti zeleni CI badge, **kako bih** znao da se projekt gradi i testira.

- GitHub Actions workflow na svaki push i PR: `deps.get`, `compile --warnings-as-errors`, `format --check-formatted`, Credo, Dialyzer (s cacheom PLT-a), `mix test`.
- Test job koristi PostGIS service container.
- Badge u README-u.

#### E0-S4: Deploy skeleton · 3 SP · M

**Kao** recenzent, **želim** javni URL aplikacije, **kako bih** mogao isprobati projekt bez kloniranja.

- Aplikacija deployana na Fly.io, baza s omogućenim PostGIS-om.
- Migracije se izvršavaju automatski pri deployu (release command).
- Deploy se pokreće automatski nakon uspješnog CI-ja na `main`.
- Health check endpoint `/health` vraća 200.

#### E0-S5: Temelj dokumentacije · 1 SP · S

**Kao** recenzent, **želim** osnovni README i mapu za ADR-ove, **kako bih** brzo razumio projekt.

- README: opis, disclaimer, pokretanje lokalno, link na demo.
- `docs/adr/0001-record-architecture-decisions.md`.
- `CLAUDE.md` u rootu s konvencijama projekta (vidi odjeljak 9).

---

### E1: Podaci

**Cilj:** baza s nekoliko tisuća realnih plaža hrvatske obale i determinističkim demo atributima.
**Faza:** 1

#### E1-S1: Shema plaža · 3 SP · M

**Kao** developer, **želim** Ecto shemu i migraciju za plaže, **kako bih** imao model podataka za sve ostale funkcije.

Polja (minimum):

```
beaches
  id               :bigserial
  osm_id           :string, unique        # npr. "way/123456"
  name             :string, nullable
  geom             :geometry(Point, 4326)  # centroid
  area             :geometry(MultiPolygon, 4326), nullable
  surface          :enum (pebble | sand | rock | concrete | mixed | unknown)
  dog_status       :enum (designated | allowed | not_allowed | unknown)
  dog_status_source:enum (osm | generated)
  amenities        :map  # dog_shower, shade, water, bins, parking (bool)
  municipality     :string, nullable
  island_id        :references(islands), nullable  # popunjava E5
  inserted_at / updated_at
```

- GiST indeks na `geom`.
- Changeset validira da je `geom` unutar bounding boxa hrvatske obale.

#### E1-S2: Overpass klijent · 3 SP · M

**Kao** developer, **želim** modul koji dohvaća plaže s Overpass API-ja, **kako bih** mogao uvesti realne lokacije.

- Upit pokriva `natural=beach` i `leisure=beach_resort` unutar područja Hrvatske, s `out center` ili geometrijom.
- Parser vraća listu struktura s `osm_id`, imenom, centroidom, poligonom (ako postoji) i relevantnim tagovima (`dog`, `surface`).
- Retry s eksponencijalnim backoffom na 429 i 5xx.
- Testovi koriste snimljeni JSON fixture, bez mrežnih poziva.

#### E1-S3: Oban import job · 3 SP · M

**Kao** developer, **želim** uvoz kao Oban job koji se može ponovno pokrenuti, **kako bih** mogao osvježiti podatke bez duplikata.

- Upsert po `osm_id` (`on_conflict`), pa je job idempotentan.
- **Zadano** job je već izvršen, **kada** ga pokrenem ponovno, **tada** broj plaža se ne mijenja.
- Job logira broj dodanih, ažuriranih i preskočenih zapisa.
- Mix task `mix beaches.import` stavlja job u red.

#### E1-S4: Deterministički demo atributi · 2 SP · M

**Kao** developer, **želim** generirane atribute za plaže bez OSM podataka, **kako bih** imao uvjerljiv demo koji je uvijek isti.

- Ako OSM ima tag `dog=*`, koristi se on i `dog_status_source = osm`.
- Inače se `dog_status` i `amenities` generiraju iz hasha `osm_id`-a. Isti ulaz uvijek daje isti rezultat.
- Raspodjela je realna: manjina plaža su `designated` ili `allowed`.
- Test: dva pokretanja daju identične atribute.

#### E1-S5: Atribucija izvora · 1 SP · M

**Kao** korisnik, **želim** vidjeti odakle su podaci, **kako bih** znao da su demonstracijski.

- Footer s OSM atribucijom i disclaimerom na svim stranicama.
- Na detalju plaže oznaka "iz OSM-a" ili "generirano" za status psa.

---

### E2: Prostorni upiti

**Cilj:** brzi i testirani upiti koji su temelj aplikacije.
**Faza:** 1

#### E2-S1: Najbliže plaže (KNN) · 3 SP · M

**Kao** korisnik, **želim** dobiti najbliže plaže svojoj lokaciji, **kako bih** brzo odabrao kamo ići.

- Funkcija `Beaches.nearest(point, opts)` koristi `ORDER BY geom <-> point` s GiST indeksom.
- Vraća udaljenost u metrima (geografski izračun, `::geography`).
- Opcije: `limit` (zadano 20), filteri (`dog_status`, `surface`, `amenities`).
- **Zadano** tri plaže na poznatim udaljenostima, **kada** pozovem `nearest`, **tada** redoslijed i udaljenosti su točni (tolerancija 1 %).

#### E2-S2: Plaže unutar vidljivog dijela karte · 2 SP · M

**Kao** korisnik, **želim** vidjeti plaže na dijelu karte koji gledam, **kako bih** mogao istraživati druga područja.

- `Beaches.within_bbox(bbox, opts)` koristi `ST_MakeEnvelope` i `&&`.
- Tvrdi limit rezultata (npr. 500). Iznad njega vraća se oznaka da treba povećati zoom ili se oslanja na klasteriranje (E3-S3).

#### E2-S3: Pretraga u radijusu · 1 SP · S

**Kao** korisnik, **želim** ograničiti pretragu na zadani radijus, **kako bih** vidio samo ono što je stvarno blizu.

- `ST_DWithin` na `geography`, radijus 5/10/25/50 km.

#### E2-S4: Benchmark indeksa · 2 SP · S

**Kao** recenzent, **želim** vidjeti izmjereni učinak prostornog indeksa, **kako bih** procijenio razumijevanje baze.

- Skripta u `bench/` (Benchee) mjeri `nearest` s indeksom i bez njega.
- `EXPLAIN ANALYZE` izlaz i rezultati zapisani u `docs/performance.md`.

---

### E3: Karta i korisničko sučelje

**Cilj:** interaktivna karta i lista, upotrebljive na mobitelu.
**Faza:** 2

#### E3-S1: MapLibre hook · 3 SP · M

**Kao** korisnik, **želim** interaktivnu kartu, **kako bih** vizualno vidio gdje su plaže.

- LiveView hook inicijalizira MapLibre s odabranim tile providerom.
- Hook šalje serveru `bounds_changed` (s debounceom od ~300 ms), a server hooku gura markere preko `push_event`.
- Karta se ne reinicijalizira pri LiveView re-renderu (`phx-update="ignore"`).

#### E3-S2: Markeri i odabir plaže · 2 SP · M

**Kao** korisnik, **želim** kliknuti na marker i vidjeti osnovne podatke, **kako bih** odlučio želim li ići tamo.

- Boja markera ovisi o `dog_status`.
- Klik otvara popup s nazivom, udaljenošću i linkom na detalj.

#### E3-S3: Klasteriranje markera · 3 SP · S

**Kao** korisnik, **želim** preglednu kartu i na malom zoomu, **kako bih** vidio gustoću plaža bez nereda.

- Koristi se ugrađeno klasteriranje GeoJSON sourcea u MapLibreu.
- Klik na klaster zumira na njegov sadržaj.

#### E3-S4: Lista rezultata · 2 SP · M

**Kao** korisnik, **želim** listu plaža sortiranu po udaljenosti, **kako bih** ih lako usporedio.

- Na mobitelu je lista donji panel (bottom sheet) iznad karte, na desktopu bočni panel.
- Klik na stavku centrira kartu na plažu.

#### E3-S5: Detalj plaže · 2 SP · M

**Kao** korisnik, **želim** stranicu s detaljima plaže, **kako bih** vidio sve sadržaje i otvorio navigaciju.

- Ruta `/beaches/:id`: naziv, status psa (s izvorom), podloga, sadržaji, mini karta.
- Gumb "Navigiraj" otvara Google Maps ili Apple Maps s koordinatama.

#### E3-S6: Filteri u URL-u · 3 SP · M

**Kao** korisnik, **želim** filtrirati plaže i podijeliti link s filterima, **kako bih** prijatelju poslao isti prikaz.

- Filteri: status psa, podloga, sadržaji (tuš, hlad, voda), radijus.
- Stanje filtera i pozicija karte su u query stringu (`handle_params`).
- **Zadano** link s filterima, **kada** ga otvorim u novom prozoru, **tada** vidim identičan prikaz.

---

### E4: Lokacija korisnika

**Cilj:** aplikacija radi i kad korisnik dopusti lokaciju i kad je odbije.
**Faza:** 2

#### E4-S1: Browser geolokacija · 2 SP · M

**Kao** korisnik, **želim** da aplikacija automatski koristi moju lokaciju, **kako bih** odmah vidio najbliže plaže.

- Hook traži `navigator.geolocation` i šalje koordinate serveru.
- Marker "ti si ovdje" na karti.
- Lokacija se **ne sprema** na serveru ni u logove.

#### E4-S2: Fallback: odabir mjesta · 3 SP · M

**Kao** korisnik koji ne želi dijeliti lokaciju, **želim** upisati mjesto, **kako bih** i dalje mogao koristiti aplikaciju.

- **Zadano** korisnik je odbio geolokaciju, **kada** se stranica učita, **tada** vidi polje za pretragu mjesta.
- Autocomplete preko Nominatima, ograničeno na Hrvatsku, s debounceom i cacheom (ETS ili Cachex).
- Poštuje se Nominatim usage policy: User-Agent s kontaktom, najviše 1 zahtjev u sekundi.

#### E4-S3: Stanja greške i praznog rezultata · 1 SP · M

**Kao** korisnik, **želim** jasne poruke kad nešto ne radi, **kako ne bih** gledao praznu kartu.

- Poruke za: odbijenu lokaciju, timeout geolokacije, nema rezultata za filtere, nedostupan tile server.

---

### E5: Otoci i stvarna udaljenost

**Cilj:** riješiti domenski problem koji jednostavne aplikacije ignoriraju: zračna udaljenost na Jadranu često vara.
**Faza:** 3

#### E5-S1: Uvoz poligona otoka · 3 SP · M

**Kao** developer, **želim** poligone hrvatskih otoka u bazi, **kako bih** mogao odrediti je li plaža na otoku.

- Tablica `islands` (`osm_id`, `name`, `geom MultiPolygon`), uvoz iz OSM-a (`place=island`, iznad minimalne površine).
- Nakon uvoza plažama se postavlja `island_id` preko `ST_Contains` ili `ST_Intersects`.
- ADR: zašto poligoni iz OSM-a, a ne ručni popis.

#### E5-S2: Upozorenje "preko mora" · 2 SP · M

**Kao** korisnik, **želim** vidjeti da je plaža na drugom otoku ili kopnu, **kako ne bih** krenuo prema plaži do koje treba trajekt.

- Određuje se `island_id` korisnikove lokacije.
- **Zadano** korisnik je na kopnu, a plaža na otoku (ili obrnuto, ili na drugom otoku), **tada** uz plažu stoji oznaka "preko mora".
- Filter "samo dostupno bez trajekta".
- Iznimka: otoci povezani mostom (Krk, Pag, Čiovo, Vir, Murter i sl.) označeni su u tablici `islands` poljem `bridge_connected`.

#### E5-S3: Udaljenost vožnjom (OSRM) · 5 SP · S

**Kao** korisnik, **želim** procjenu udaljenosti i vremena vožnje, **kako bih** znao koliko mi zapravo treba.

- Za prvih N rezultata (npr. 10) poziva se OSRM `table` servis u jednom zahtjevu.
- Rezultati se cacheiraju po zaokruženim koordinatama (npr. na 3 decimale).
- **Zadano** OSRM nije dostupan ili je spor (timeout 2 s), **tada** prikazuje se zračna udaljenost s oznakom "približno" i aplikacija ne puca.
- Rezultati stižu asinkrono (`Task.async` / `start_async`), lista se prvo prikaže sa zračnom udaljenošću pa se ažurira.

#### E5-S4: Sortiranje po stvarnoj udaljenosti · 2 SP · C

**Kao** korisnik, **želim** sortirati po vremenu vožnje, **kako bih** prvo vidio ono do čega najbrže stignem.

- Opcija sortiranja: zračna udaljenost ili vrijeme vožnje (kad je dostupno).

---

### E6: PWA i lokalizacija

**Cilj:** aplikacija se ponaša kao mobilna aplikacija i govori jezikom publike.
**Faza:** 4

#### E6-S1: Tri jezika · 3 SP · M

**Kao** turist iz Njemačke ili Austrije, **želim** sučelje na svom jeziku, **kako bih** ga lakše koristio.

- Gettext s `hr`, `en`, `de`. Jezik se određuje iz `Accept-Language` i može se ručno promijeniti.
- Odabrani jezik pamti se u cookieju.
- CI provjerava da nema neprevedenih stringova (`mix gettext.extract --check-up-to-date`).

#### E6-S2: Instalabilna PWA · 2 SP · S

**Kao** korisnik, **želim** dodati aplikaciju na početni zaslon, **kako bih** je otvarao kao aplikaciju.

- `manifest.json`, ikone, theme color.
- Lighthouse PWA provjera prolazi.

#### E6-S3: Offline zadnji rezultati · 3 SP · C

**Kao** korisnik sa slabim signalom na plaži, **želim** vidjeti zadnje učitane rezultate, **kako bih** mogao pronaći plažu i bez interneta.

- Service worker cacheira app shell.
- Zadnji rezultati spremaju se u IndexedDB i prikazuju s oznakom "offline" kad je LiveView socket nedostupan.

---

### E7: Kvaliteta i dokumentacija

**Cilj:** repozitorij koji recenzent može procijeniti za 5 minuta.
**Faza:** 4 (dijelom kontinuirano)

#### E7-S1: README za recenzenta · 2 SP · M

**Kao** recenzent, **želim** README koji odmah pokazuje što je zanimljivo, **kako bih** brzo procijenio kandidata.

- Na vrhu: link na demo, GIF ili screenshot, jedna rečenica o projektu.
- Odjeljak "Tehnički zanimljivo": prostorni upiti, problem otoka, asinkroni OSRM, idempotentni uvoz.
- Dijagram arhitekture (Mermaid).
- Upute za lokalno pokretanje u najviše 5 naredbi.

#### E7-S2: ADR-ovi ključnih odluka · 2 SP · S

**Kao** recenzent, **želim** vidjeti zašto su odluke donesene, **kako bih** procijenio inženjersko razmišljanje.

- Minimalno: PostGIS umjesto izračuna u aplikaciji, LiveView umjesto SPA, OSM kao izvor, strategija fallbacka za OSRM.

#### E7-S3: Pokrivenost testovima · 3 SP · S

**Kao** developer, **želim** testove na kritičnim putovima, **kako bih** mogao mijenjati kod bez straha.

- Testovi za sve funkcije u `Beaches` kontekstu (prostorni upiti na stvarnoj PostGIS bazi).
- LiveView testovi za filtere i fallback lokacije.
- Vanjski servisi (Overpass, Nominatim, OSRM) iza behaviour modula, mockirani u testovima (Mox).
- Coverage izvještaj u CI-ju (ExCoveralls), cilj ≥ 80 % za `lib/dogo`.

#### E7-S4: Observability · 2 SP · C

**Kao** developer, **želim** osnovni uvid u rad produkcije, **kako bih** znao kad nešto ne radi.

- Phoenix LiveDashboard iza basic autha.
- Telemetry metrike za trajanje prostornih upita i poziva vanjskim servisima.

#### E7-S5: Objava v1.0 · 1 SP · M

**Kao** developer, **želim** označenu verziju i changelog, **kako bih** projekt predstavio kao dovršen.

- Git tag `v1.0.0`, `CHANGELOG.md`.
- Link dodan na CV i GitHub profil (pinned repo).

---

### E8: Administracija (opcionalno)

**Faza:** nakon v1.0, samo ako ostane vremena.

#### E8-S1: Admin pregled i uređivanje plaža · 5 SP · C

**Kao** developer, **želim** admin sučelje za ručne ispravke, **kako bih** pokazao rad s autentifikacijom i formama.

- `phx.gen.auth` samo za admina, CRUD nad plažama, ponovno pokretanje importa iz sučelja.

---

## 7. Sprint plan (prijedlog)

Sprint = 1 tjedan rada navečer (~10–15 SP).

| Sprint | Storyji | SP |
|---|---|---|
| 1 | E0-S1, E0-S2, E0-S3, E0-S4, E0-S5 | 10 |
| 2 | E1-S1, E1-S2, E1-S3, E1-S4, E1-S5 | 12 |
| 3 | E2-S1, E2-S2, E2-S3, E2-S4, E3-S1 | 11 |
| 4 | E3-S2, E3-S4, E3-S5, E3-S6, E4-S1 | 11 |
| 5 | E4-S2, E4-S3, E3-S3, E5-S1, E5-S2 | 12 |
| 6 | E5-S3, E6-S1, E6-S2, E7-S1 | 12 |
| 7 | E7-S2, E7-S3, E5-S4, E7-S5 (+ C storyji po želji) | 8+ |

Nakon svakog sprinta: kratki retro u `docs/retro.md` (što je išlo, što nije, što mijenjam).

## 8. Rizici

| Rizik | Vjerojatnost | Utjecaj | Mitigacija |
|---|---|---|---|
| Overpass timeout ili rate limit | srednja | srednji | Uvoz po regijama, retry s backoffom, fixture za testove i seed |
| Javni OSRM spor ili nedostupan | visoka | nizak | Timeout, cache, fallback na zračnu udaljenost (E5-S3) |
| Nominatim blokira zbog preopterećenja | niska | srednji | Cache, 1 req/s, User-Agent s kontaktom |
| Tile provider ukine free tier | niska | srednji | Provider konfigurabilan kroz env varijablu |
| Opseg se širi (scope creep) | visoka | visok | Non-goals su fiksni. Novo ide u backlog, ne u sprint |
| Karta i LiveView se "tuku" oko DOM-a | srednja | srednji | `phx-update="ignore"`, sva komunikacija samo preko eventova |

## 9. Rad s Claude Codeom

**`CLAUDE.md` u rootu** treba sadržavati:

- kratki opis projekta i link na ovaj plan (`docs/PLAN.md`)
- konvencije: konteksti (`Dogo.Beaches`, `Dogo.Geo`, `Dogo.Import`), vanjski servisi uvijek iza behaviourova, bez mrežnih poziva u testovima
- naredbe za provjeru: `mix format`, `mix credo --strict`, `mix dialyzer`, `mix test`
- pravilo da se Definition of Done (odjeljak 4) provjeri prije završetka storyja

**Tijek rada po storyju:**

1. Otvori novu granu `e1-s3-oban-import`.
2. Zadaj Claude Codeu jedan story: kopiraj njegov tekst i kriterije prihvaćanja.
3. Traži prvo plan i testove, pa implementaciju.
4. Sam pregledaj diff. Ne mergeaj ništa što ne razumiješ, jer će te to pitati na intervjuu.
5. PR, CI zelen, merge, deploy.

**Jedan story = jedna sesija = jedan PR.** Story veći od 5 SP najprije se dijeli.
