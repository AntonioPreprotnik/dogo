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

  # Tvrdi limit za bbox upite: iznad ovoga karta ionako nije čitljiva bez
  # klasteriranja, a odgovor postaje preskup i za server i za mobitel.
  @bbox_limit 500

  @typedoc """
  Opcije prostornih upita.

  - `:limit` — najviše rezultata (zadano #{@default_limit})
  - `:dog_status` — popis statusa, npr. `[:designated, :allowed]`
  - `:surface` — popis podloga
  - `:amenities` — popis obaveznih sadržaja, npr. `[:water, :shade]`
  """
  @type query_opts :: keyword()

  @doc "Tvrdi limit rezultata za bbox upite."
  def bbox_limit, do: @bbox_limit

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

  @doc """
  Plaže unutar vidljivog dijela karte.

  `bbox` je `{min_lon, min_lat, max_lon, max_lat}`. Koristi `ST_MakeEnvelope`
  i operator `&&`, koji ide preko GiST indeksa nad `geometry`.

  Vraća `{:ok, beaches}` ili `{:too_many, beaches}` kad rezultata ima više od
  `bbox_limit/0` — tada sučelje traži veći zoom ili klasteriranje (E3-S3).
  Rezultat nije poredan po udaljenosti jer bbox nema referentnu točku.
  """
  @spec within_bbox({float(), float(), float(), float()}, query_opts()) ::
          {:ok, [Beach.t()]} | {:too_many, [Beach.t()]}
  def within_bbox({min_lon, min_lat, max_lon, max_lat}, opts \\ []) do
    limit = Keyword.get(opts, :limit, @bbox_limit)

    beaches =
      Beach
      |> where(
        [b],
        fragment(
          "? && ST_MakeEnvelope(?, ?, ?, ?, 4326)",
          b.geom,
          ^min_lon,
          ^min_lat,
          ^max_lon,
          ^max_lat
        )
      )
      |> apply_filters(opts)
      |> order_by([b], b.id)
      |> limit(^(limit + 1))
      |> Repo.all()

    if length(beaches) > limit do
      {:too_many, Enum.take(beaches, limit)}
    else
      {:ok, beaches}
    end
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
