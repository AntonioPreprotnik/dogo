defmodule Dogo.Import.Overpass.ParserTest do
  use ExUnit.Case, async: true

  alias Dogo.Import.Overpass.Element
  alias Dogo.Import.Overpass.Parser
  alias Dogo.OverpassFixtures

  describe "parse/1 na snimljenom odgovoru" do
    setup do
      {:ok, elements} = Parser.parse(OverpassFixtures.decoded("beaches_split"))
      %{elements: elements, by_id: Map.new(elements, &{&1.osm_id, &1})}
    end

    test "preskače elemente bez koordinata", %{elements: elements} do
      # Fixture ima pet elemenata; peti je way bez centra i bez geometrije.
      assert length(elements) == 4
      refute Enum.any?(elements, &(&1.osm_id == "way/567891234"))
    end

    test "osm_id spaja tip i broj", %{by_id: by_id} do
      assert by_id |> Map.keys() |> Enum.sort() == [
               "node/1234567890",
               "relation/456789123",
               "way/234567891",
               "way/345678912"
             ]
    end

    test "node koristi vlastite lat/lon", %{by_id: by_id} do
      node = by_id["node/1234567890"]

      assert node.name == "Bačvice"
      assert node.centroid == %Geo.Point{coordinates: {16.4402, 43.5041}, srid: 4326}
      assert node.area == nil
    end

    test "way s 'out center' koristi center", %{by_id: by_id} do
      way = by_id["way/234567891"]

      assert way.centroid == %Geo.Point{coordinates: {16.4268, 43.5083}, srid: 4326}
    end

    test "zadržava tagove koje uvoz koristi", %{by_id: by_id} do
      assert by_id["way/234567891"].tags["dog"] == "leashed"
      assert by_id["way/234567891"].tags["surface"] == "pebble"
      assert by_id["way/345678912"].tags["leisure"] == "beach_resort"
      assert by_id["node/1234567890"].tags["addr:city"] == "Split"
    end

    test "plaža bez imena ima name: nil" do
      element = %{"type" => "node", "id" => 1, "lat" => 43.5, "lon" => 16.4}

      assert %Element{name: nil} = Parser.parse_element(element)
    end
  end

  describe "parse/1 na 'out geom' odgovoru" do
    setup do
      {:ok, elements} = Parser.parse(OverpassFixtures.decoded("beaches_geometry"))
      %{by_id: Map.new(elements, &{&1.osm_id, &1})}
    end

    test "zatvorena linija postaje MultiPolygon", %{by_id: by_id} do
      way = by_id["way/234567891"]

      assert %Geo.MultiPolygon{coordinates: [[ring]], srid: 4326} = way.area
      assert length(ring) == 5
      assert List.first(ring) == List.last(ring)
      assert {16.426, 43.508} in ring
    end

    test "otvorena linija ostaje bez poligona", %{by_id: by_id} do
      assert by_id["way/678912345"].area == nil
    end

    test "centroid se računa iz geometrije kad nema centra", %{by_id: by_id} do
      %Geo.Point{coordinates: {lon, lat}} = by_id["way/234567891"].centroid

      assert_in_delta lon, 16.4268, 0.001
      assert_in_delta lat, 43.5086, 0.001
    end
  end

  describe "parse/1 na stvarnom snimljenom odgovoru" do
    # Snimljeno s overpass-api.de 2026-09-28, bbox oko Splita. Rucno pisani
    # fixture pokriva rubne slucajeve, ovaj cuva stvarni oblik odgovora.
    setup do
      {:ok, elements} = Parser.parse(OverpassFixtures.decoded("beaches_split_real"))
      %{elements: elements}
    end

    test "svi elementi imaju osm_id i centroid u Hrvatskoj", %{elements: elements} do
      assert length(elements) == 8

      for element <- elements do
        assert element.osm_id =~ ~r{^(node|way|relation)/\d+$}
        assert %Geo.Point{srid: 4326} = element.centroid
        assert Dogo.Geo.within_croatia?(element.centroid)
      end
    end

    test "cita imena i tagove kakvi stvarno dolaze iz OSM-a", %{elements: elements} do
      names = elements |> Enum.map(& &1.name) |> Enum.reject(&is_nil/1)

      assert "Plaža Ježinac" in names
      assert "Žnjan" in names

      jezinac = Enum.find(elements, &(&1.name == "Plaža Ježinac"))
      assert jezinac.tags["surface"] == "pebblestone"
      assert jezinac.tags["natural"] == "beach"
    end

    test "plaze bez imena se ne odbacuju", %{elements: elements} do
      assert Enum.any?(elements, &is_nil(&1.name))
    end
  end

  describe "parse/1 na neispravnom odgovoru" do
    test "Overpass remark je greška, ne prazan rezultat" do
      body = %{"elements" => [], "remark" => "runtime error: Query timed out"}

      assert {:error, {:overpass_remark, "runtime error: Query timed out"}} = Parser.parse(body)
    end

    test "nepoznat oblik payloada" do
      assert {:error, :unexpected_payload} = Parser.parse(%{"foo" => "bar"})
    end

    test "prazan popis elemenata je uspjeh" do
      assert {:ok, []} = Parser.parse(%{"elements" => []})
    end
  end
end
