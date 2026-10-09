# 10. Admin bez registracije, prijava samo lozinkom

- **Status:** prihvaćeno
- **Datum:** 2026-10-09

## Kontekst

E8-S1 traži admin sučelje za ručne ispravke plaža i ponovno pokretanje uvoza.
Javni dio aplikacije nema korisnike i neće ih imati. Admin je jedna ili dvije
osobe koje vode projekt.

Standardni `phx.gen.auth` (Phoenix 1.8) donosi registraciju, prijavu magic
linkom, potvrdu emaila i promjenu emaila. Sve osim lozinke ide preko maila, a
produkcija nema konfiguriran mailer (`Swoosh.Adapters.Local` samo u razvoju).

LiveDashboard je od E7-S4 na `/admin/dashboard` iza basic autha
(`DASHBOARD_USER`, `DASHBOARD_PASSWORD`). Tadašnje obrazloženje je bilo
upravo to da aplikacija nema admina.

## Odluka

1. **`phx.gen.auth`, pa skraćen.** Ostaju sesije u bazi (`admins_tokens`),
   "zapamti me" cookie, ponovna prijava za osjetljive radnje (sudo) i
   prekidanje LiveView veza pri odjavi. Uklonjeni su registracija, magic
   link, potvrda i promjena emaila te `AdminNotifier`.
2. **Admin nastaje samo iz konzole:** `mix admin.create EMAIL`, u produkciji
   `Dogo.Release.create_admin/1`. Lozinka je nasumična i ispisuje se jednom.
   Ne prima se kao argument, da ne ostane u povijesti shella. Admin je mijenja
   na `/admin/settings`.
3. **Sve pod `/admin`, iza istog mehanizma**, uključujući LiveDashboard.
   Basic auth i njegove varijable okoline su uklonjeni.
4. **Javni dio ne čita sesiju admina.** Plug `fetch_current_scope_for_admin`
   je u zasebnom `:admin` pipelineu, a ne u `:browser`, pa javni zahtjevi ne
   dotiču tablice admina.
5. **Autorizacija i u kontekstu.** Admin funkcije u `Dogo.Beaches` primaju
   `%Scope{admin: %Admin{}}` kao prvi argument. Bez prijavljenog admina poziv
   pada, i kad bi ruta greškom završila izvan zaštićenog bloka.

## Razmotrene opcije

- **Zadržati basic auth i za admin sučelje.** Najmanje koda, ali nema odjave,
  ni sesije koja istječe, ni CSRF zaštite vezane uz sesiju. Pored toga, story
  izričito traži rad s autentifikacijom i formama.
- **Puni `phx.gen.auth` s magic linkom.** Traži produkcijski mailer, dakle
  novi vanjski servis i tajnu, samo za jednog ili dva admina.
- **Javna registracija s odobrenjem.** Otvara površinu za napad (registracija,
  enumeracija emailova) bez ikakve koristi za projekt ove veličine.

## Posljedice

- Zaboravljena lozinka se ne može resetirati iz sučelja. Novi admin ili nova
  lozinka idu kroz konzolu, što je za ovakav projekt prihvatljivo.
- Za deploy više ne trebaju `DASHBOARD_USER` i `DASHBOARD_PASSWORD`. Nakon
  prvog deploya treba stvoriti admina (upute u `fly.toml`).
- Novi dependency: `bcrypt_elixir`. To je NIF, ali Dockerfile već ima
  `build-essential`.
- Testovi iz generatora su zadržani, prilagođeni i prevedeni na hrvatski
  opis, a za uklonjene dijelove postoje testovi da ih nema (nema ruta za
  registraciju, nema magic link forme).
