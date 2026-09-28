# 1. Bilježenje arhitektonskih odluka

- **Status:** prihvaćeno
- **Datum:** 2026-09-28

## Kontekst

Dogo je portfolio projekt. Recenzent (tehnički intervjuer) treba u nekoliko
minuta vidjeti ne samo *što* je napravljeno, nego i *zašto*. Kod pokazuje
rezultat odluke, ali ne i odbačene alternative ni kompromise.

## Odluka

Svaku netrivijalnu tehničku odluku bilježimo kao ADR (Architecture Decision
Record) u `docs/adr/`, numerirano rastuće: `NNNN-kratki-naslov.md`.

Format svakog zapisa:

- **Status**: predloženo | prihvaćeno | zamijenjeno ADR-om NNNN
- **Kontekst**: problem i ograničenja
- **Odluka**: što je odabrano
- **Posljedice**: što dobivamo, što gubimo, što ostaje otvoreno

ADR se ne mijenja nakon prihvaćanja. Ako se odluka promijeni, piše se novi ADR
koji zamjenjuje stari, a stari dobiva status "zamijenjeno".

Definition of Done (vidi `docs/PLAN.md`, odjeljak 4) zahtijeva ADR za svaki
story koji uvodi arhitektonsku odluku.

## Posljedice

- Recenzent ima jedno mjesto za razumijevanje inženjerskog razmišljanja.
- Mali dodatni trošak pisanja po storyju.
- Povijest odluka je čitljiva bez kopanja po git logu.
