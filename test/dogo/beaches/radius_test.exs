defmodule Dogo.Beaches.RadiusTest do
  @moduledoc "E2-S3: pretraga u radijusu."
  use Dogo.DataCase, async: true

  import Dogo.BeachesFixtures

  alias Dogo.Beaches

  @from %Geo.Point{coordinates: {16.4392, 43.5081}, srid: 4326}

  setup do
    # ~0.6 km, ~5.3 km i ~24 km od @from.
    beach_fixture(%{osm_id: "way/blizu", name: "Blizu", geom: point(16.4453, 43.5041)})
    beach_fixture(%{osm_id: "way/srednje", name: "Srednje", geom: point(16.5050, 43.5081)})
    beach_fixture(%{osm_id: "way/daleko", name: "Daleko", geom: point(16.7350, 43.5081)})
    :ok
  end

  test "radijus od 5 km hvata samo najbližu" do
    assert Beaches.within_radius(@from, 5_000) |> Enum.map(& &1.name) == ["Blizu"]
  end

  test "radijus od 10 km hvata dvije" do
    assert Beaches.within_radius(@from, 10_000) |> Enum.map(& &1.name) == ["Blizu", "Srednje"]
  end

  test "radijus od 50 km hvata sve i čuva poredak" do
    assert Beaches.within_radius(@from, 50_000) |> Enum.map(& &1.name) ==
             ["Blizu", "Srednje", "Daleko"]
  end

  test "radijus je u metrima, ne u stupnjevima" do
    [blizu] = Beaches.within_radius(@from, 1_000)

    assert_in_delta blizu.distance_m, 600, 150
  end

  test "sve plaže u rezultatu su stvarno unutar radijusa" do
    radius = 10_000

    for beach <- Beaches.within_radius(@from, radius) do
      assert beach.distance_m <= radius
    end
  end

  test "radijus se kombinira s filterima i limitom" do
    assert Beaches.within_radius(@from, 50_000, limit: 1) |> Enum.map(& &1.name) == ["Blizu"]
    assert Beaches.within_radius(@from, 50_000, dog_status: [:not_allowed]) == []
  end

  test "sučelje nudi 5, 10, 25 i 50 km" do
    assert Beaches.radii_m() == [5_000, 10_000, 25_000, 50_000]
  end

  test "nearest/2 prima :within_m izravno" do
    assert Beaches.nearest(@from, within_m: 5_000) |> Enum.map(& &1.name) == ["Blizu"]
  end
end
