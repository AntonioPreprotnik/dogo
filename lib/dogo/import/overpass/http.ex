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

  @impl Dogo.Import.Overpass
  def fetch_beaches(opts \\ []) do
    query = build_query(opts)

    [
      method: :post,
      url: endpoint(),
      form: [data: query],
      headers: [{"user-agent", user_agent()}],
      receive_timeout: :timer.seconds(@default_query_timeout + 30),
      retry: :transient,
      max_retries: @max_retries,
      retry_delay: &retry_delay/1,
      retry_log_level: :warning
    ]
    |> Keyword.merge(Application.get_env(:dogo, :overpass_req_options, []))
    |> Req.request()
    |> handle_response()
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
    Parser.parse(body)
  end

  defp handle_response({:ok, %Req.Response{status: 200, body: body}}) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> Parser.parse(decoded)
      {:error, error} -> {:error, {:invalid_json, error}}
    end
  end

  defp handle_response({:ok, %Req.Response{status: status}}) do
    Logger.warning("Overpass je vratio HTTP #{status}")
    {:error, {:http_error, status}}
  end

  defp handle_response({:error, exception}), do: {:error, exception}

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
