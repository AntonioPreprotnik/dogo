defmodule Dogo.BeachesFixtures do
  @moduledoc """
  Pomoćne funkcije za stvaranje plaža u testovima.

  `osm_id` se automatski veže uz proces testa. Bez toga dva async testa koja
  ubace istu vrijednost blokiraju se na unique indeksu, a u nesretnom
  redoslijedu i deadlockaju — Postgres drži lock do kraja transakcije, a
  sandbox transakciju drži do kraja testa.
  """

  alias Dogo.Beaches

  @doc "Točka u Bačvicama, Split — koristi se kao zadana lokacija plaže."
  def point(lon \\ 16.4402, lat \\ 43.5041), do: %Geo.Point{coordinates: {lon, lat}, srid: 4326}

  @doc """
  `osm_id` vezan uz proces koji ga traži.

  Testovi koji plažu traže po `osm_id`-u moraju proći kroz ovu funkciju:

      Beaches.get_beach_by_osm_id(osm_id("way/blizu"))
  """
  def osm_id(base \\ "way"), do: "#{base}@#{:erlang.pid_to_list(self())}"

  def valid_attrs(attrs \\ %{}) do
    attrs
    |> Enum.into(%{
      osm_id: osm_id("way/#{System.unique_integer([:positive])}"),
      name: "Bačvice",
      geom: point(),
      surface: :sand,
      dog_status: :allowed,
      dog_status_source: :osm,
      amenities: %{"water" => true, "shade" => false},
      municipality: "Split"
    })
    |> Map.update!(:osm_id, &scope/1)
  end

  def beach_fixture(attrs \\ %{}) do
    {:ok, beach} = attrs |> valid_attrs() |> Beaches.create_beach()
    beach
  end

  # Idempotentno: vec omeden osm_id se ne omeduje dvaput.
  defp scope(value) do
    if String.contains?(value, "@"), do: value, else: osm_id(value)
  end
end
