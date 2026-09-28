defmodule Dogo.Geo do
  @moduledoc """
  Geografske konstante i pomoćne funkcije zajedničke svim kontekstima.

  Ovaj modul namjerno **nije** aliasiran kao `Geo` nigdje u projektu, jer bi se
  sudario s `Geo` namespaceom biblioteke `geo` / `geo_postgis`. Zovi ga punim
  imenom: `Dogo.Geo.within_croatia?(point)`.
  """

  @srid 4326

  # Bounding box hrvatske obale i otoka: od Savudrije na sjeverozapadu do
  # Prevlake na jugoistoku, s rezervom prema unutrašnjosti jer neke plaže OSM
  # bilježi uz ušća rijeka.
  @min_lon 13.0
  @max_lon 19.7
  @min_lat 42.2
  @max_lat 45.7

  @doc "SRID koji projekt koristi svugdje (WGS 84)."
  def srid, do: @srid

  @doc """
  Bounding box hrvatske obale kao `{min_lon, min_lat, max_lon, max_lat}`.
  """
  def croatia_bbox, do: {@min_lon, @min_lat, @max_lon, @max_lat}

  @doc """
  Je li točka unutar bounding boxa hrvatske obale?

  Gruba provjera zdravog razuma nad uvezenim podacima, ne geografski točan test
  pripadnosti državi.
  """
  def within_croatia?(%Geo.Point{coordinates: {lon, lat}}) do
    lon >= @min_lon and lon <= @max_lon and lat >= @min_lat and lat <= @max_lat
  end

  def within_croatia?(_), do: false
end
