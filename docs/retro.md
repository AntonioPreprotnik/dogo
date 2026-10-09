# Retrospektive

Plan (odjeljak 7) traži kratki retro nakon svakog sprinta: što je išlo, što
nije, što mijenjam.

> **Napomena:** retro je napisan naknadno, 2026-10-09, iz poruka commitova i
> ADR-ova, a ne na kraju svakog sprinta. Sprintovi iz plana su zamišljeni kao
> tjedni rada navečer. Stvarno je cijela v1.0 commitana u dva dana
> (2026-09-28 i 2026-09-29), uz Claude Code, story po story. Podjela ispod
> zato prati **sadržaj** sprintova iz plana, a ne kalendar.

---

## Sprint 1: temelji (E0)

**Išlo je**

- CI od prvog dana: format, Credo strict, Dialyzer, testovi na istom
  `postgis/postgis:16-3.4` imageu kao lokalno. Svaki kasniji story je
  provjeravan istim pravilima.
- `/health` vraća 200 tek kad baza odgovori, pa deploy s krivim
  `DATABASE_URL`-om padne odmah.

**Nije išlo**

- Test udaljenosti Split–Dubrovnik imao je krivu očekivanu vrijednost
  (157 umjesto ~165 km) i preširoku toleranciju, pa je prolazio iako nije
  ništa dokazivao. Popravljeno odmah, uz toleranciju od 2 km.

**Mijenjam**

- Prostorni test mora imati toleranciju dovoljno usku da padne kad je
  izračun kriv, ne samo kad je red veličine kriv.

## Sprint 2: podaci (E1)

**Išlo je**

- Snimljeni stvarni Overpass odgovor kao fixture, uz ručno pisani. Ručni
  fixture pokriva rubne slučajeve, a stvarni pokriva oblik podataka koji nitko
  ne bi izmislio (`alt_name`, `name:de`).
- Deterministički demo atributi preko SHA-256, s vlastitim nizom po polju.
  Novi sadržaj ne mijenja postojeće vrijednosti, a demo izgleda isto nakon
  svakog deploya.
- Enumi kao tekst + `CHECK` constraint, jer uvoz i ručni SQL zaobilaze
  changeset.

**Nije išlo**

- Overpass vraća isti objekt dvaput (`natural=beach` i
  `leisure=beach_resort`), što je rušilo `insert_all`. Otkriveno tek na
  stvarnim podacima.
- Overpass na preopterećenje odgovara s `remark` u tijelu i statusom 200.
  Bez posebne provjere neuspjeli upit izgleda kao "nema plaža".

**Mijenjam**

- Svaki vanjski servis prvo pozvati uživo i snimiti odgovor, pa tek onda
  pisati parser. Dokumentacija API-ja ne opisuje kako servis zakaže.

## Sprint 3: prostorni upiti i karta (E2, E3-S1)

**Išlo je**

- Benchmark (E2-S4) s isključenim indeksima na razini transakcije umjesto
  brisanja indeksa: isti upit, isti podaci, ponovljivo. Rezultat 7,7× brže i
  4× manje pročitanih blokova (`docs/performance.md`).
- Karta živi u JS-u iza `phx-update="ignore"`, a LiveView i MapLibre
  komuniciraju samo eventima. Rizik iz plana ("tuku se oko DOM-a") se nije
  ostvario.

**Nije išlo**

- `nearest/2` je sortirao ravninski po stupnjevima, a udaljenost računao nad
  `geography`. Test nije uhvatio grešku jer je slučajno koristio točke na
  kojima se oba poretka poklapaju. Grešku je otkrilo tek mjerenje u E2-S4.

**Mijenjam**

- Test poretka mora koristiti podatke na kojima bi kriva implementacija dala
  **drugačiji** rezultat, i treba ga provjeriti tako da padne na starom kodu.

## Sprint 4: korisničko sučelje (E3-S2…S6, E4-S1)

**Išlo je**

- Svaki UI story provjeren u pravom pregledniku (headless Chromium), ne samo
  LiveView testovima. Tako su nađene greške koje testovi ne vide: MapLibre
  atribucija preko liste na mobitelu i lista od dvadeset redaka "Plaža bez
  imena" (70 % plaža u OSM-u nema ime, ADR 0007).
- Filteri u URL-u preko zasebnog modula `DogoWeb.BeachFilters`, bez
  pretvaranja korisničkog unosa u atome.
- Privatnost lokacije provjerena na sva tri mjesta na kojima je Phoenix po
  zadanom ispisuje (parametri eventa, Ecto log, URL).

**Nije išlo**

- Async testovi su povremeno deadlockali na unique indeksu `osm_id`.
  Riješeno vezanjem `osm_id` uz proces testa u fixtureu.
- `within_bbox/2` nije primjenjivao filter radijusa (tiho bez učinka), a
  promjena filtera je ispuštala zoom iz URL-a.
- Prva zaštita lokacije u URL-u bila je zastavica u hooku, ali MapLibre
  emitira još jedan `moveend`. Pravilo je premješteno na server i vezano uz
  stanje, ne uz događaj.
- Redoslijed iz plana nije bio izvediv: E3-S5 (detalj) je napravljen prije
  E3-S2, jer popup treba link na detalj.

**Mijenjam**

- Provjera u pregledniku je dio Definition of Done za svaki story koji
  mijenja sučelje.
- Testovi privatnosti prvo dokazuju da je logiranje uključeno. Inače
  `refute log =~ …` prolazi i kad filter ne radi.

