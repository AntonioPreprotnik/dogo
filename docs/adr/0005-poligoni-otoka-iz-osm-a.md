# 5. Poligoni otoka iz OSM-a, sastavljeni u PostGIS-u

- **Status:** prihvaćeno
- **Datum:** 2026-09-28

## Kontekst

Diferencijator projekta (E5) je odgovor na pitanje "je li ova plaža preko
mora?". Za to treba znati na kojoj je kopnenoj masi svaka plaža, a to znači
poligone hrvatskih otoka.

## Zašto ne ručni popis

Ručni popis od dvadesetak velikih otoka bio bi kraći za napisati, ali:

- popis daje **imena**, a treba nam **geometrija** — bez poligona ne može se
  odgovoriti na kojem je otoku koja plaža
- Hrvatska ima preko tisuću otoka; granica "velikog" je proizvoljna i svaka
  odabrana granica tiho izostavlja plaže
- ručni podaci zastarijevaju bez ikakvog signala, a OSM ima povijest promjena
- plaže već dolaze iz OSM-a, pa isti izvor znači isti koordinatni sustav i
  istu licencu

## Kako su otoci mapirani

Provjereno na stvarnim podacima (`place=island`, područje Hrvatske): **181
objekt, od toga 101 way i 80 relacija**. Svi veliki otoci su relacije: Krk,
Pag, Cres, Brač, Hvar, Korčula, Rab, Lošinj, Mljet, Vir, Čiovo, Murter.

Relacija nije poligon. Krk ima **72 vanjska člana**, nijedan poredan, a samo
jedan zatvoren sam po sebi. Sastavljanje u prsten znači spajanje segmenata uz
pažnju na redoslijed i smjer.

## Odluka

Poligone **ne sastavljamo u Elixiru**. Parser vraća samo popis linija, a posao
radi baza:

```sql
ST_Multi(ST_CollectionExtract(ST_Polygonize(ARRAY[ST_UnaryUnion($1)]), 3))
```

`ST_UnaryUnion` je nužan, ne ukras: bez njega `ST_Polygonize` vrati prazno čim
se dva segmenta križaju ili dodiruju mimo krajnjih točaka — a stvarni OSM
podaci to rade. Provjereno na Krku: bez nodanja 0 poligona, s nodanjem 2 dijela
i **405,4 km²**, dok je stvarna površina Krka 405,8 km².

Ako ni nakon nodanja nema poligona, otok se **preskače i broji**, umjesto da se
spremi prazan poligon koji bi tiho isključio sve plaže na njemu.

### Uvoz ide u dvije faze

Geometrija svih 181 otoka u jednom zahtjevu su deseci megabajta i Overpass na
tome odustane (samo Krk je 1 MB). Zato:

1. `out bb tags` za sve otoke — 75 KB, samo granice i imena.
2. Filtar po površini bounding boxa (zadano ≥ 1 km², što je 97 otoka).
3. `out geom` u serijama, s pauzom između njih.

Pauza nije kozmetička: bez nje Overpass odgovori s 429 i na kraju odbije vezu.
To se dogodilo pri prvom pokušaju uvoza.

## Pridruživanje plaža

`ST_DWithin` na `geography` s 150 m tolerancije, uz odabir najbližeg otoka kad
ih je više u dometu. Tolerancija postoji jer centroid plaže zna pasti koji
metar u more; kanali između otoka i kopna su svugdje puno širi od 150 m.

Veze se pri svakom uvozu prvo brišu pa iznova računaju, inače bi plaža
pogrešno pridružena jednom uvozu zadržala vezu i nakon ispravka podataka.

## Posljedice

- Točna geometrija bez ručnog održavanja, uz istu licencu kao i plaže.
- Uvoz otoka je sporiji i osjetljiviji od uvoza plaža, pa ide kao zaseban Oban
  job s većim `unique` prozorom.
- Ovisimo o kvaliteti OSM relacija. Nepotpuna relacija znači otok bez poligona;
  to se broji i logira umjesto da prođe nezapaženo.
