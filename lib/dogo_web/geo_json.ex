defmodule DogoWeb.GeoJSON do
  @moduledoc """
  Pretvara plaže u GeoJSON koji karta razumije.

  Držimo se onoga što MapLibre stvarno treba: id, ime, status za pse i njegov
  izvor, te udaljenost kad je poznata. Cijeli zapis ne šaljemo — na malom zoomu
  to su stotine objekata po pomaku karte.
  """

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
        dog_status_source: beach.dog_status_source,
        surface: beach.surface,
        distance_m: beach.distance_m
      }
    }
  end
end
