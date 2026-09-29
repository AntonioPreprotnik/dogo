# 6. LiveView umjesto SPA

- **Status:** prihvaćeno
- **Datum:** 2026-09-29 (odluka donesena na početku projekta, E0-S1; zapisana
  naknadno, u E7-S2)

## Kontekst

Sučelje je jedna interaktivna stranica: karta, filteri, lista najbližih plaža
koja se mijenja sa svakim pomakom karte, i detalj plaže. Dva uobičajena
pristupa:

1. **SPA** (React ili sl.) nad JSON API-jem iz Phoenixa.
2. **Phoenix LiveView**: stanje i renderiranje na serveru, preglednik dobiva
   diff preko websocketa.

Projekt ima jednog održavatelja i ograničeno vrijeme. Većina logike su
prostorni upiti u bazi (ADR 0002), a ne interakcija na klijentu.

## Odluka

LiveView. Jedini dio koji mora živjeti u pregledniku, sama karta (MapLibre GL
JS), ide kao **hook** s `phx-update="ignore"`. Server i karta razgovaraju samo
eventovima: karta šalje granice (`bounds_changed`), server vraća GeoJSON i
naredbe poput `fly_to`.

## Zašto

- **Jedan jezik i jedan izvor istine.** Filteri, radijus, lista i klasteri
  računaju se u kontekstima (`Dogo.Beaches`, `Dogo.Geo`) i odmah se renderiraju.
  Nema API sloja, serijalizacije ni dupliciranog stanja na klijentu. Sav
  klijentski JavaScript je oko 500 redaka, gotovo sve u hooku karte.
- **Asinkroni rad bez dodatne infrastrukture.** Vrijeme vožnje (ADR 0008) i
  geokodiranje idu kroz `start_async`; odgovor koji zakasni nakon pomaka karte
  jednostavno se odbacuje. U SPA-u bi to bila otkazivanja zahtjeva i
  upravljanje stanjem na klijentu.
- **Privatnost lokacije.** Korisnikova lokacija stiže kao parametar eventa
  `location`, koji je u `:filter_parameters`, pa ga logger ispiše kao
  `[FILTERED]`. Nikad ne ide u URL, pa ni u access log ili povijest
  preglednika. Test (`geolocation_privacy_test.exs`) to zaključava.
- **Filteri u URL-u besplatno.** `push_patch` + `handle_params` daju linkove
  koje se može podijeliti i gumb "natrag" koji radi (E3-S6), bez klijentskog
  routera.
- **Testovi bez preglednika.** `Phoenix.LiveViewTest` pokriva filtere, stanja
  greške i fallback lokacije kao obične ExUnit testove.

## Posljedice

- **Proces po posjetitelju.** Svaki otvoreni tab drži LiveView proces sa
  stanjem u memoriji servera. Za očekivani promet to je zanemarivo, ali
  skaliranje je vertikalno i treba ga imati na umu.
- **Svaka interakcija ide preko mreže.** Na lošoj vezi klik na filter čeka
  povratni put do servera. Pomak karte je glatki jer ga radi MapLibre lokalno;
  tek lista kasni.
- **Offline je teži.** Bez socketa nema renderiranja. E6-S3 (zadnji rezultati
  offline) zato traži zasebnu klijentsku kopiju podataka u IndexedDB-u, što bi
  u SPA-u bilo prirodnije.
- **Granica s kartom je mjesto rizika.** LiveView i MapLibre ne smiju oboje
  upravljati istim DOM-om; `phx-update="ignore"` i komunikacija samo eventovima
  to drže odvojenim (rizik je naveden i u `docs/PLAN.md`).
- Veličina JavaScripta nije argument ni za ni protiv: bundle je ~1 MB
  minificiran, i gotovo sve je MapLibre, koji bi i SPA morao učitati
  (`docs/performance.md`).
