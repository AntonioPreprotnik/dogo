defmodule Dogo.Repo.Migrations.AddBridgeConnectedToIslands do
  use Ecto.Migration

  # Otoci do kojih se dolazi mostom, bez trajekta. Popis je kratak i stabilan
  # (zadnji je most na Ciovo iz 2018.), pa je u kodu, a ne u OSM-u: OSM nema
  # tag koji bi to izravno rekao, nego bi se moralo zakljucivati iz mreze cesta.
  @bridge_connected [
    "Krk",
    "Pag",
    "Vir",
    "Čiovo",
    "Murter",
    "Ugljan",
    "Pašman",
    "Školjić",
    "Sveti Marko"
  ]

  def up do
    alter table(:islands) do
      add :bridge_connected, :boolean, null: false, default: false
    end

    flush()

    names = Enum.map_join(@bridge_connected, ", ", &"'#{&1}'")
    execute("UPDATE islands SET bridge_connected = true WHERE name IN (#{names})")
  end

  def down do
    alter table(:islands) do
      remove :bridge_connected
    end
  end
end
