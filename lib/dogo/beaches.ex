defmodule Dogo.Beaches do
  @moduledoc """
  Kontekst za plaže: perzistencija i prostorni upiti.

  Web sloj nikada ne piše Ecto upite izravno, nego ide kroz ovaj modul.

  Sve udaljenosti su u metrima i računaju se nad `geography` tipom, dakle po
  sferoidu. Vidi `docs/adr/0003-knn-nad-geography-tipom.md`.
  """

  import Ecto.Query

  alias Dogo.Accounts.Admin
  alias Dogo.Accounts.Scope
  alias Dogo.Beaches.Beach
  alias Dogo.Geo.Island
  alias Dogo.Geo.Islands
  alias Dogo.Repo

  @default_limit 20

  # Tvrdi limit za bbox upite: iznad ovoga karta ionako nije čitljiva bez
  # klasteriranja, a odgovor postaje preskup i za server i za mobitel.
  @bbox_limit 500

  # Ciljana veličina ćelije sažetka na ekranu, u pikselima. Ista ideja kao
  # MapLibreov `clusterRadius`: gustoća klastera ne smije ovisiti o tome je li
  # korisnik na mobitelu ili na širokom monitoru.
  @cluster_cell_px 70
  @default_columns 16

  # Radijusi ponuđeni u sučelju, u metrima.
  @radii_m [5_000, 10_000, 25_000, 50_000]

  @typedoc """
  Opcije prostornih upita.

  - `:limit` — najviše rezultata (zadano #{@default_limit})
  - `:dog_status` — popis statusa, npr. `[:designated, :allowed]`
  - `:surface` — popis podloga
  - `:amenities` — popis obaveznih sadržaja, npr. `[:water, :shade]`
  - `:within_m` — ograniči na radijus u metrima
  - `:reachable_from` — otok (ili `nil` za kopno) do kojeg se mora doći bez
    trajekta; izostavlja plaže preko mora
  """
  @type query_opts :: keyword()

  @doc "Radijusi koje sučelje nudi, u metrima."
  def radii_m, do: @radii_m

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

  ## Admin
  #
  # Funkcije za admin sučelje primaju `Scope` s prijavljenim adminom kao prvi
  # argument. Bez njega poziv pada na `FunctionClauseError`, pa autorizacija ne
  # ovisi samo o tome je li ruta u routeru na pravom mjestu.

  @admin_per_page 25

  @doc """
  Stranica plaža za admin popis, po imenu.

  Opcije: `:query` (dio imena ili općine, ili točan `osm_id`) i `:page`
  (od 1). Vraća `%{entries: [...], page: n, total_pages: n, total: n}`.
  """
  def list_beaches_for_admin(%Scope{admin: %Admin{}}, opts \\ []) do
    query = admin_search(Beach, Keyword.get(opts, :query))
    total = Repo.aggregate(query, :count)
    total_pages = max(ceil(total / @admin_per_page), 1)
    page = opts |> Keyword.get(:page, 1) |> max(1) |> min(total_pages)

    entries =
      Repo.all(
        from b in query,
          order_by: [asc_nulls_last: b.name, asc: b.id],
          limit: @admin_per_page,
          offset: ^((page - 1) * @admin_per_page)
      )

    %{entries: entries, page: page, total_pages: total_pages, total: total}
  end

  defp admin_search(query, term) when is_binary(term) do
    case String.trim(term) do
      "" ->
        query

      term ->
        pattern = "%" <> escape_like(term) <> "%"

        where(
          query,
          [b],
          ilike(b.name, ^pattern) or ilike(b.municipality, ^pattern) or b.osm_id == ^term
        )
    end
  end

  defp admin_search(query, _term), do: query

  defp escape_like(term), do: String.replace(term, ["\\", "%", "_"], &("\\" <> &1))

  @doc "Changeset za admin formu, s koordinatama popunjenima iz `geom`."
  def change_beach_as_admin(%Beach{} = beach, attrs \\ %{}) do
    Beach.admin_changeset(beach, attrs)
  end

  @doc """
  Ručno dodaje plažu.

  Dobiva `osm_id` oblika `manual/…`, koji se ne može sudariti s OSM-om, pa je
  uvoz nikad ne dira. Izvor statusa je `:manual`.
  """
  def create_beach_as_admin(%Scope{admin: %Admin{}}, attrs) do
    osm_id = "manual/" <> Base.url_encode64(:crypto.strong_rand_bytes(9))

    %Beach{osm_id: osm_id, dog_status_source: :manual}
    |> Beach.admin_changeset(attrs)
    |> assign_island()
    |> Repo.insert()
  end

  @doc """
  Ručno ispravlja plažu. Nakon toga je uvoz više ne mijenja (ADR 0011).
  """
  def update_beach_as_admin(%Scope{admin: %Admin{}}, %Beach{} = beach, attrs) do
    beach
    |> Beach.admin_changeset(attrs)
    |> assign_island()
    |> Repo.update()
  end

  @doc """
  Briše plažu.

  Plaža iz OSM-a vratit će se pri sljedećem uvozu, jer je OSM izvor istine
  za postojanje plaže. Trajno se miče ispravkom u OSM-u.
  """
  def delete_beach(%Scope{admin: %Admin{}}, %Beach{} = beach), do: Repo.delete(beach)

  # Pomaknuta plaža može prijeći s otoka na kopno ili obratno, a o otoku ovisi
  # upozorenje "preko mora". Uvoz otoka to radi za sve plaže odjednom, ovdje
  # samo za jednu.
  defp assign_island(changeset) do
    case Ecto.Changeset.fetch_change(changeset, :geom) do
      {:ok, point} when changeset.valid? ->
        island = Islands.at(point)
        Ecto.Changeset.put_change(changeset, :island_id, island && island.id)

      _ ->
        changeset
    end
  end

  @doc """
  Označava svakoj plaži je li preko mora u odnosu na zadano polazište.

  Popunjava virtualno polje `across_sea`. Otoci se dohvaćaju jednim upitom za
  cijeli popis, ne po plaži.
  """
  @spec mark_across_sea([Beach.t()], Island.t() | nil) :: [Beach.t()]
  def mark_across_sea(beaches, from) do
    islands = islands_by_id(beaches)

    Enum.map(beaches, fn beach ->
      %{beach | across_sea: Islands.across_sea?(from, islands[beach.island_id])}
    end)
  end

  defp islands_by_id(beaches) do
    ids = beaches |> Enum.map(& &1.island_id) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    if ids == [] do
      %{}
    else
      Island
      |> where([i], i.id in ^ids)
      |> Repo.all()
      |> Map.new(&{&1.id, &1})
    end
  end

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
    Dogo.Telemetry.spatial_query(:nearest, fn -> do_nearest(point, opts) end)
  end

  defp do_nearest(point, opts) do
    Beach
    |> with_distance(point)
    |> apply_filters(opts)
    |> apply_radius(point, Keyword.get(opts, :within_m))
    |> apply_reachability(opts)
    |> order_by(
      [b],
      fragment("?::geography <-> ?::geography", type(^point, Geo.PostGIS.Geometry), b.geom)
    )
    |> limit(^Keyword.get(opts, :limit, @default_limit))
    |> Repo.all(repo_opts(opts))
  end

  defp repo_opts(opts), do: Keyword.take(opts, [:log])

  @doc """
  Plaže unutar vidljivog dijela karte.

  `bbox` je `{min_lon, min_lat, max_lon, max_lat}`. Koristi `ST_MakeEnvelope`
  i operator `&&`, koji ide preko GiST indeksa nad `geometry`.

  Vraća `{:ok, beaches}` ili `{:too_many, beaches}` kad rezultata ima više od
  `bbox_limit/0` — tada sučelje traži veći zoom ili klasteriranje (E3-S3).

  Uz opciju `:near` (točka) rezultat dobiva `distance_m` i poredan je po
  udaljenosti od te točke. Bez nje bbox nema referentnu točku, pa se vraća
  poredan po `id`.

  Opcija `:within_m` reže rezultat na radijus oko `:near`. Bez `:near` se
  ignorira — nema od čega mjeriti.

  Opcija `log: false` gasi Ecto log za taj upit. Koristi se kad je `:near`
  korisnikova lokacija: Ecto inače ispiše parametre upita, pa bi koordinate
  završile u logu (E4-S1).
  """
  @spec within_bbox({float(), float(), float(), float()}, query_opts()) ::
          {:ok, [Beach.t()]} | {:too_many, [Beach.t()]}
  def within_bbox(bbox, opts \\ []) do
    Dogo.Telemetry.spatial_query(:within_bbox, fn -> do_within_bbox(bbox, opts) end)
  end

  defp do_within_bbox({min_lon, min_lat, max_lon, max_lat}, opts) do
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
      |> apply_radius(Keyword.get(opts, :near), Keyword.get(opts, :within_m))
      |> apply_reachability(opts)
      |> order_from(Keyword.get(opts, :near))
      |> limit(^(limit + 1))
      |> Repo.all(repo_opts(opts))

    if length(beaches) > limit do
      {:too_many, Enum.take(beaches, limit)}
    else
      {:ok, beaches}
    end
  end

  @doc """
  Sažetak plaža u pravokutniku: mreža ćelija s brojem plaža u svakoj.

  Koristi se kad pojedinačnih plaža ima previše za slanje klijentu. Cijeli
  Jadran je 3107 plaža, odnosno oko 900 KB GeoJSON-a po svakom pomaku karte —
  a broj u klasteru mora biti točan, pa se skup ne smije samo odrezati.
  `ST_SnapToGrid` grupiranje vraća nekoliko desetaka ćelija i točne brojeve.

  Veličina ćelije se izvodi iz širine karte u pikselima (`:width_px`), pa su
  klasteri jednako gusti na svakom ekranu. Bez nje se koristi zadani broj
  stupaca.
  """
  @spec cluster_in_bbox({float(), float(), float(), float()}, query_opts()) :: [
          %{lon: float(), lat: float(), count: pos_integer()}
        ]
  def cluster_in_bbox(bbox, opts \\ []) do
    Dogo.Telemetry.spatial_query(:cluster_in_bbox, fn -> do_cluster_in_bbox(bbox, opts) end)
  end

  defp do_cluster_in_bbox({min_lon, min_lat, max_lon, max_lat}, opts) do
    cell = max((max_lon - min_lon) / columns(opts), 0.0001)

    query =
      from b in Beach,
        where:
          fragment(
            "? && ST_MakeEnvelope(?, ?, ?, ?, 4326)",
            b.geom,
            ^min_lon,
            ^min_lat,
            ^max_lon,
            ^max_lat
          ),
        group_by: fragment("ST_SnapToGrid(?, ?)", b.geom, ^cell),
        select: %{
          lon: fragment("ST_X(ST_Centroid(ST_Collect(?)))", b.geom),
          lat: fragment("ST_Y(ST_Centroid(ST_Collect(?)))", b.geom),
          count: count(b.id)
        }

    query
    |> apply_filters(opts)
    |> apply_radius(Keyword.get(opts, :near), Keyword.get(opts, :within_m))
    |> apply_reachability(opts)
    |> Repo.all(repo_opts(opts))
  end

  defp columns(opts) do
    case Keyword.get(opts, :columns) do
      columns when is_integer(columns) and columns > 0 ->
        columns

      _ ->
        case Keyword.get(opts, :width_px) do
          width when is_number(width) and width > 0 ->
            max(round(width / @cluster_cell_px), 4)

          _ ->
            @default_columns
        end
    end
  end

  @doc """
  Plaže unutar radijusa od točke, poredane po udaljenosti.

  Koristi `ST_DWithin` nad `geography`, pa je radijus u metrima i stvaran.
  """
  @spec within_radius(Geo.Point.t(), number(), query_opts()) :: [Beach.t()]
  def within_radius(%Geo.Point{} = point, radius_m, opts \\ []) do
    point
    |> nearest(Keyword.put(opts, :within_m, radius_m))
  end

  defp order_from(query, nil), do: order_by(query, [b], b.id)

  defp order_from(query, %Geo.Point{} = point) do
    query
    |> with_distance(point)
    |> order_by(
      [b],
      fragment("?::geography <-> ?::geography", type(^point, Geo.PostGIS.Geometry), b.geom)
    )
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

  defp apply_radius(query, _point, nil), do: query

  # Bez referentne tocke radijus nema od cega mjeriti, pa se ignorira.
  defp apply_radius(query, nil, _radius_m), do: query

  defp apply_radius(query, point, radius_m) do
    where(
      query,
      [b],
      fragment(
        "ST_DWithin(?::geography, ?::geography, ?)",
        b.geom,
        type(^point, Geo.PostGIS.Geometry),
        ^radius_m
      )
    )
  end

  # Filtar "bez trajekta". Ako je polaziste spojeno cestom (kopno ili otok s
  # mostom), dostupno je sve sto je takoder spojeno cestom. Ako je polaziste
  # otok bez mosta, dostupan je samo taj otok.
  defp apply_reachability(query, opts) do
    if Keyword.has_key?(opts, :reachable_from) do
      reachable_from(query, Keyword.fetch!(opts, :reachable_from))
    else
      query
    end
  end

  defp reachable_from(query, %Island{bridge_connected: false, id: id}) do
    where(query, [b], b.island_id == ^id)
  end

  defp reachable_from(query, _road_connected) do
    from b in query,
      left_join: i in Island,
      on: i.id == b.island_id,
      where: is_nil(b.island_id) or i.bridge_connected
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
