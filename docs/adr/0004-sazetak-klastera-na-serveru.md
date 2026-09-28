# 4. Sažetak klastera na serveru, ne samo u MapLibreu

- **Status:** prihvaćeno
- **Datum:** 2026-09-28

## Kontekst

Story E3-S3 traži klasteriranje markera i predlaže ugrađeno klasteriranje
GeoJSON sourcea u MapLibreu. To pretpostavlja da klijent ima **sve** točke iz
vidljivog dijela karte — inače su brojevi u klasterima krivi, a broj je cijela
poanta klastera.

E2-S2 je uveo tvrdi limit od 500 plaža po bbox upitu, upravo zato što slanje
svih nije besplatno. Izmjereno na stvarnim podacima (3107 plaža, cijeli Jadran
u jednom pogledu):

| Oblik | Veličina |
|---|---|
| puni GeoJSON | 917 KB |
| sažeti GeoJSON (id + status) | 206 KB |

To je trošak **po svakom pomaku karte**. Na mobilnoj vezi je neupotrebljivo.

Spoj tog limita i klijentskog klasteriranja daje najgori ishod: klasteri bi
zbrajali 500 umjesto 3107 i izgledali uvjerljivo dok lažu.

## Razmotrene opcije

1. **Poslati sve i pustiti MapLibre da klasterira.** Točni brojevi, ali 917 KB
   po pomaku. Radilo bi danas jer je skup malen; ne skalira i loše se ponaša
   na mobitelu, a upravo je mobitel ciljani uređaj.
2. **Zadržati limit i prikazati upozorenje umjesto klastera.** Jednostavno, ali
   korisniku na malom zoomu ne daje ništa — a to je prvi ekran koji vidi.
3. **Sažeti na serveru.** `ST_SnapToGrid` grupiranje vraća nekoliko desetaka
   ćelija s točnim brojevima, neovisno o veličini skupa.

## Odluka

Oba, ovisno o broju rezultata:

- **Ispod limita** (500) server šalje pojedinačne plaže, a MapLibre ih
  klasterira ugrađenim mehanizmom, kako story i traži. Klik na klaster koristi
  `getClusterExpansionZoom` i zumira točno onoliko koliko treba.
- **Iznad limita** server šalje sažetak: `Beaches.cluster_in_bbox/2` grupira po
  `ST_SnapToGrid` i vraća težište i broj po ćeliji. Klijent ih crta istim
  stilom i ne klasterira ih dalje — broj je već konačan.

Veličina ćelije se izvodi iz širine karte u pikselima (~70 px po ćeliji), ista
ideja kao MapLibreov `clusterRadius`, pa gustoća klastera ne ovisi o tome je li
korisnik na mobitelu ili na širokom monitoru.

Svojstvo se zove `point_count`, isto kao u MapLibreovim klasterima, pa jedan
stil pokriva oba slučaja i korisnik ne vidi razliku.

## Posljedice

- Brojevi su točni na svakom zoomu: zbroj ćelija je stvaran broj plaža u
  pogledu, ne odrezan. Test to izrijekom provjerava.
- Promet na malom zoomu padne s ~900 KB na nekoliko KB.
- Dvije putanje umjesto jedne, i prag između njih je još jedno mjesto koje može
  iznenaditi. Ublaženo time što obje izgledaju isto i što su obje pokrivene
  testovima.
- Agregacija je jedan dodatni upit, ali ide preko istog GiST indeksa kao i bbox
  filtar.
- Lista rezultata i dalje radi na pojedinačnim plažama, pa korisnik na malom
  zoomu vidi klastere na karti i konkretne najbliže plaže u listi.
