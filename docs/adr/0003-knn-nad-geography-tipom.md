# 3. KNN pretraga nad `geography`, ne nad `geometry`

- **Status:** prihvaćeno
- **Datum:** 2026-09-28

## Kontekst

Osnovni upit aplikacije je "20 najbližih plaža zadanoj točki". PostGIS to rješava
KNN operatorom `<->` uz GiST indeks:

```sql
ORDER BY geom <-> point LIMIT 20
```

Nad tipom `geometry` taj operator računa **ravninsku udaljenost u stupnjevima**.
Stupanj zemljopisne širine je svugdje ~111 km, a stupanj duljine se skraćuje s
kosinusom širine. Na 43. paraleli (Split) faktor je `cos(43.5°) ≈ 0.725`, dakle
stupanj duljine je oko 27 % kraći.

Posljedica: plaža 0.02° istočno je stvarno ~1.6 km daleko, a plaža 0.02° sjeverno
~2.2 km — ali ravninski su jednako "daleko" i poredak ovisi o slučaju. Na
razvučenoj obali s puno otoka to daje vidljivo krive rezultate.

## Razmotrene opcije

1. **`geom <-> point` na geometriji, pa presortirati u aplikaciji.** Indeks bi
   radio, ali bi trebalo dohvatiti puno više od `limit` redaka da bi presortiranje
   bilo ispravno, a koliko više nije moguće znati unaprijed.
2. **Projicirati u metarski koordinatni sustav (npr. EPSG:3765, HTRS96/TM).**
   Točno za Hrvatsku i brzo, ali veže shemu na jednu državu i komplicira razmjenu
   podataka, koji iz OSM-a dolaze u 4326.
3. **`geography` tip.** Operator `<->` nad `geography` vraća metre po sferoidu i
   poredak je stvaran.

## Odluka

Kolona ostaje `geometry(Point, 4326)`, a upiti castaju na `geography`:

```sql
ORDER BY point::geography <-> geom::geography
```

Da planer to može ubrzati, dodan je **funkcijski GiST indeks nad castom**:

```sql
CREATE INDEX beaches_geom_geography_index ON beaches USING gist ((geom::geography));
```

Bez tog indeksa cast onemogućuje korištenje običnog `beaches_geom_index`.

`EXPLAIN ANALYZE` potvrđuje Index Scan, bez koraka sortiranja:

```
Limit
  ->  Index Scan using beaches_geom_geography_index on beaches
        Order By: ((geom)::geography <-> '...'::geography)
```

Kolona ostaje `geometry` jer poligoni otoka (E5) trebaju `ST_Contains` i srodne
operacije, koje su nad `geometry` jednostavnije i brže.

## Posljedice

- Udaljenosti su u metrima bez konverzije i poredak je stvaran.
- Dva GiST indeksa na istoj koloni: jedan za `geometry` operacije (bbox,
  `ST_Contains`), jedan za `geography` KNN. Dodatni prostor i trošak pri pisanju,
  ali uvoz je rijedak, a čitanje često.
- Mjerenje razlike s indeksom i bez njega je u `docs/performance.md` (E2-S4).
