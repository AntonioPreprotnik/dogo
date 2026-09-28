defmodule DogoWeb.GeoJSONTest do
  @moduledoc "E3-S2: podaci koje karta treba za boju markera i popup."
  use Dogo.DataCase, async: true

  import Dogo.BeachesFixtures

  alias Dogo.Beaches.Beach
  alias DogoWeb.GeoJSON

  describe "feature/1" do
    test "koordinate idu u GeoJSON redoslijedu [lon, lat]" do
      beach = beach_fixture(%{geom: point(16.4402, 43.5041)})

      assert %{geometry: %{type: "Point", coordinates: [16.4402, 43.5041]}} =
               GeoJSON.feature(beach)
    end

    test "nosi boju koja odgovara statusu za pse" do
      for {status, color} <- DogoWeb.BeachComponents.marker_colors() do
        beach = beach_fixture(%{osm_id: "way/#{status}", dog_status: status})

        assert GeoJSON.feature(beach).properties.color == color
      end
    end

    test "nosi već formatiranu oznaku statusa, da JS ne mora znati domenu" do
      beach = beach_fixture(%{dog_status: :designated})

      assert GeoJSON.feature(beach).properties.dog_status_label == "Plaža za pse"
    end

    test "bez udaljenosti nema ni oznake udaljenosti" do
      beach = beach_fixture(%{})

      assert GeoJSON.feature(beach).properties.distance_label == nil
    end

    test "udaljenost se formatira u metrima ili kilometrima" do
      assert %Beach{} = beach = beach_fixture(%{})

      assert GeoJSON.feature(%{beach | distance_m: 640.4}).properties.distance_label == "640 m"
      assert GeoJSON.feature(%{beach | distance_m: 2450.0}).properties.distance_label == "2.5 km"
    end
  end

  describe "marker_color_match/0" do
    test "boje dolaze kao ravna lista koju MapLibre 'match' očekuje" do
      %{colors: colors, fallbackColor: fallback} = GeoJSON.marker_color_match()

      assert rem(length(colors), 2) == 0

      pairs = colors |> Enum.chunk_every(2) |> Map.new(fn [k, v] -> {k, v} end)

      assert pairs["designated"] == "#059669"
      assert pairs["not_allowed"] == "#e11d48"
      assert fallback == pairs["unknown"]
    end

    test "pokriva svaki status iz sheme, pa nijedna plaža ne ostane bez boje" do
      %{colors: colors} = GeoJSON.marker_color_match()
      statuses = colors |> Enum.take_every(2) |> Enum.sort()

      assert statuses == Beach.dog_statuses() |> Enum.map(&to_string/1) |> Enum.sort()
    end
  end

  describe "feature_collection/1" do
    test "prazan popis je i dalje ispravan FeatureCollection" do
      assert GeoJSON.feature_collection([]) == %{type: "FeatureCollection", features: []}
    end
  end
end
