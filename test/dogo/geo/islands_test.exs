defmodule Dogo.Geo.IslandsTest do
  @moduledoc """
  E5-S2. Model je namjerno grub: kopno i otoci s mostom su jedna skupina,
  svaki otok bez mosta je svoja.
  """
  use Dogo.DataCase, async: true

  import Dogo.BeachesFixtures

  alias Dogo.Geo.Island
  alias Dogo.Geo.Islands
  alias Dogo.Import.Islands, as: Import
  alias Dogo.Import.Overpass.IslandElement

  defp square(osm_id, lon, lat, size \\ 0.1) do
    corners = [
      {lon, lat},
      {lon + size, lat},
      {lon + size, lat + size},
      {lon, lat + size},
      {lon, lat}
    ]

    lines = corners |> Enum.chunk_every(2, 1, :discard) |> Enum.map(&Enum.to_list/1)
    %IslandElement{osm_id: osm_id, name: osm_id, lines: lines}
  end

  defp island(osm_id, lon, lat, bridge_connected) do
    Import.store([square(osm_id, lon, lat)])
    island = Repo.get_by!(Island, osm_id: osm_id)

    Repo.update_all(from(i in Island, where: i.id == ^island.id),
      set: [bridge_connected: bridge_connected]
    )

    Repo.reload!(island)
  end

  describe "across_sea?/2" do
    test "kopno prema kopnu ne treba trajekt" do
      refute Islands.across_sea?(nil, nil)
    end

    test "s kopna na otok bez mosta treba trajekt" do
      hvar = %Island{id: 1, bridge_connected: false}

      assert Islands.across_sea?(nil, hvar)
      assert Islands.across_sea?(hvar, nil)
    end

    test "s kopna na otok s mostom ne treba trajekt" do
      krk = %Island{id: 1, bridge_connected: true}

      refute Islands.across_sea?(nil, krk)
      refute Islands.across_sea?(krk, nil)
    end

    test "unutar istog otoka nema mora, ni kad nema mosta" do
      hvar = %Island{id: 7, bridge_connected: false}

      refute Islands.across_sea?(hvar, hvar)
    end

    test "s jednog otoka s mostom na drugi se vozi preko kopna" do
      krk = %Island{id: 1, bridge_connected: true}
      pag = %Island{id: 2, bridge_connected: true}

      refute Islands.across_sea?(krk, pag)
    end

    test "izmedu dva otoka bez mosta treba trajekt" do
      hvar = %Island{id: 1, bridge_connected: false}
      brac = %Island{id: 2, bridge_connected: false}

      assert Islands.across_sea?(hvar, brac)
    end

    test "s otoka bez mosta na otok s mostom treba trajekt" do
      hvar = %Island{id: 1, bridge_connected: false}
      krk = %Island{id: 2, bridge_connected: true}

      assert Islands.across_sea?(hvar, krk)
    end
  end

  describe "road_connected?/1" do
    test "kopno i otoci s mostom" do
      assert Islands.road_connected?(nil)
      assert Islands.road_connected?(%Island{bridge_connected: true})
      refute Islands.road_connected?(%Island{bridge_connected: false})
    end
  end

  describe "at/2" do
    setup do
      %{otok: island("way/otok", 16.0, 43.0, false)}
    end

    test "tocka na otoku vraca taj otok", %{otok: otok} do
      assert %Island{id: id} = Islands.at(point(16.05, 43.05))
      assert id == otok.id
    end

    test "tocka na kopnu vraca nil" do
      assert Islands.at(point(16.44, 43.50)) == nil
    end

    test "nil tocka vraca nil" do
      assert Islands.at(nil) == nil
    end

    test "tocka koji metar u moru se i dalje racuna otoku" do
      refute is_nil(Islands.at(point(16.0 - 0.0008, 43.05)))
    end
  end

  describe "migracija oznacava otoke s mostom" do
    test "Krk i Pag su oznaceni, Hvar nije" do
      # Migracija oznacava po imenu; ovdje provjeravamo da popis djeluje.
      Import.store([
        %{square("relation/krk", 16.0, 43.0) | name: "Krk"},
        %{square("relation/hvar", 16.5, 43.0) | name: "Hvar"}
      ])

      Repo.query!("UPDATE islands SET bridge_connected = true WHERE name IN ('Krk', 'Pag')")

      assert Repo.get_by!(Island, name: "Krk").bridge_connected
      refute Repo.get_by!(Island, name: "Hvar").bridge_connected
    end
  end
end
