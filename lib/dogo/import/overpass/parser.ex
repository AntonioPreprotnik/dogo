defmodule Dogo.Import.Overpass.Parser do
  @moduledoc """
  Pretvara dekodirani Overpass JSON u `Dogo.Import.Overpass.Element` strukture.

  Čista funkcija bez mreže i baze, pa se testira na snimljenom odgovoru.

  Podržava oba oblika izlaza: `out center` (samo centroid) i `out geom`
  (puna geometrija, iz koje se gradi poligon kad je linija zatvorena).
  """

  alias Dogo.Import.Overpass.Element

  @srid 4326

  @doc """
  Vraća `{:ok, elements}` ili `{:error, reason}`.

  Elementi bez upotrebljivih koordinata se preskaču — Overpass zna vratiti
  relacije bez centra kad podaci u OSM-u nisu potpuni.
  """
  @spec parse(map()) :: {:ok, [Element.t()]} | {:error, term()}
  def parse(%{"remark" => remark}) when is_binary(remark),
    do: {:error, {:overpass_remark, remark}}

  def parse(%{"elements" => elements}) when is_list(elements) do
    {:ok, Enum.flat_map(elements, &List.wrap(parse_element(&1)))}
  end

  def parse(_other), do: {:error, :unexpected_payload}

  @doc """
  Vraća `Element` ili `nil` ako element nema koordinate.
  """
  @spec parse_element(map()) :: Element.t() | nil
  def parse_element(%{"type" => type, "id" => id} = element) do
    case centroid(element) do
      nil ->
        nil

      point ->
        tags = Map.get(element, "tags", %{})

        %Element{
          osm_id: "#{type}/#{id}",
          name: tags["name"],
          centroid: point,
          area: area(element),
          tags: tags
        }
    end
  end

  def parse_element(_), do: nil

  defp centroid(%{"lat" => lat, "lon" => lon}), do: point(lon, lat)
  defp centroid(%{"center" => %{"lat" => lat, "lon" => lon}}), do: point(lon, lat)

  defp centroid(%{"geometry" => geometry}) when is_list(geometry) and geometry != [] do
    coordinates = ring(geometry)
    count = length(coordinates)

    {sum_lon, sum_lat} =
      Enum.reduce(coordinates, {0.0, 0.0}, fn {lon, lat}, {lons, lats} ->
        {lons + lon, lats + lat}
      end)

    point(sum_lon / count, sum_lat / count)
  end

  defp centroid(_), do: nil

  # Poligon gradimo samo iz zatvorene linije. Relacije (multipoligoni s
  # rupama) preskačemo: `area` je nullable i koristi se samo za prikaz.
  defp area(%{"geometry" => geometry}) when is_list(geometry) do
    coordinates = ring(geometry)

    if closed?(coordinates) and length(coordinates) >= 4 do
      %Geo.MultiPolygon{coordinates: [[coordinates]], srid: @srid}
    end
  end

  defp area(_), do: nil

  defp ring(geometry) do
    for %{"lat" => lat, "lon" => lon} <- geometry, do: {lon, lat}
  end

  defp closed?([first | _] = coordinates), do: List.last(coordinates) == first
  defp closed?(_), do: false

  defp point(lon, lat), do: %Geo.Point{coordinates: {lon, lat}, srid: @srid}
end
