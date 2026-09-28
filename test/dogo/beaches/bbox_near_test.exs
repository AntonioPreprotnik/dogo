defmodule Dogo.Beaches.BboxNearTest do
  @moduledoc "E3-S4: bbox upit s referentnom točkom vraća udaljenosti i poredak."
  use Dogo.DataCase, async: true

  import Dogo.BeachesFixtures

  alias Dogo.Beaches

  @bbox {16.40, 43.48, 16.52, 43.54}
  @center %Geo.Point{coordinates: {16.45, 43.505}, srid: 4326}

  setup do
    beach_fixture(%{osm_id: "way/c", name: "Daleko", geom: point(16.5000, 43.5300)})
    beach_fixture(%{osm_id: "way/a", name: "Blizu", geom: point(16.4505, 43.5050)})
    beach_fixture(%{osm_id: "way/b", name: "Srednje", geom: point(16.4700, 43.5150)})
    :ok
  end

  test "bez :near poredak je po id-u i nema udaljenosti" do
    assert {:ok, beaches} = Beaches.within_bbox(@bbox)

    assert Enum.map(beaches, & &1.name) == ["Daleko", "Blizu", "Srednje"]
    assert Enum.all?(beaches, &is_nil(&1.distance_m))
  end

  test "s :near poredak je po udaljenosti od te točke" do
    assert {:ok, beaches} = Beaches.within_bbox(@bbox, near: @center)

    assert Enum.map(beaches, & &1.name) == ["Blizu", "Srednje", "Daleko"]
  end

  test "s :near svaka plaža ima udaljenost u metrima" do
    assert {:ok, [blizu | _]} = Beaches.within_bbox(@bbox, near: @center)

    assert_in_delta blizu.distance_m, 40, 25
  end

  test ":near ne širi rezultat izvan pravokutnika" do
    beach_fixture(%{osm_id: "way/out", name: "Izvan", geom: point(16.9, 43.5)})

    assert {:ok, beaches} = Beaches.within_bbox(@bbox, near: @center)

    refute "Izvan" in Enum.map(beaches, & &1.name)
  end

  test ":near se kombinira s filterima" do
    beach_fixture(%{
      osm_id: "way/dog",
      name: "Za pse",
      geom: point(16.4600, 43.5100),
      dog_status: :designated
    })

    assert {:ok, [beach]} = Beaches.within_bbox(@bbox, near: @center, dog_status: [:designated])
    assert beach.name == "Za pse"
    assert beach.distance_m > 0
  end

  test "limit reže po udaljenosti, ne nasumično" do
    assert {:too_many, beaches} = Beaches.within_bbox(@bbox, near: @center, limit: 2)

    assert Enum.map(beaches, & &1.name) == ["Blizu", "Srednje"]
  end

  describe ":within_m" do
    test "reže rezultat na radijus oko :near" do
      assert {:ok, beaches} = Beaches.within_bbox(@bbox, near: @center, within_m: 1_500)

      assert Enum.map(beaches, & &1.name) == ["Blizu"]
    end

    test "veći radijus propušta više" do
      assert {:ok, beaches} = Beaches.within_bbox(@bbox, near: @center, within_m: 3_000)

      assert Enum.map(beaches, & &1.name) == ["Blizu", "Srednje"]
    end

    test "bez :near se ignorira, jer nema od čega mjeriti" do
      assert {:ok, beaches} = Beaches.within_bbox(@bbox, within_m: 1)

      assert length(beaches) == 3
    end
  end
end
