# CLAUDE.md

Upute za Claude Code pri radu na projektu **Dogo**.

Phoenix/Elixir usage rules žive u [`AGENTS.md`](AGENTS.md) — pročitaj ih prije
pisanja koda. Ovaj dokument dodaje konvencije specifične za projekt.

## Projekt

Dogo pronalazi plaže prikladne za pse na hrvatskom Jadranu. Aplikacija
`:dogo`, moduli `Dogo` (domena) i `DogoWeb` (web sloj).

Cjeloviti plan, epici i user storyji: [`docs/PLAN.md`](docs/PLAN.md).
Rad ide **story po story**: jedan story = jedna grana = jedan PR.

## Konvencije

### Konteksti

| Kontekst | Odgovornost |
|---|---|
| `Dogo.Beaches` | plaže: shema, prostorni upiti, filteri |
| `Dogo.Geo` | geometrija i geografija: otoci, udaljenosti, bounding box |
| `Dogo.Import` | uvoz podataka: Overpass klijent, Oban jobovi, demo atributi |

Web sloj nikada ne piše Ecto upite izravno — sve ide kroz kontekst.

### Vanjski servisi

Overpass, Nominatim i OSRM su **uvijek iza behaviour modula**
(npr. `Dogo.Import.OverpassClient` s `@behaviour`), a implementacija se bira
kroz konfiguraciju. U testovima se mockiraju Moxom.

**Testovi ne smiju raditi mrežne pozive.** Odgovori vanjskih servisa spremaju
se kao fixture u `test/support/fixtures/`.

### Prostorni podaci

- Geometrija se sprema kao `geometry(..., 4326)` i čita kao `Geo.*` struct
  (Postgrex tipovi: `Dogo.PostgrexTypes`).
- Udaljenosti u metrima računaju se na `::geography`, nikad na `geometry`.
- Svaka geometrijska kolona po kojoj se pretražuje ima GiST indeks.
- Prostorni testovi idu na stvarnu PostGIS bazu, ne na mock.

### Privatnost

Lokacija korisnika se **ne sprema** u bazu ni u logove.

## Naredbe za provjeru

```sh
mix format
mix credo --strict
mix dialyzer
mix test
mix precommit    # sve osim dialyzera
```

## Definition of Done

Prije nego javiš da je story gotov, provjeri sve iz odjeljka 4 u
[`docs/PLAN.md`](docs/PLAN.md):

1. kriteriji prihvaćanja ispunjeni
2. testovi napisani i prolaze
3. `mix format`, Credo i Dialyzer bez upozorenja
4. CI zelen
5. ako se mijenja ponašanje vidljivo korisniku → prijevodi hr/en/de dodani
6. ako se uvodi arhitektonska odluka → ADR u `docs/adr/`
