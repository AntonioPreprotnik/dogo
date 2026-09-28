defmodule Dogo.Beaches.NearestTest do
  @moduledoc """
  E2-S1. Očekivane udaljenosti računa Haversine u testu — neovisna
  implementacija, pa test stvarno provjerava PostGIS, a ne sam sebe.
  """
  use Dogo.DataCase, async: true

  import Dogo.BeachesFixtures

  alias Dogo.Beaches

  # Riva u Splitu.
  @from %Geo.Point{coordinates: {16.4392, 43.5081}, srid: 4326}

  @earth_radius_m 6_371_008.8

  defp haversine_m(%Geo.Point{coordinates: {lon1, lat1}}, %Geo.Point{coordinates: {lon2, lat2}}) do
    rad = &(&1 * :math.pi() / 180)
    dlat = rad.(lat2 - lat1)
    dlon = rad.(lon2 - lon1)

    a =
      :math.sin(dlat / 2) ** 2 +
        :math.cos(rad.(lat1)) * :math.cos(rad.(lat2)) * :math.sin(dlon / 2) ** 2

    @earth_radius_m * 2 * :math.asin(:math.sqrt(a))
  end

  describe "nearest/2 udaljenosti i poredak" do
    setup do
      bacvice = point(16.4453, 43.5041)
      znjan = point(16.4700, 43.5015)
      kasjuni = point(16.4062, 43.5061)

      %{
        bacvice: beach_fixture(%{osm_id: "way/bacvice", name: "Bačvice", geom: bacvice}),
        znjan: beach_fixture(%{osm_id: "way/znjan", name: "Žnjan", geom: znjan}),
        kasjuni: beach_fixture(%{osm_id: "way/kasjuni", name: "Kašjuni", geom: kasjuni}),
        points: %{"Bačvice" => bacvice, "Žnjan" => znjan, "Kašjuni" => kasjuni}
      }
    end

    test "poredak je po stvarnoj udaljenosti", %{points: points} do
      names = @from |> Beaches.nearest() |> Enum.map(& &1.name)

      expected =
        points
        |> Enum.sort_by(fn {_name, point} -> haversine_m(@from, point) end)
        |> Enum.map(fn {name, _} -> name end)

      assert names == expected
    end

    test "udaljenost je u metrima, unutar 1 % Haversinea", %{points: points} do
      for beach <- Beaches.nearest(@from) do
        expected = haversine_m(@from, points[beach.name])

        assert_in_delta beach.distance_m, expected, expected * 0.01
      end
    end

    test "udaljenosti su stotine metara do par kilometara, ne stupnjevi" do
      distances = @from |> Beaches.nearest() |> Enum.map(& &1.distance_m)

      assert Enum.all?(distances, &(&1 > 100 and &1 < 10_000))
    end

    test "poredak je sferoidni, ne ravninski po stupnjevima" do
      # Namjerno obrnut par: istočna plaža je u stupnjevima *dalje*
      # (0.030° > 0.025°), ali stvarno bliže, jer je stupanj duljine na 43.
      # paraleli oko 27 % kraći. Ravninski `<->` bi ih zamijenio.
      east = point(16.4392 + 0.030, 43.5081)
      north = point(16.4392, 43.5081 + 0.025)

      beach_fixture(%{osm_id: "way/east", name: "Istok", geom: east})
      beach_fixture(%{osm_id: "way/north", name: "Sjever", geom: north})

      [first, second] =
        @from
        |> Beaches.nearest(limit: 50)
        |> Enum.filter(&(&1.name in ["Istok", "Sjever"]))

      assert first.name == "Istok"
      assert second.name == "Sjever"
      assert first.distance_m < second.distance_m
    end

    test "rezultat je uvijek rastuće poredan po distance_m" do
      for i <- 1..20 do
        beach_fixture(%{
          osm_id: "way/spread#{i}",
          geom: point(16.40 + i * 0.004, 43.48 + i * 0.003)
        })
      end

      distances = @from |> Beaches.nearest(limit: 50) |> Enum.map(& &1.distance_m)

      assert distances == Enum.sort(distances)
    end
  end

  describe "nearest/2 opcije" do
    setup do
      beach_fixture(%{
        osm_id: "way/a",
        name: "Za pse",
        geom: point(16.4453, 43.5041),
        dog_status: :designated,
        surface: :sand,
        amenities: %{"water" => true, "shade" => true}
      })

      beach_fixture(%{
        osm_id: "way/b",
        name: "Zabranjeno",
        geom: point(16.4470, 43.5041),
        dog_status: :not_allowed,
        surface: :pebble,
        amenities: %{"water" => true, "shade" => false}
      })

      beach_fixture(%{
        osm_id: "way/c",
        name: "Nepoznato",
        geom: point(16.4490, 43.5041),
        dog_status: :unknown,
        surface: :rock,
        amenities: %{}
      })

      :ok
    end

    test "zadani limit je 20" do
      for i <- 1..25 do
        beach_fixture(%{osm_id: "way/mass#{i}", geom: point(16.44 + i / 10_000, 43.50)})
      end

      assert length(Beaches.nearest(@from)) == 20
    end

    test "limit se može promijeniti" do
      assert length(Beaches.nearest(@from, limit: 2)) == 2
    end

    test "filtrira po statusu za pse" do
      names =
        @from
        |> Beaches.nearest(dog_status: [:designated, :allowed])
        |> Enum.map(& &1.name)

      assert names == ["Za pse"]
    end

    test "filtrira po podlozi" do
      names = @from |> Beaches.nearest(surface: [:pebble, :rock]) |> Enum.map(& &1.name)

      assert Enum.sort(names) == ["Nepoznato", "Zabranjeno"]
    end

    test "filtrira po sadržajima, traži sve navedene" do
      assert @from |> Beaches.nearest(amenities: [:water]) |> Enum.map(& &1.name) |> Enum.sort() ==
               ["Za pse", "Zabranjeno"]

      assert @from |> Beaches.nearest(amenities: [:water, :shade]) |> Enum.map(& &1.name) ==
               ["Za pse"]
    end

    test "filteri se kombiniraju" do
      assert Beaches.nearest(@from, dog_status: [:not_allowed], amenities: [:shade]) == []
    end

    test "prazan filter ne filtrira ništa" do
      assert length(Beaches.nearest(@from, dog_status: [], surface: [])) == 3
    end
  end

  test "nearest/2 na praznoj bazi vraća prazan popis" do
    assert Beaches.nearest(@from) == []
  end
end
