defmodule Dogo.Import.Islands do
  @moduledoc """
  Uvoz poligona hrvatskih otoka i pridruživanje plaža otocima.

  Poligone **ne sastavljamo u Elixiru**. Relacija otoka u OSM-u je skup
  nepovezanih i neporedanih linija — Krk ih ima 72 — pa bi ih trebalo spajati u
  prstenove pazeći na redoslijed i smjer. `ST_Polygonize` to radi ispravno i u
  jednom pozivu, a rezultat je odmah u bazi.
  """

  import Ecto.Query

  require Logger

  alias Dogo.Beaches.Beach
  alias Dogo.Geo.Island
  alias Dogo.Import.Overpass
  alias Dogo.Repo

  # Koliko daleko od poligona plaža smije biti da se i dalje smatra njegovom.
  # Centroid plaže zna pasti koji metar u more, a kanali između otoka i kopna
  # su svugdje puno širi od ovoga.
  @snap_distance_m 150

  @typedoc "Brojači jednog uvoza otoka."
  @type stats :: %{
          inserted: non_neg_integer(),
          updated: non_neg_integer(),
          skipped: non_neg_integer(),
          beaches_assigned: non_neg_integer()
        }

  @doc "Dohvaća otoke s Overpassa, sprema ih i pridružuje im plaže."
  @spec import_islands(keyword()) :: {:ok, stats()} | {:error, term()}
  def import_islands(opts \\ []) do
    with {:ok, elements} <- Overpass.fetch_islands(opts) do
      {:ok, store(elements)}
    end
  end

  @doc """
  Sprema već dohvaćene otoke i pridružuje plaže. Vraća brojače.
  """
  @spec store([Overpass.IslandElement.t()]) :: stats()
  def store(elements) do
    existing = elements |> Enum.map(& &1.osm_id) |> existing_osm_ids() |> MapSet.new()

    counts =
      Enum.reduce(elements, %{inserted: 0, updated: 0, skipped: 0}, fn element, counts ->
        case upsert(element) do
          :skip -> Map.update!(counts, :skipped, &(&1 + 1))
          :ok -> Map.update!(counts, key_for(element, existing), &(&1 + 1))
        end
      end)

    stats = Map.put(counts, :beaches_assigned, assign_beaches())

    Logger.info(
      "Uvoz otoka: #{stats.inserted} dodano, #{stats.updated} azurirano, " <>
        "#{stats.skipped} preskoceno, #{stats.beaches_assigned} plaza pridruzeno"
    )

    stats
  end

  @doc """
  Pridružuje svakoj plaži otok na kojem leži i vraća broj pridruženih.

  Pokreće se iznova pri svakom uvozu, pa prvo briše stare veze — inače bi plaža
  koja je greškom bila pridružena zadržala vezu i nakon ispravka podataka.
  """
  @spec assign_beaches() :: non_neg_integer()
  def assign_beaches do
    Repo.update_all(Beach, set: [island_id: nil])

    %{num_rows: assigned} =
      Repo.query!(
        """
        UPDATE beaches AS b
        SET island_id = nearest.island_id
        FROM (
          SELECT b.id AS beach_id,
                 i.id AS island_id,
                 row_number() OVER (
                   PARTITION BY b.id
                   ORDER BY ST_Distance(b.geom::geography, i.geom::geography)
                 ) AS rank
          FROM beaches b
          JOIN islands i
            ON ST_DWithin(b.geom::geography, i.geom::geography, $1)
        ) AS nearest
        WHERE b.id = nearest.beach_id AND nearest.rank = 1
        """,
        [@snap_distance_m]
      )

    assigned
  end

  defp upsert(%{lines: []}), do: :skip

  defp upsert(element) do
    multiline = %Geo.MultiLineString{coordinates: element.lines, srid: 4326}

    # ST_UnaryUnion prije polygonize: cvorira linije na svim sjecistima. Bez
    # toga ST_Polygonize vrati prazno cim se dva segmenta negdje krizaju ili
    # dodiruju mimo krajnjih tocaka — a stvarni OSM podaci to rade.
    #
    # Ako ni tada nema poligona, linije stvarno ne zatvaraju prsten (nepotpuna
    # relacija). Takav otok preskacemo umjesto da spremimo prazan poligon koji
    # bi tiho iskljucio sve plaze na njemu.
    %{num_rows: rows} =
      Repo.query!(
        """
        WITH built AS (
          SELECT ST_Multi(
                   ST_CollectionExtract(
                     ST_Polygonize(ARRAY[ST_UnaryUnion($3::geometry)]), 3
                   )
                 ) AS geom
        )
        INSERT INTO islands (osm_id, name, geom, area_m2, inserted_at, updated_at)
        SELECT $1, $2, geom, ST_Area(geom::geography), now(), now()
        FROM built
        WHERE geom IS NOT NULL AND NOT ST_IsEmpty(geom)
        ON CONFLICT (osm_id) DO UPDATE
        SET name = EXCLUDED.name,
            geom = EXCLUDED.geom,
            area_m2 = EXCLUDED.area_m2,
            updated_at = EXCLUDED.updated_at
        """,
        [element.osm_id, element.name, multiline]
      )

    if rows == 0 do
      Logger.debug("Preskacem otok #{element.osm_id}: linije ne zatvaraju poligon")
      :skip
    else
      :ok
    end
  end

  defp key_for(element, existing) do
    if MapSet.member?(existing, element.osm_id), do: :updated, else: :inserted
  end

  defp existing_osm_ids([]), do: []

  defp existing_osm_ids(osm_ids) do
    Repo.all(from i in Island, where: i.osm_id in ^osm_ids, select: i.osm_id)
  end
end
