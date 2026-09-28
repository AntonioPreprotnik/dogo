defmodule Dogo.Beaches.BboxTest do
  @moduledoc "E2-S2: plaže unutar vidljivog dijela karte."
  use Dogo.DataCase, async: true

  import Dogo.BeachesFixtures

  alias Dogo.Beaches

  # Uski pravokutnik oko splitske obale.
  @bbox {16.40, 43.50, 16.48, 43.52}

  setup do
    beach_fixture(%{osm_id: "way/in-1", name: "Unutra 1", geom: point(16.4453, 43.5041)})
    beach_fixture(%{osm_id: "way/in-2", name: "Unutra 2", geom: point(16.4200, 43.5100)})
    beach_fixture(%{osm_id: "way/out-e", name: "Istocno", geom: point(16.6000, 43.5100)})
    beach_fixture(%{osm_id: "way/out-s", name: "Juzno", geom: point(16.4400, 43.4000)})
    :ok
  end

  test "vraća samo plaže unutar pravokutnika" do
    assert {:ok, beaches} = Beaches.within_bbox(@bbox)

    assert beaches |> Enum.map(& &1.name) |> Enum.sort() == ["Unutra 1", "Unutra 2"]
  end

  test "plaža točno na rubu je unutra" do
    beach_fixture(%{osm_id: "way/edge", name: "Rub", geom: point(16.40, 43.50)})

    assert {:ok, beaches} = Beaches.within_bbox(@bbox)
    assert "Rub" in Enum.map(beaches, & &1.name)
  end

  test "filteri vrijede i ovdje" do
    beach_fixture(%{
      osm_id: "way/in-3",
      name: "Za pse",
      geom: point(16.4300, 43.5050),
      dog_status: :designated
    })

    assert {:ok, [beach]} = Beaches.within_bbox(@bbox, dog_status: [:designated])
    assert beach.name == "Za pse"
  end

  test "iznad limita vraća {:too_many, _} i reže rezultat" do
    for i <- 1..10 do
      beach_fixture(%{osm_id: "way/many#{i}", geom: point(16.41 + i / 10_000, 43.505)})
    end

    assert {:too_many, beaches} = Beaches.within_bbox(@bbox, limit: 5)
    assert length(beaches) == 5
  end

  test "točno na limitu je još uvijek {:ok, _}" do
    assert {:ok, beaches} = Beaches.within_bbox(@bbox, limit: 2)
    assert length(beaches) == 2
  end

  test "zadani tvrdi limit je 500" do
    assert Beaches.bbox_limit() == 500
  end

  test "prazan pravokutnik vraća prazan popis" do
    assert {:ok, []} = Beaches.within_bbox({18.0, 42.6, 18.1, 42.7})
  end
end
