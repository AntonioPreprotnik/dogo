defmodule Dogo.Repo.Migrations.CreateBeaches do
  use Ecto.Migration

  @surfaces ~w(pebble sand rock concrete mixed unknown)
  @dog_statuses ~w(designated allowed not_allowed unknown)
  @dog_status_sources ~w(osm generated)

  def change do
    create table(:beaches) do
      add :osm_id, :string, null: false
      add :name, :string
      add :geom, :"geometry(Point,4326)", null: false
      add :area, :"geometry(MultiPolygon,4326)"
      add :surface, :string, null: false, default: "unknown"
      add :dog_status, :string, null: false, default: "unknown"
      add :dog_status_source, :string, null: false, default: "generated"
      add :amenities, :map, null: false, default: %{}
      add :municipality, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:beaches, [:osm_id])

    # KNN pretraga (`ORDER BY geom <-> point`) i bbox upiti idu preko ovog
    # indeksa; bez njega bi svaki upit citao cijelu tablicu.
    create index(:beaches, [:geom], using: :gist)

    # Enumi se cuvaju kao tekst radi lakseg dodavanja vrijednosti, ali baza
    # svejedno odbija nepoznate - Ecto.Enum sam po sebi ne stiti od upisa
    # mimo changeseta (uvoz, rucni SQL).
    create constraint(:beaches, :beaches_surface_check,
             check: "surface IN (#{sql_list(@surfaces)})"
           )

    create constraint(:beaches, :beaches_dog_status_check,
             check: "dog_status IN (#{sql_list(@dog_statuses)})"
           )

    create constraint(:beaches, :beaches_dog_status_source_check,
             check: "dog_status_source IN (#{sql_list(@dog_status_sources)})"
           )
  end

  defp sql_list(values), do: Enum.map_join(values, ", ", &"'#{&1}'")
end
