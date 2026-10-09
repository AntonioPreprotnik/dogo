defmodule Dogo.Import do
  @moduledoc """
  Uvoz plaža iz OpenStreetMapa u bazu.

  Uvoz je **idempotentan**: ključ je `osm_id`, a ponovno pokretanje radi upsert
  umjesto novih zapisa. To je nužno jer se OSM mijenja, a podatke želimo
  osvježavati bez brisanja tablice.

  Plaže koje je admin ručno ispravio (`edited_at` postavljen) uvoz preskače:
  ručna ispravka je namjerna i ne smije nestati sa sljedećim uvozom (ADR 0011).
  """

  import Ecto.Query

  require Logger

  alias Dogo.Beaches.Beach
  alias Dogo.Import.Attributes
  alias Dogo.Import.Jobs.ImportBeaches
  alias Dogo.Import.Jobs.ImportIslands
  alias Dogo.Import.Overpass
  alias Dogo.Repo

  @chunk_size 500

  @typedoc """
  Brojači jednog uvoza. `kept` su ručno ispravljene plaže koje uvoz nije
  dirao.
  """
  @type stats :: %{
          inserted: non_neg_integer(),
          updated: non_neg_integer(),
          skipped: non_neg_integer(),
          kept: non_neg_integer()
        }

  @workers [ImportBeaches, ImportIslands]

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

    existing = existing_rows(rows)
    {kept, rows} = Enum.split_with(rows, &Map.get(existing, &1.osm_id, false))
    inserted = Enum.count(rows, &(not Map.has_key?(existing, &1.osm_id)))

    rows
    |> Enum.chunk_every(@chunk_size)
    |> Enum.each(fn chunk ->
      Repo.insert_all(Beach, chunk, on_conflict: upsert_unless_edited(), conflict_target: :osm_id)
    end)

    stats = %{
      inserted: inserted,
      updated: length(rows) - inserted,
      skipped: skipped,
      kept: length(kept)
    }

    Logger.info(
      "Uvoz plaza: #{stats.inserted} dodano, #{stats.updated} azurirano, " <>
        "#{stats.skipped} preskoceno, #{stats.kept} rucno ispravljenih zadrzano"
    )

    stats
  end

  # Ručno ispravljene plaže su već izbačene iz `rows`, ali admin može spremiti
  # izmjenu dok uvoz traje. Uvjet u samom upsertu pokriva i taj slučaj.
  # Javna samo radi testa tog slučaja.
  @doc false
  def upsert_unless_edited do
    from b in Beach,
      where: is_nil(b.edited_at),
      update: [
        set: [
          name: fragment("EXCLUDED.name"),
          geom: fragment("EXCLUDED.geom"),
          area: fragment("EXCLUDED.area"),
          surface: fragment("EXCLUDED.surface"),
          dog_status: fragment("EXCLUDED.dog_status"),
          dog_status_source: fragment("EXCLUDED.dog_status_source"),
          amenities: fragment("EXCLUDED.amenities"),
          municipality: fragment("EXCLUDED.municipality"),
          updated_at: fragment("EXCLUDED.updated_at")
        ]
      ]
  end

  @doc """
  Stavlja uvoz plaža u Oban red. Za admin sučelje i `mix beaches.import`.
  """
  @spec enqueue_beaches_import(map()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue_beaches_import(args \\ %{}), do: args |> ImportBeaches.new() |> Oban.insert()

  @doc """
  Stavlja uvoz otoka (i ponovno pridruživanje plaža otocima) u Oban red.
  """
  @spec enqueue_islands_import(map()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue_islands_import(args \\ %{}), do: args |> ImportIslands.new() |> Oban.insert()

  @doc "Zadnji uvozni jobovi, najnoviji prvi."
  @spec recent_jobs(pos_integer()) :: [Oban.Job.t()]
  def recent_jobs(limit \\ 10) do
    workers = Enum.map(@workers, &Oban.Worker.to_string/1)

    Repo.all(
      from j in Oban.Job,
        where: j.worker in ^workers,
        order_by: [desc: j.id],
        limit: ^limit
    )
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

  # osm_id => je li ručno ispravljena, za plaže koje su već u bazi.
  defp existing_rows([]), do: %{}

  defp existing_rows(rows) do
    osm_ids = Enum.map(rows, & &1.osm_id)

    from(b in Beach, where: b.osm_id in ^osm_ids, select: {b.osm_id, not is_nil(b.edited_at)})
    |> Repo.all()
    |> Map.new()
  end
end
