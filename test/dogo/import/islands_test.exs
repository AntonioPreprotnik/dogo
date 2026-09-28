defmodule Dogo.Import.IslandsTest do
  @moduledoc """
  E5-S1. Ključna provjera je da se poligon otoka sastavi iz nepovezanih
  segmenata relacije — Krk ih u OSM-u ima 72, nijedan zatvoren.
  """
  use Dogo.DataCase, async: true

  import Dogo.BeachesFixtures
  import Mox

  alias Dogo.Geo.Island
  alias Dogo.Import.Islands
  alias Dogo.Import.Overpass.IslandElement
  alias Dogo.Import.Overpass.Parser
  alias Dogo.OverpassFixtures
  alias Dogo.OverpassMock

  setup :verify_on_exit!

  # Kvadrat oko (16.0, 43.0), stranice 0.1 stupnja, zadan kao cetiri odvojena
  # segmenta — bas kako relacija otoka izgleda u OSM-u.
  defp square(osm_id, lon, lat, size \\ 0.1) do
    corners = [
      {lon, lat},
      {lon + size, lat},
      {lon + size, lat + size},
      {lon, lat + size},
      {lon, lat}
    ]

    lines = corners |> Enum.chunk_every(2, 1, :discard) |> Enum.map(&Enum.to_list/1)

    %IslandElement{osm_id: osm_id, name: "Otok #{osm_id}", lines: lines}
  end

  describe "store/1" do
    test "sastavlja poligon iz nepovezanih segmenata" do
      assert %{inserted: 1, skipped: 0} = Islands.store([square("way/1", 16.0, 43.0)])

      island = Repo.one(Island)

      assert %Geo.MultiPolygon{} = island.geom
      assert island.name == "Otok way/1"
      # 0.1 stupnja na 43. paraleli: oko 8.1 x 11.1 km.
      assert_in_delta island.area_m2 / 1_000_000, 90, 15
    end

    test "ponovni uvoz ne stvara duplikate" do
      element = square("way/1", 16.0, 43.0)

      assert %{inserted: 1, updated: 0} = Islands.store([element])
      assert %{inserted: 0, updated: 1} = Islands.store([element])

      assert Repo.aggregate(Island, :count) == 1
    end

    test "preskace otok cije linije ne zatvaraju prsten" do
      broken = %IslandElement{
        osm_id: "way/9",
        name: "Slomljen",
        lines: [[{16.0, 43.0}, {16.1, 43.0}]]
      }

      assert %{inserted: 0, skipped: 1} = Islands.store([broken])
      assert Repo.aggregate(Island, :count) == 0
    end

    test "preskace otok bez linija" do
      assert %{skipped: 1} = Islands.store([%IslandElement{osm_id: "way/0", lines: []}])
    end

    test "prazan uvoz je uspjeh bez promjena" do
      assert %{inserted: 0, updated: 0, skipped: 0} = Islands.store([])
    end
  end

  describe "stvarni podaci iz OSM-a" do
    test "Krk se sastavi iz 72 segmenta relacije" do
      {:ok, [element]} = Parser.parse_islands(OverpassFixtures.decoded("island_krk"))

      assert element.osm_id == "relation/1924210"
      assert element.name == "Krk"
      assert length(element.lines) == 72

      # Gotovo nijedan segment nije zatvoren sam po sebi (jedan jest, mali
      # otocic uz obalu), pa se prsten mora sastaviti iz vise njih.
      open = Enum.count(element.lines, &(List.first(&1) != List.last(&1)))
      assert open == 71

      assert %{inserted: 1, skipped: 0} = Islands.store([element])

      krk = Repo.one(Island)
      assert %Geo.MultiPolygon{} = krk.geom
      # Stvarna povrsina Krka je 405,8 km2; fixture je prorijeden, pa dopustamo
      # odstupanje, ali red velicine mora biti tocan.
      assert_in_delta krk.area_m2 / 1_000_000, 405, 25
    end
  end

  describe "assign_beaches/0" do
    setup do
      Islands.store([square("way/otok", 16.0, 43.0)])
      :ok
    end

    test "plaza na otoku dobije island_id" do
      beach = beach_fixture(%{osm_id: "way/na-otoku", geom: point(16.05, 43.05)})

      assert Islands.assign_beaches() == 1
      assert Repo.reload!(beach).island_id == Repo.one(Island).id
    end

    test "plaza na kopnu ostaje bez otoka" do
      beach = beach_fixture(%{osm_id: "way/kopno", geom: point(16.44, 43.50)})

      Islands.assign_beaches()

      assert Repo.reload!(beach).island_id == nil
    end

    test "plaza malo izvan obale se i dalje racuna otoku" do
      # Centroid plaze zna pasti koji metar u more.
      beach = beach_fixture(%{osm_id: "way/uz-obalu", geom: point(16.0 - 0.0008, 43.05)})

      Islands.assign_beaches()

      refute is_nil(Repo.reload!(beach).island_id)
    end

    test "plaza preko kanala ne pripada otoku" do
      beach = beach_fixture(%{osm_id: "way/preko", geom: point(16.0 - 0.01, 43.05)})

      Islands.assign_beaches()

      assert Repo.reload!(beach).island_id == nil
    end

    test "ponovno pokretanje brise zastarjele veze" do
      beach = beach_fixture(%{osm_id: "way/na-otoku", geom: point(16.05, 43.05)})
      Islands.assign_beaches()
      refute is_nil(Repo.reload!(beach).island_id)

      Repo.delete_all(Island)

      assert Islands.assign_beaches() == 0
      assert Repo.reload!(beach).island_id == nil
    end

    test "plaza pripada najblizem otoku kad su dva blizu" do
      Islands.store([square("way/drugi", 16.2, 43.0)])

      beach = beach_fixture(%{osm_id: "way/blizu-prvog", geom: point(16.05, 43.05)})

      Islands.assign_beaches()

      prvi = Repo.get_by!(Island, osm_id: "way/otok")
      assert Repo.reload!(beach).island_id == prvi.id
    end
  end

  describe "import_islands/1" do
    test "prosljeduje opcije klijentu i sprema rezultat" do
      expect(OverpassMock, :fetch_islands, fn opts ->
        assert opts[:min_area_km2] == 5.0
        {:ok, [square("way/1", 16.0, 43.0)]}
      end)

      assert {:ok, %{inserted: 1}} = Islands.import_islands(min_area_km2: 5.0)
    end

    test "greska klijenta se propagira i nista se ne sprema" do
      expect(OverpassMock, :fetch_islands, fn _ -> {:error, {:http_error, 504}} end)

      assert {:error, {:http_error, 504}} = Islands.import_islands()
      assert Repo.aggregate(Island, :count) == 0
    end
  end
end
