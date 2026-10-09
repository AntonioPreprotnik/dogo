# 11. Ručne izmjene imaju prednost pred uvozom

- **Status:** prihvaćeno
- **Datum:** 2026-10-09

## Kontekst

Uvoz plaža je idempotentan upsert po `osm_id` (E1-S3): svako pokretanje
prepisuje ime, položaj, status i sadržaje onime što vrati Overpass. Uvoz se
pokreće ponovno, sad i iz admin sučelja.

Admin ispravlja plažu jer podatak iz OSM-a (ili generirani demo podatak) ne
valja. Kad bi sljedeći uvoz ispravku tiho poništio, admin sučelje ne bi imalo
smisla.

## Odluka

1. **Kolona `beaches.edited_at`.** Postavlja je svaka stvarna promjena kroz
   admin formu (`Beach.admin_changeset/2`). Spremanje bez promjena je ne
   postavlja.
2. **Uvoz preskače plaže s `edited_at`.** Izbacuju se prije upisa, pa ih
   brojač izvještava kao `kept`. Isti uvjet stoji i u samom upsertu
   (`ON CONFLICT … DO UPDATE … WHERE edited_at IS NULL`), za slučaj da admin
   spremi izmjenu dok uvoz traje.
3. **Novi izvor statusa `:manual`.** Kad admin promijeni status psa, izvor
   postaje `:manual`, a javna stranica ga tako i označava. Generirani podatak
   ne smije izgledati kao provjereno pravilo (disclaimer, E1-S4), ali ni
   ručno unesen ne smije izgledati kao da dolazi iz OSM-a.
4. **Ručno dodane plaže** dobivaju `osm_id` oblika `manual/…`, koji se ne može
   sudariti s OSM-om.
5. **Brisanje je stvarno brisanje.** Plaža iz OSM-a vratit će se pri
   sljedećem uvozu, i sučelje to kaže prije potvrde.

## Razmotrene opcije

- **Zapis po polju (koje je polje ručno mijenjano).** Uvoz bi i dalje mogao
  osvježavati polja koja admin nije dirao. To je preciznije, ali traži
  dodatnu strukturu i pravila spajanja za korist koja ovdje ne postoji: plaže
  se rijetko mijenjaju, a ispravljena plaža je ionako pregledana.
- **Ispravke u zasebnoj tablici, spojene pri čitanju.** Čuva izvorni podatak,
  ali svaki prostorni upit (KNN, bbox, klasteri) bi morao spajati dvije
  tablice. Takav trošak na najčešćem putu nije opravdan.
- **Soft delete, da obrisana plaža ostane obrisana.** Svaki javni upit bi
  morao filtrirati obrisane, a greška u jednom od njih vratila bi plažu na
  kartu. OSM je izvor istine za postojanje plaže: trajno brisanje ide
  ispravkom u OSM-u.

## Posljedice

- Ispravljena plaža više ne prati OSM. Ako se OSM kasnije popravi, admin to
  mora preuzeti ručno. Popis pokazuje datum ispravke, pa se takve plaže lako
  nađu.
- Ručno pomaknuta plaža odmah dobiva otok (`Islands.at/1`), bez čekanja na
  uvoz otoka. O otoku ovisi upozorenje "preko mora".
- Poligon (`area`) se ne uređuje: forma mijenja samo centroid.
