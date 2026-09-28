defmodule Dogo.BeachesFixtures do
  @moduledoc """
  Pomoćne funkcije za stvaranje plaža u testovima.
  """

  alias Dogo.Beaches

  @doc "Točka u Bačvicama, Split — koristi se kao zadana lokacija plaže."
  def point(lon \\ 16.4402, lat \\ 43.5041), do: %Geo.Point{coordinates: {lon, lat}, srid: 4326}

  def valid_attrs(attrs \\ %{}) do
    Enum.into(attrs, %{
      osm_id: "way/#{System.unique_integer([:positive])}",
      name: "Bačvice",
      geom: point(),
      surface: :sand,
      dog_status: :allowed,
      dog_status_source: :osm,
      amenities: %{"water" => true, "shade" => false},
      municipality: "Split"
    })
  end

  def beach_fixture(attrs \\ %{}) do
    {:ok, beach} = attrs |> valid_attrs() |> Beaches.create_beach()
    beach
  end
end
