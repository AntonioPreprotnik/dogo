defmodule Dogo.Repo.Migrations.AddObanJobsTable do
  use Ecto.Migration

  def up, do: Oban.Migration.up(version: 14)

  # Verzija 1 vraca bazu u stanje prije Obana, ukljucujuci brisanje tablica.
  def down, do: Oban.Migration.down(version: 1)
end
