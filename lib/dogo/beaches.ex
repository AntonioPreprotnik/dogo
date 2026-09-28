defmodule Dogo.Beaches do
  @moduledoc """
  Kontekst za plaže: perzistencija i prostorni upiti.

  Web sloj nikada ne piše Ecto upite izravno, nego ide kroz ovaj modul.

  Sve udaljenosti su u metrima i računaju se nad `geography` tipom, dakle po
  sferoidu. Vidi `docs/adr/0003-knn-nad-geography-tipom.md`.
  """

  import Ecto.Query

  alias Dogo.Beaches.Beach
  alias Dogo.Repo

  @default_limit 20

  @typedoc """
  Opcije prostornih upita.

  - `:limit` — najviše rezultata (zadano #{@default_limit})
  - `:dog_status` — popis statusa, npr. `[:designated, :allowed]`
  - `:surface` — popis podloga
  - `:amenities` — popis obaveznih sadržaja, npr. `[:water, :shade]`
  - `:within_m` — ograniči na radijus u metrima
  """
  @type query_opts :: keyword()

  @doc "Dohvaća plažu po ID-u ili diže `Ecto.NoResultsError`."
  def get_beach!(id), do: Repo.get!(Beach, id)

  @doc "Dohvaća plažu po OSM ID-u (`\"way/123456\"`), ili `nil`."
  def get_beach_by_osm_id(osm_id), do: Repo.get_by(Beach, osm_id: osm_id)

  @doc "Sprema novu plažu."
  def create_beach(attrs) do
    %Beach{}
    |> Beach.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Ažurira postojeću plažu."
  def update_beach(%Beach{} = beach, attrs) do
    beach
    |> Beach.changeset(attrs)
    |> Repo.update()
  end

  @doc "Changeset za forme."
  def change_beach(%Beach{} = beach, attrs \\ %{}), do: Beach.changeset(beach, attrs)

  @doc "Broj plaža u bazi."
  def count_beaches, do: Repo.aggregate(Beach, :count)

  @doc """
  Najbliže plaže zadanoj točki, poredane po stvarnoj udaljenosti.

  Svaka plaža ima popunjen virtualni `distance_m` (metri, po sferoidu).

  Poredak ide preko KNN operatora `<->` nad `geography` tipom, što koristi
  funkcijski GiST indeks `beaches_geom_geography_index`.

  ## Primjer

      Beaches.nearest(point, limit: 10, dog_status: [:designated, :allowed])
  """
  @spec nearest(Geo.Point.t(), query_opts()) :: [Beach.t()]
  def nearest(%Geo.Point{} = point, opts \\ []) do
    Beach
    |> with_distance(point)
    |> apply_filters(opts)
    |> order_by([b], fragment("? <-> ?", type(^point, Geo.PostGIS.Geometry), b.geom))
    |> limit(^Keyword.get(opts, :limit, @default_limit))
    |> Repo.all()
  end

  defp with_distance(query, point) do
    from b in query,
      select_merge: %{
        distance_m:
          fragment(
            "ST_Distance(?::geography, ?::geography)",
            b.geom,
            type(^point, Geo.PostGIS.Geometry)
          )
      }
  end

  defp apply_filters(query, opts) do
    Enum.reduce(opts, query, fn
      {:dog_status, [_ | _] = statuses}, query ->
        where(query, [b], b.dog_status in ^statuses)

      {:surface, [_ | _] = surfaces}, query ->
        where(query, [b], b.surface in ^surfaces)

      {:amenities, [_ | _] = amenities}, query ->
        required = Map.new(amenities, &{to_string(&1), true})
        where(query, [b], fragment("? @> ?", b.amenities, ^required))

      _other, query ->
        query
    end)
  end
end
