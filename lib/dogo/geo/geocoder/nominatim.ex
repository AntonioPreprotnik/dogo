defmodule Dogo.Geo.Geocoder.Nominatim do
  @moduledoc """
  Geokodiranje preko Nominatima.

  Nominatim je besplatan servis s izričitom usage policyjem. Poštujemo je na
  tri načina, i svaki je vidljiv u kodu:

  1. **Najviše 1 zahtjev u sekundi** — kroz `Dogo.Geo.RateLimiter`, globalno za
     cijeli čvor, ne po procesu.
  2. **Cache** — `Dogo.Geo.PlaceCache`; isti upit se ne pita dvaput.
  3. **User-Agent s kontaktom** — konfigurabilan, jer je adresa vezana uz
     instalaciju, ne uz kod.

  Pretraga je ograničena na Hrvatsku (`countrycodes=hr`).
  """
  @behaviour Dogo.Geo.Geocoder

  require Logger

  alias Dogo.Geo.Place
  alias Dogo.Geo.PlaceCache
  alias Dogo.Geo.RateLimiter

  @default_endpoint "https://nominatim.openstreetmap.org/search"
  @limit 5

  @impl Dogo.Geo.Geocoder
  def search(query) do
    key = cache_key(query)

    case PlaceCache.fetch(key) do
      {:ok, places} ->
        {:ok, places}

      :miss ->
        with :ok <- RateLimiter.acquire(),
             {:ok, places} <- request(query) do
          PlaceCache.put(key, places)
          {:ok, places}
        end
    end
  end

  defp request(query) do
    options =
      Keyword.merge(
        [
          url: endpoint(),
          params: [
            q: query,
            format: "jsonv2",
            countrycodes: "hr",
            limit: @limit,
            addressdetails: 1
          ],
          headers: [{"user-agent", user_agent()}],
          receive_timeout: :timer.seconds(5),
          retry: false
        ],
        Application.get_env(:dogo, :nominatim_req_options, [])
      )

    Dogo.Telemetry.external_request(:nominatim, fn ->
      options |> Req.get() |> handle_response()
    end)
  end

  defp handle_response({:ok, %Req.Response{status: 200, body: body}}) when is_list(body) do
    {:ok, Enum.flat_map(body, &List.wrap(to_place(&1)))}
  end

  defp handle_response({:ok, %Req.Response{status: 200, body: body}}) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} when is_list(decoded) ->
        handle_response({:ok, %Req.Response{status: 200, body: decoded}})

      _ ->
        {:error, :invalid_json}
    end
  end

  defp handle_response({:ok, %Req.Response{status: status}}) do
    Logger.warning("Nominatim je vratio HTTP #{status}")
    {:error, {:http_error, status}}
  end

  defp handle_response({:error, exception}), do: {:error, exception}

  defp to_place(%{"lat" => lat, "lon" => lon} = result) do
    with {latitude, _} <- Float.parse(to_string(lat)),
         {longitude, _} <- Float.parse(to_string(lon)) do
      %Place{
        name: result["name"] || primary_name(result["display_name"]),
        description: secondary_name(result["display_name"]),
        point: %Geo.Point{coordinates: {longitude, latitude}, srid: 4326}
      }
    else
      _ -> nil
    end
  end

  defp to_place(_result), do: nil

  # Nominatim vraca "Split, Splitsko-dalmatinska zupanija, Hrvatska".
  defp primary_name(nil), do: "Nepoznato mjesto"
  defp primary_name(display_name), do: display_name |> String.split(",") |> hd() |> String.trim()

  defp secondary_name(nil), do: nil

  defp secondary_name(display_name) do
    case String.split(display_name, ",", parts: 2) do
      [_first, rest] -> String.trim(rest)
      _ -> nil
    end
  end

  defp cache_key(query), do: query |> String.trim() |> String.downcase()

  defp endpoint, do: Application.get_env(:dogo, :nominatim_endpoint, @default_endpoint)

  defp user_agent do
    Application.get_env(
      :dogo,
      :nominatim_user_agent,
      "dogo/0.1 (portfolio projekt; https://github.com/dogo)"
    )
  end
end
