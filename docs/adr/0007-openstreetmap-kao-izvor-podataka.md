# 7. OpenStreetMap kao izvor podataka o plažama

- **Status:** prihvaćeno
- **Datum:** 2026-09-29 (odluka donesena u E1-S2; zapisana naknadno, u E7-S2)

## Kontekst

Aplikaciji trebaju lokacije plaža na cijeloj hrvatskoj obali i, idealno,
podatak smije li se na plažu sa psom. Razmotreni izvori:

1. **Ručno prikupljen popis** plaža za pse (turističke zajednice, blogovi).
2. **Komercijalni API** mjesta (Google Places i sl.).
3. **OpenStreetMap**, preko Overpass API-ja.

## Odluka

Plaže (i otoci, ADR 0005) dolaze iz OSM-a: `natural=beach` i
`leisure=beach_resort` unutar granice Hrvatske, s `out center tags`. Uvoz je
Oban job s upsertom po `osm_id`, pa je ponovno pokretanje sigurno.

## Zašto

- **Pokrivenost.** Jedan upit daje 3109 plaža na cijeloj obali i otocima.
  Ručni popis bi imao desetke, i to one koje su već poznate.
- **Licenca dopušta ono što radimo.** ODbL dopušta spremanje i prikaz uz
  atribuciju. Uvjeti komercijalnih API-ja tipično zabranjuju trajno spremanje
  rezultata, a prostorni upiti u PostGIS-u (ADR 0002) upravo to traže.
- **Isti izvor za sve.** Plaže, otoci i podloga karte (OpenFreeMap) su svi OSM:
  isti koordinatni sustav, ista licenca, jedna atribucija.
- **Besplatno i bez ključa.** Za portfolio projekt to znači da ga recenzent može
  pokrenuti lokalno bez registracije.

## Što OSM nema

Izmjereno na uvezenim podacima:

| | Plaža | Udio |
|---|---|---|
| ukupno | 3109 | |
| ima `dog=*` tag | 130 | 4 % |
| bez imena | 2185 | 70 % |

Upravo podatak koji aplikaciji najviše treba, smije li pas na plažu, gotovo
nikad nije mapiran. Zato se nedostajući atributi **generiraju
deterministički iz `osm_id`-a** (`Dogo.Import.Attributes`, E1-S4): isti ulaz
uvijek daje isti rezultat, pa je uvoz idempotentan i demo izgleda isto pri
svakom pokretanju.

Generirani podatak se nikad ne predstavlja kao stvaran. Izvor se sprema u
`dog_status_source` (`osm` ili `generated`), detalj plaže ga prikazuje, a
disclaimer je u footeru i README-u.

## Posljedice

- Aplikacija je u ovom obliku **demonstracija**, ne vodič na koji se može
  osloniti. Put do stvarnih podataka je jasan: izvor `generated` zamijeniti
  stvarnim (unos korisnika, podaci turističkih zajednica) bez promjene sheme.
- Bezimene plaže se u listi prikazuju kao "Plaža bez imena". To je stvarno
  stanje OSM-a, a ne greška uvoza.
- Ovisimo o javnom Overpass API-ju, koji ima ograničenja prometa. Uvoz je zato
  rijedak, ide kroz red s jednim radnikom i sam je siguran za ponavljanje. Pri
  prevelikom prometu Overpass privremeno odbija veze; to se ne rješava
  agresivnijim ponavljanjem, nego čekanjem ili mirrorom (`:overpass_endpoint`).
- Atribucija "© OpenStreetMap contributors" je obavezna i nalazi se na svakoj
  stranici (E1-S5).
