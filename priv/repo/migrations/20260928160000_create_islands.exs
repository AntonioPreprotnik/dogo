defmodule Dogo.Repo.Migrations.CreateIslands do
  use Ecto.Migration

  def change do
    create table(:islands) do
      add :osm_id, :string, null: false
      add :name, :string
      add :geom, :"geometry(MultiPolygon,4326)", null: false
      add :area_m2, :float, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:islands, [:osm_id])

    # Pripadnost plaze otoku se racuna kroz ST_DWithin nad ovim indeksom.
    create index(:islands, [:geom], using: :gist)

    alter table(:beaches) do
      add :island_id, references(:islands, on_delete: :nilify_all)
    end

    # Filtar "samo bez trajekta" (E5-S2) gada ovu kolonu.
    create index(:beaches, [:island_id])
  end
end