## Sprint 5: fallback, klasteri, otoci (E4-S2, E4-S3, E3-S3, E5-S1, E5-S2)

**Išlo je**

- Nominatimova pravila (1 zahtjev/s, cache, User-Agent) su svako na svom
  mjestu u kodu i testirana.
- Poligoni otoka se sastavljaju u PostGIS-u (`ST_UnaryUnion` +
  `ST_Polygonize`). Krk izlazi 405,4 km², a stvarna površina je 405,8 km².
- Odstupanje od plana kod klasteriranja je mjereno, a ne nagađano: klijentski
  klasteri iznad 500 plaža lagali bi o broju. Zato postoji sažetak na
  serveru (ADR 0004).

**Nije išlo**

- Poruka o nedostupnom tile serveru je lagala ("popis i dalje radi"), a lista
  je bila prazna. Bez stila MapLibre nikad ne emitira `load`.
- Prvi uvoz otoka je Overpass odbio (429, pa prekinuta veza). Pauza između
  serija je obavezna.
- Oznaka "preko mora" i udaljenosti su koristile različita polazišta.

**Mijenjam**

- Svaka poruka o grešci provjerava se u stanju koje opisuje, ne samo da se
  prikaže.

## Sprint 6: OSRM, jezici, PWA, README (E5-S3, E6-S1, E6-S2, E7-S1)

**Išlo je**

- OSRM je dodatak, a ne ovisnost: lista se prikaže odmah sa zračnom
  udaljenošću, a vrijeme vožnje stiže asinkrono (ADR 0008). Koordinate se
  zaokružuju prije slanja trećoj strani.
- Lighthouse audit je našao dvije stvarne greske (gumbi bez accessible name,
  traženje lokacije pri otvaranju) i obje su popravljene.

**Nije išlo**

- Lighthouse performance je 64, zbog MapLibrea (1 MB JS). Rješenje
  (dinamički chunk) je opisano u `docs/performance.md`, ali nije napravljeno.

**Mijenjam**

- Prijevodi idu u isti commit kao i string. Od E6-S1 je to dio Definition of
  Done.

## Sprint 7: kvaliteta i objava (E7-S2…S5, E5-S4, E6-S3)

**Išlo je**

- ADR-ovi su napisani naknadno, ali s mjerenjima iz commitova. Na primjer,
  samo 4 % plaža ima `dog=*` tag, što opravdava generirane atribute
  (ADR 0007).
- Pokrivenost je kao alat (prag 80 % u CI-ju) odmah našla najosjetljiviji
  netestirani dio: dvofazni uvoz otoka.

**Nije išlo**

- Taj dio je bio netestiran od E5-S1 do E7-S3, iako je ADR 0005 opisivao
  baš njega kao osjetljiv.
- Service worker i IndexedDB (E6-S3) nisu pokriveni ExUnit testovima, nego
  ručnom provjerom u pregledniku (ADR 0009).

**Mijenjam**

- Pokrivenost od prvog sprinta, ne od zadnjeg.

## Nakon v1.0: administracija (E8-S1)

**Išlo je**

- `phx.gen.auth` skraćen na ono što projekt treba. Bez maila u produkciji
  nema registracije ni magic linkova. Admin nastaje iz konzole (ADR 0010).
- Prije prvog retka koda donesena je odluka da ručne izmjene imaju prednost
  pred uvozom (ADR 0011). Bez nje bi sljedeći uvoz tiho poništio svaku
  ispravku.
- LiveDashboard je prebačen s basic autha iz E7-S4 na istu prijavu. Pod
  `/admin` je sada jedan mehanizam, a ne dva.

**Nije išlo**

- Generator je ubacio plug za sesiju admina u javni `:browser` pipeline, pa
  bi svaki javni zahtjev čitao tablice admina. Premješteno u zaseban `:admin`
  pipeline.
- Lokalno nije bilo Dockera, pa su testovi išli na privremenu PostGIS bazu.
  CI za ovaj story još nije pokrenut.
- Provjera u pregledniku na dev serveru stvarno je pokrenula uvoz s
  Overpassa. Job je otkazan, ali je jedan zahtjev vjerojatno otišao.

**Mijenjam**

- Kod provjere admin sučelja u pregledniku koristiti bazu bez Oban radnika
  (ili `testing: :manual`), da klik ne zove vanjski servis.

---

## Zajednički zaključci

1. **Mjerenje je nalazilo greške koje testovi nisu.** Benchmark je našao
   krivi poredak, Lighthouse dvije greške pristupačnosti, pokrivenost
   netestirani uvoz otoka, a preglednik pola tuceta UI grešaka. Testovi su
   te greške zaključali tek nakon što su nađene.
2. **Stvarni podaci ruše pretpostavke.** Duplikati iz Overpassa, 70 % plaža
   bez imena, otoci kao nesređene relacije, `remark` umjesto HTTP greške:
   ništa od toga nije bilo u planu.
3. **Odstupanja od plana su zapisana.** Redoslijed E3-S5/E3-S2, klasteri na
   serveru i `island_id` tek u E5-S1 imaju razlog u commitu ili ADR-u.
4. **Tempo nije bio realan.** Plan računa ~7 tjedana rada navečer, a v1.0 je
   nastala u dva dana uz AI asistenta. To ne znači da je plan bio loš, nego
   da procjena u SP-ovima ne prenosi na ovakav način rada. Za idući projekt
   je bolje planirati po rizicima i provjerama nego po satima.
