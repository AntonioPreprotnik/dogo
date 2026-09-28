defmodule DogoWeb.GeoJSON do
  @moduledoc """
  Pretvara plaže u GeoJSON koji karta razumije.

  Šaljemo samo ono što karta stvarno treba: geometriju, identitet i već
  formatirane oznake za popup. Cijeli zapis ne ide — na malom zoomu to su
  stotine objekata po svakom pomaku karte.

  Oznake se formatiraju ovdje, a ne u JS-u, da prijevodi (E6) ostanu na jednom
  mjestu i da popup ne mora znati ništa o domeni.
  """

  import DogoWeb.BeachComponents,
    only: [dog_status_label: 1, marker_colors: 0, format_distance: 1]

  alias Dogo.Beaches.Beach

  @doc "FeatureCollection od popisa plaža."
  @spec feature_collection([Beach.t()]) :: map()
  def feature_collection(beaches) do
    %{type: "FeatureCollection", features: Enum.map(beaches, &feature/1)}
  end

  @doc "Jedna plaža kao GeoJSON Feature."
  @spec feature(Beach.t()) :: map()
  def feature(%Beach{geom: %Geo.Point{coordinates: {lon, lat}}} = beach) do
    %{
      type: "Feature",
      id: beach.id,
      geometry: %{type: "Point", coordinates: [lon, lat]},
      properties: %{
        id: beach.id,
        name: beach.name,
        dog_status: beach.dog_status,
        dog_status_label: dog_status_label(beach.dog_status),
        dog_status_source: beach.dog_status_source,
        surface: beach.surface,
        color: Map.fetch!(marker_colors(), beach.dog_status),
        distance_m: beach.distance_m,
        distance_label: format_distance(beach.distance_m)
      }
    }
  end

  @doc """
  Sažete ćelije kao GeoJSON.

  Svojstvo se zove `point_count` jer MapLibre tako zove broj u klasteru —
  isti stil onda radi i za klijentske i za serverske klastere.
  """
  @spec cluster_collection([%{lon: float(), lat: float(), count: pos_integer()}]) :: map()
  def cluster_collection(clusters) do
    %{
      type: "FeatureCollection",
      features: Enum.map(clusters, &cluster_feature/1)
    }
  end

  defp cluster_feature(%{lon: lon, lat: lat, count: count}) do
    %{
      type: "Feature",
      geometry: %{type: "Point", coordinates: [lon, lat]},
      properties: %{
        point_count: count,
        point_count_abbreviated: abbreviate(count)
      }
    }
  end

  # MapLibre sam skracuje brojeve u klijentskim klasterima; za serverske to
  # radimo ovdje, da oznake izgledaju isto.
  defp abbreviate(count) when count < 1_000, do: to_string(count)

  defp abbreviate(count) do
    :erlang.float_to_binary(count / 1_000, decimals: 1) <> "k"
  end

  @doc """
  Boje za MapLibre `match` izraz: ravna lista `status, boja, status, boja, ...`.

  MapLibre očekuje baš takav oblik, pa ga gradimo ovdje umjesto u JS-u — jedan
  izvor istine za boje statusa.
  """
  @spec marker_color_match() :: %{colors: [String.t()], fallbackColor: String.t()}
  def marker_color_match do
    colors = marker_colors()

    %{
      colors: Enum.flat_map(colors, fn {status, color} -> [to_string(status), color] end),
      fallbackColor: Map.fetch!(colors, :unknown)
    }
  end
end
