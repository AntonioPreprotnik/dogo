defmodule Dogo.ImportTest do
  use Dogo.DataCase, async: true

  import Mox

  alias Dogo.Beaches
  alias Dogo.Import
  alias Dogo.Import.Overpass.Element
  alias Dogo.OverpassMock

  setup :verify_on_exit!

  defp element(osm_id, overrides \\ %{}) do
    defaults = %Element{
      osm_id: osm_id,
      name: "Plaža #{osm_id}",
      centroid: %Geo.Point{coordinates: {16.44, 43.50}, srid: 4326},
      tags: %{}
    }

    struct!(defaults, overrides)
  end

  describe "store/1" do
    test "sprema nove plaže i broji ih" do
      assert %{inserted: 2, updated: 0, skipped: 0} =
               Import.store([element("way/1"), element("node/2")])

      assert Beaches.count_beaches() == 2
      assert %{name: "Plaža way/1"} = Beaches.get_beach_by_osm_id("way/1")
    end

    test "drugi prolaz ažurira, ne duplicira — uvoz je idempotentan" do
      elements = [element("way/1"), element("node/2")]

      assert %{inserted: 2, updated: 0} = Import.store(elements)
      assert %{inserted: 0, updated: 2, skipped: 0} = Import.store(elements)

      assert Beaches.count_beaches() == 2
    end

    test "ažurira promijenjene podatke iz OSM-a" do
      Import.store([element("way/1", %{name: "Staro ime"})])
      Import.store([element("way/1", %{name: "Novo ime"})])

      assert %{name: "Novo ime"} = Beaches.get_beach_by_osm_id("way/1")
      assert Beaches.count_beaches() == 1
    end

    test "ne mijenja inserted_at pri ažuriranju" do
      Import.store([element("way/1")])
      %{inserted_at: first} = Beaches.get_beach_by_osm_id("way/1")

      Import.store([element("way/1", %{name: "Drugo"})])
      %{inserted_at: second} = Beaches.get_beach_by_osm_id("way/1")

      assert first == second
    end

    test "preskače plaže izvan hrvatske obale umjesto da padne" do
      nica = element("way/9", %{centroid: %Geo.Point{coordinates: {7.26, 43.71}, srid: 4326}})

      assert %{inserted: 1, skipped: 1} = Import.store([element("way/1"), nica])
      assert Beaches.count_beaches() == 1
    end

    test "isti osm_id dvaput u istom odgovoru ne ruši upsert" do
      assert %{inserted: 1, updated: 0} =
               Import.store([
                 element("way/1", %{name: "Prvi"}),
                 element("way/1", %{name: "Drugi"})
               ])

      assert %{name: "Drugi"} = Beaches.get_beach_by_osm_id("way/1")
    end

    test "prazan odgovor je uspjeh bez promjena" do
      assert %{inserted: 0, updated: 0, skipped: 0} = Import.store([])
    end

    test "primjenjuje generirane atribute" do
      Import.store([element("way/1", %{tags: %{"dog" => "designated", "surface" => "sand"}})])

      beach = Beaches.get_beach_by_osm_id("way/1")

      assert beach.dog_status == :designated
      assert beach.dog_status_source == :osm
      assert beach.surface == :sand

      assert beach.amenities |> Map.keys() |> Enum.sort() ==
               ~w(bins dog_shower parking shade water)
    end
  end

  describe "import_beaches/1" do
    test "prosljeđuje opcije klijentu i sprema rezultat" do
      expect(OverpassMock, :fetch_beaches, fn opts ->
        assert opts[:bbox] == {43.49, 16.41, 43.52, 16.48}
        {:ok, [element("way/1")]}
      end)

      assert {:ok, %{inserted: 1}} = Import.import_beaches(bbox: {43.49, 16.41, 43.52, 16.48})
    end

    test "greška klijenta se propagira i ništa se ne sprema" do
      expect(OverpassMock, :fetch_beaches, fn _ -> {:error, {:http_error, 504}} end)

      assert {:error, {:http_error, 504}} = Import.import_beaches()
      assert Beaches.count_beaches() == 0
    end
  end
end
