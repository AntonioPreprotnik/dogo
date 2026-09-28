# 2. PostGIS umjesto izračuna udaljenosti u aplikaciji

- **Status:** prihvaćeno
- **Datum:** 2026-09-28

## Kontekst

Osnovna funkcija aplikacije je "najbliže plaže zadanoj točki" nad nekoliko
tisuća zapisa, uz filtere i pretragu po vidljivom dijelu karte. Dvije su
opcije:

1. Dohvatiti kandidate iz baze i računati udaljenost u Elixiru (Haversine).
2. Prepustiti prostorne operacije PostgreSQL-u s PostGIS ekstenzijom.

## Odluka

Koristimo PostgreSQL + PostGIS (`geo_postgis` + Postgrex tipovi), a geometriju
spremamo kao `geometry(Point, 4326)`.

- KNN pretraga ide preko operatora `<->` uz GiST indeks (`ORDER BY geom <-> $1`).
- Udaljenosti u metrima računaju se na `::geography` tipu, koji uzima u obzir
  oblik Zemlje.
- Bounding box upiti koriste `ST_MakeEnvelope` i `&&`, radijus `ST_DWithin`.

## Posljedice

- Upit "najbliže" koristi indeks i ostaje brz s rastom broja zapisa; verzija u
  aplikaciji zahtijevala bi dohvat cijele tablice (mjerenje u
  `docs/performance.md`, story E2-S4).
- Lokalni razvoj i CI zahtijevaju PostGIS, ne običan Postgres. Rješavamo
  `docker-compose.yml`-om (image `postgis/postgis`) i istim imageom kao service
  containerom u CI-ju.
- Deploy mora koristiti bazu na kojoj se smije stvoriti ekstenzija
  (`CREATE EXTENSION postgis`).
- Kasnije funkcije (poligoni otoka, `ST_Contains` za pripadnost otoku u E5)
  dolaze gotovo besplatno.
