defmodule Dogo.Geo.Routing.OSRM do
  @moduledoc """
  Rutiranje preko javnog OSRM demo servera.

  Tri stvari koje ovaj klijent radi namjerno:

  1. **Jedan zahtjev za sva odredišta** — `table` servis s `sources=0`. Deset
     zasebnih `route` poziva bi bilo deset puta sporije i deset puta grublje
     prema besplatnom servisu.
  2. **Zaokruživanje koordinata na tri decimale (~110 m)** prije slanja. To
     istovremeno podiže pogodak u cacheu i smanjuje preciznost korisnikove
     lokacije koja odlazi trećoj strani. Na skali "koliko mi treba do plaže"
     stotinu metara ionako ne mijenja odgovor.
  3. **Kratak timeout i bez ponavljanja.** Ovo je dodatna informacija, ne
     osnovna funkcija; korisnik ne smije čekati na nju.
  """
  @behaviour Dogo.Geo.Routing

  require Logger

  alias Dogo.Geo.RouteCache

  @default_endpoint "https://router.project-osrm.org/table/v1/driving/"
  @timeout_ms 2_000
  @precision 3

  @impl Dogo.Geo.Routing
  def table(origin, destinations) do
    origin = round_point(origin)
    destinations = Enum.map(destinations, &round_point/1)
    key = {origin, destinations}

    case RouteCache.fetch(key) do
      {:ok, legs} ->
        {:ok, legs}

      :miss ->
        with {:ok, legs} <- request(origin, destinations) do
          RouteCache.put(key, legs)
          {:ok, legs}
        end
    end
  end

  defp request(origin, destinations) do
    coordinates =
      Enum.map_join([origin | destinations], ";", fn {lon, lat} -> "#{lon},#{lat}" end)

    [
      url: endpoint() <> coordinates,
      params: [sources: 0, annotations: "duration,distance"],
      headers: [{"user-agent", user_agent()}],
      receive_timeout: @timeout_ms,
      retry: false
    ]
    |> Keyword.merge(Application.get_env(:dogo, :osrm_req_options, []))
    |> Req.get()
    |> handle_response(length(destinations))
  end

  defp handle_response({:ok, %Req.Response{status: 200, body: body}}, count)
       when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> handle_response({:ok, %Req.Response{status: 200, body: decoded}}, count)
      _ -> {:error, :invalid_json}
    end
  end

  defp handle_response({:ok, %Req.Response{status: 200, body: %{"code" => "Ok"} = body}}, count) do
    durations = body |> Map.get("durations", [[]]) |> List.first() |> List.wrap()
    distances = body |> Map.get("distances", [[]]) |> List.first() |> List.wrap()

    # Prvi stupac je polaziste prema samom sebi; odredista slijede.
    legs =
      0..(count - 1)//1
      |> Enum.map(&leg(Enum.at(durations, &1 + 1), Enum.at(distances, &1 + 1)))

    {:ok, legs}
  end

  defp handle_response({:ok, %Req.Response{status: 200, body: %{"code" => code}}}, _count) do
    {:error, {:osrm_error, code}}
  end

  defp handle_response({:ok, %Req.Response{status: status}}, _count) do
    Logger.warning("OSRM je vratio HTTP #{status}")
    {:error, {:http_error, status}}
  end

  defp handle_response({:error, exception}, _count), do: {:error, exception}

  defp leg(duration, distance) when is_number(duration) and is_number(distance) do
    %{duration_s: duration / 1, distance_m: distance / 1}
  end

  defp leg(_duration, _distance), do: nil

  defp round_point(%Geo.Point{coordinates: {lon, lat}}) do
    {Float.round(lon / 1, @precision), Float.round(lat / 1, @precision)}
  end

  defp endpoint, do: Application.get_env(:dogo, :osrm_endpoint, @default_endpoint)

  defp user_agent do
    Application.get_env(
      :dogo,
      :osrm_user_agent,
      "dogo/0.1 (portfolio projekt; https://github.com/dogo)"
    )
  end
end
