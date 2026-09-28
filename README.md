# Dogo 🐕🏖️

[![CI](https://github.com/CHANGE-ME/dogo/actions/workflows/ci.yml/badge.svg)](https://github.com/CHANGE-ME/dogo/actions/workflows/ci.yml)

Web aplikacija koja vlasniku psa na hrvatskom Jadranu pokazuje najbliže plaže
na kojima smije biti sa psom — s pravom udaljenošću, upozorenjem kada je plaža
"preko mora" i popisom sadržaja.

**Demo:** _(uskoro)_ · **Plan izrade:** [`docs/PLAN.md`](docs/PLAN.md)

> **Disclaimer:** Podaci su demonstracijski. Lokacije plaža potječu iz
> OpenStreetMapa (© OpenStreetMap contributors, ODbL). Atributi vezani uz pse
> djelomično su generirani i ne odražavaju stvarna pravila.

## Tehnički zanimljivo

- **Prostorni upiti u PostGIS-u** — KNN pretraga (`ORDER BY geom <-> point`) uz
  GiST indeks, udaljenosti na `geography` tipu. Izmjereni učinak indeksa u
  `docs/performance.md`.
- **Problem otoka** — zračna udaljenost na Jadranu vara; poligoni otoka iz OSM-a
  služe za oznaku "preko mora" i filter "bez trajekta".
- **Idempotentan uvoz** — Oban job s upsertom po `osm_id`; ponovno pokretanje ne
  stvara duplikate.
- **Asinkroni OSRM** — lista se prikaže odmah sa zračnom udaljenošću, vrijeme
  vožnje stiže naknadno; timeout i fallback ne ruše stranicu.

## Stack

Elixir · Phoenix LiveView · PostgreSQL + PostGIS · Oban · MapLibre GL JS ·
Gettext (hr/en/de) · Fly.io

## Lokalno pokretanje

Potreban je PostgreSQL **s PostGIS ekstenzijom**. Najlakše preko Dockera:

```sh
docker compose up -d          # PostgreSQL 16 + PostGIS na portu 5432
mix setup                     # deps, baza, migracije, assets
mix phx.server                # http://localhost:4000
```

Bez Dockera: postavi varijable `PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD` prema
svojoj instalaciji (paket `postgresql-16-postgis-3`).

## Provjere kvalitete

```sh
mix precommit   # compile --warnings-as-errors, deps.unlock, format, credo, test
mix dialyzer
```

## Dokumentacija

- [`docs/PLAN.md`](docs/PLAN.md) — vizija, opseg, epici i storyji
- [`docs/adr/`](docs/adr/) — arhitektonske odluke
- [`AGENTS.md`](AGENTS.md) / [`CLAUDE.md`](CLAUDE.md) — konvencije za rad s AI alatima

## Licenca podataka

Podaci o plažama: © OpenStreetMap contributors, [ODbL](https://www.openstreetmap.org/copyright).
