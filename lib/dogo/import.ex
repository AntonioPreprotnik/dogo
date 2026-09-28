defmodule Dogo.Import do
  @moduledoc """
  Uvoz plaža iz OpenStreetMapa u bazu.

  Uvoz je **idempotentan**: ključ je `osm_id`, a ponovno pokretanje radi upsert
  umjesto novih zapisa. To je nužno jer se OSM mijenja, a podatke želimo
  osvježavati bez brisanja tablice.
  """

  import Ecto.Query

  require Logger

  alias Dogo.Beaches.Beach
  alias Dogo.Import.Attributes
  alias Dogo.Import.Overpass
  alias Dogo.Repo

  @replaceable [
    :name,
    :geom,
    :area,
    :surface,
    :dog_status,
    :dog_status_source,
    :amenities,
    :municipality,
    :updated_at
  ]

  @chunk_size 500

  @typedoc "Brojači jednog uvoza."
  @type stats :: %{
          inserted: non_neg_integer(),
          updated: non_neg_integer(),
          skipped: non_neg_integer()
        }

  @doc """
  Dohvaća plaže s Overpassa i sprema ih u bazu.
  """
  @spec import_beaches(Overpass.opts()) :: {:ok, stats()} | {:error, term()}
  def import_beaches(opts \\ []) do
    with {:ok, elements} <- Overpass.fetch_beaches(opts) do
      {:ok, store(elements)}
    end
  end

  @doc """
  Sprema već dohvaćene elemente. Vraća brojače.

  Elementi koji ne prođu changeset (npr. točka izvan hrvatske obale) se
  preskaču — jedan pokvaren zapis ne smije srušiti cijeli uvoz.
  """
  @spec store([Overpass.Element.t()]) :: stats()
  def store(elements) do
    now = DateTime.utc_now(:second)
    {rows, skipped} = rows_and_skipped(elements, now)

    existing = existing_osm_ids(rows)
    inserted = Enum.count(rows, &(&1.osm_id not in existing))

    rows
    |> Enum.chunk_every(@chunk_size)
    |> Enum.each(fn chunk ->
      Repo.insert_all(Beach, chunk,
        on_conflict: {:replace, @replaceable},
        conflict_target: :osm_id
      )
    end)

    stats = %{inserted: inserted, updated: length(rows) - inserted, skipped: skipped}

    Logger.info(
      "Uvoz plaza: #{stats.inserted} dodano, #{stats.updated} azurirano, #{stats.skipped} preskoceno"
    )

    stats
  end

  defp rows_and_skipped(elements, now) do
    elements
    |> Enum.reduce({[], 0}, fn element, {rows, skipped} ->
      attrs = Attributes.build(element)

      case Beach.changeset(%Beach{}, attrs) do
        %{valid?: true} ->
          {[Map.merge(attrs, %{inserted_at: now, updated_at: now}) | rows], skipped}

        changeset ->
          Logger.debug("Preskacem #{element.osm_id}: #{inspect(changeset.errors)}")
          {rows, skipped + 1}
      end
    end)
    |> then(fn {rows, skipped} -> {dedupe(rows), skipped} end)
  end

  # Overpass zna vratiti isti objekt dvaput (npr. kad odgovara i na
  # natural=beach i na leisure=beach_resort). `insert_all` bi na duplikatu
  # unutar iste naredbe pukao, pa ih mičemo prije upisa.
  #
  # `rows` je u obrnutom redoslijedu (gradi se prependanjem), pa `uniq_by`
  # zadržava **zadnje** pojavljivanje — isto što bi dao niz upserta.
  defp dedupe(rows) do
    rows
    |> Enum.uniq_by(& &1.osm_id)
    |> Enum.reverse()
  end

  defp existing_osm_ids([]), do: []

  defp existing_osm_ids(rows) do
    osm_ids = Enum.map(rows, & &1.osm_id)

    Repo.all(from b in Beach, where: b.osm_id in ^osm_ids, select: b.osm_id)
  end
end
