defmodule Dogo.Import.Overpass.HTTP do
  @moduledoc """
  Stvarni Overpass klijent.

  Overpass je besplatan javni servis pod stalnim opterećenjem: uz 429 zna
  vratiti i 504 kad mu je dispatcher zauzet. Zato ide retry s eksponencijalnim
  backoffom, a svaki zahtjev nosi User-Agent s kontaktom, kako traži usage
  policy.
  """
  @behaviour Dogo.Import.Overpass

  require Logger

  alias Dogo.Import.Overpass.Parser

  @default_endpoint "https://overpass-api.de/api/interpreter"
  @default_query_timeout 180
  @max_retries 5
  @default_min_island_area_km2 1.0
  @default_island_batch_size 8

  # Pauza izmedu serija geometrije. Overpass ima ograničen broj paralelnih
  # slotova i na niz teških upita odgovori s 429; retry to preživi, ali je
  # pristojnije ne izazivati ga.
  @default_batch_pause_ms 2_000

  @impl Dogo.Import.Overpass
  def fetch_beaches(opts \\ []) do
    query = build_query(opts)

    query
    |> run()
    |> case do
      {:ok, body} -> Parser.parse(body)
      {:error, reason} -> {:error, reason}
    end
  end

  # Jedan Overpass zahtjev. Vraca dekodirano tijelo; parsiranje je na
  # pozivatelju, jer plaze i otoci imaju razlicite oblike odgovora.
  defp run(query) when is_binary(query) do
    run(
      method: :post,
      url: endpoint(),
      form: [data: query],
      headers: [{"user-agent", user_agent()}],
      receive_timeout: :timer.seconds(@default_query_timeout + 30),
      retry: :transient,
      max_retries: @max_retries,
      retry_delay: &retry_delay/1,
      retry_log_level: :warning
    )
  end

  defp run(options) when is_list(options) do
    options
    |> Keyword.merge(Application.get_env(:dogo, :overpass_req_options, []))
    |> Req.request()
    |> handle_response()
  end

  @doc """
  Dohvaća otoke u dvije faze.

  Geometrija svih 181 hrvatskog otoka u jednom zahtjevu su deseci megabajta i
  Overpass na tome odustane. Zato prvo `out bb tags` (75 KB za sve), pa se po
  površini bounding boxa odabere što je vrijedno dohvatiti, i tek onda
  `out geom` u serijama.
  """
  @impl Dogo.Import.Overpass
  def fetch_islands(opts \\ []) do
    min_area_km2 = Keyword.get(opts, :min_area_km2, @default_min_island_area_km2)
    batch_size = Keyword.get(opts, :batch_size, @default_island_batch_size)

    with {:ok, body} <- run(island_bounds_query()),
         {:ok, candidates} <- Parser.parse_island_bounds(body) do
      candidates
      |> Enum.filter(&(bbox_area_km2(&1.bounds) >= min_area_km2))
      |> Enum.chunk_every(batch_size)
      |> fetch_island_batches(Keyword.get(opts, :batch_pause_ms, @default_batch_pause_ms))
    end
  end

  defp fetch_island_batches(batches, pause_ms) do
    batches
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {batch, index}, {:ok, acc} ->
      if index > 0 and pause_ms > 0, do: Process.sleep(pause_ms)

      case fetch_island_batch(batch) do
        {:ok, islands} -> {:cont, {:ok, acc ++ islands}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp fetch_island_batch(batch) do
    with {:ok, body} <- run(island_geometry_query(batch)) do
      Parser.parse_islands(body)
    end
  end

  @doc """
  Površina bounding boxa u kvadratnim kilometrima.

  Gruba mjera, dovoljna da se odvoji otok od hridi. Stvarna površina se računa
  u bazi, nakon što je poligon sastavljen.
  """
  def bbox_area_km2(%{"minlat" => min_lat, "maxlat" => max_lat} = bounds) do
    %{"minlon" => min_lon, "maxlon" => max_lon} = bounds

    mean_lat = (min_lat + max_lat) / 2
    height = (max_lat - min_lat) * 111.32
    width = (max_lon - min_lon) * 111.32 * :math.cos(mean_lat * :math.pi() / 180)

    height * width
  end

  @doc """
  Overpass QL upit za plaže. Izdvojeno radi čitljivosti i testiranja.
  """
  def build_query(opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_query_timeout)

    {scope_prefix, selector} =
      case Keyword.get(opts, :bbox) do
        nil ->
          {~s(area["ISO3166-1"="HR"][admin_level=2]->.searchArea;), "(area.searchArea)"}

        {min_lat, min_lon, max_lat, max_lon} ->
          {"", "(#{min_lat},#{min_lon},#{max_lat},#{max_lon})"}
      end

    """
    [out:json][timeout:#{timeout}];
    #{scope_prefix}
    (
      nwr["natural"="beach"]#{selector};
      nwr["leisure"="beach_resort"]#{selector};
    );
    out center tags;
    """
  end

  defp handle_response({:ok, %Req.Response{status: 200, body: body}}) when is_map(body) do
    {:ok, body}
  end

  defp handle_response({:ok, %Req.Response{status: 200, body: body}}) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, error} -> {:error, {:invalid_json, error}}
    end
  end

  defp handle_response({:ok, %Req.Response{status: status}}) do
    Logger.warning("Overpass je vratio HTTP #{status}")
    {:error, {:http_error, status}}
  end

  defp handle_response({:error, exception}), do: {:error, exception}

  defp island_bounds_query do
    """
    [out:json][timeout:#{@default_query_timeout}];
    area["ISO3166-1"="HR"][admin_level=2]->.searchArea;
    (
      way["place"="island"](area.searchArea);
      relation["place"="island"](area.searchArea);
    );
    out bb tags;
    """
  end

  defp island_geometry_query(candidates) do
    ways = ids_of(candidates, "way")
    relations = ids_of(candidates, "relation")

    """
    [out:json][timeout:#{@default_query_timeout}];
    (
    #{if ways == "", do: "", else: "  way(id:#{ways});"}
    #{if relations == "", do: "", else: "  relation(id:#{relations});"}
    );
    out geom;
    """
  end

  defp ids_of(candidates, type) do
    candidates
    |> Enum.filter(&(&1.type == type))
    |> Enum.map_join(",", &to_string(&1.id))
  end

  @doc """
  Eksponencijalni backoff: 1s, 2s, 4s, 8s, 16s.

  Dovoljno da preživi kratki nalet opterećenja na Overpassu, a da uvoz ne visi
  predugo. Javno radi testiranja.
  """
  @spec retry_delay(non_neg_integer()) :: pos_integer()
  def retry_delay(attempt), do: :timer.seconds(Bitwise.bsl(1, attempt))

  defp endpoint, do: Application.get_env(:dogo, :overpass_endpoint, @default_endpoint)

  defp user_agent do
    Application.get_env(
      :dogo,
      :overpass_user_agent,
      "dogo/0.1 (portfolio projekt; https://github.com/dogo)"
    )
  end
end
