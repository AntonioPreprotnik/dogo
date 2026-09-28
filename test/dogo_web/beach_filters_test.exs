defmodule DogoWeb.BeachFiltersTest do
  @moduledoc "E3-S6: filteri putuju kroz URL, pa se parsiranje testira zasebno."
  use ExUnit.Case, async: true

  alias DogoWeb.BeachFilters

  describe "parse/1" do
    test "prazni parametri daju prazne filtere" do
      assert BeachFilters.parse(%{}) == %BeachFilters{}
      refute BeachFilters.active?(BeachFilters.parse(%{}))
    end

    test "čita popise odvojene zarezom" do
      filters = BeachFilters.parse(%{"dog" => "designated,allowed", "surface" => "sand"})

      assert filters.dog_status == [:designated, :allowed]
      assert filters.surface == [:sand]
    end

    test "odbacuje vrijednosti izvan sheme umjesto da padne" do
      filters = BeachFilters.parse(%{"dog" => "designated,nepostojeci", "surface" => "lava"})

      assert filters.dog_status == [:designated]
      assert filters.surface == []
    end

    test "ne pretvara nepoznat ulaz u atom" do
      # Kad bi parser zvao String.to_atom/1, napadac bi kroz query string mogao
      # puniti atom tablicu, koja se ne skuplja. Brojanje atoma bi ovdje bilo
      # nestabilno (drugi async testovi ih stvaraju), pa provjeravamo izravno:
      # atom ne smije postojati nakon parsiranja.
      BeachFilters.parse(%{"dog" => "izmisljeni_status_iz_url_a"})

      assert_raise ArgumentError, fn ->
        String.to_existing_atom("izmisljeni_status_iz_url_a")
      end
    end

    test "duplikati se miču" do
      assert BeachFilters.parse(%{"dog" => "allowed,allowed"}).dog_status == [:allowed]
    end

    test "prihvaća samo ponuđene radijuse" do
      assert BeachFilters.parse(%{"radius" => "10000"}).radius_m == 10_000
      assert BeachFilters.parse(%{"radius" => "7000"}).radius_m == nil
      assert BeachFilters.parse(%{"radius" => "abc"}).radius_m == nil
      assert BeachFilters.parse(%{"radius" => "10000; DROP TABLE"}).radius_m == nil
    end

    test "podnosi parametre koji nisu stringovi" do
      assert BeachFilters.parse(%{"dog" => ["a", "b"], "radius" => %{"x" => 1}}) ==
               %BeachFilters{}
    end
  end

  describe "to_params/1" do
    test "prazni filteri ne ostavljaju trag u URL-u" do
      assert BeachFilters.to_params(%BeachFilters{}) == %{}
    end

    test "isto stanje uvijek daje isti zapis" do
      a = %BeachFilters{dog_status: [:allowed, :designated]}
      b = %BeachFilters{dog_status: [:designated, :allowed]}

      assert BeachFilters.to_params(a) == BeachFilters.to_params(b)
      assert BeachFilters.to_params(a) == %{"dog" => "allowed,designated"}
    end

    test "kružno putovanje kroz URL čuva stanje" do
      filters = %BeachFilters{
        dog_status: [:designated],
        surface: [:pebble, :sand],
        amenities: [:water],
        radius_m: 25_000
      }

      assert filters |> BeachFilters.to_params() |> BeachFilters.parse() == filters
    end
  end

  describe "from_form/1" do
    test "čita checkboxe" do
      params = %{
        "dog" => %{"designated" => "true", "allowed" => "false"},
        "amenities" => %{"water" => "true"},
        "radius" => "5000"
      }

      filters = BeachFilters.from_form(params)

      assert filters.dog_status == [:designated]
      assert filters.amenities == [:water]
      assert filters.radius_m == 5_000
    end

    test "prazna forma daje prazne filtere" do
      assert BeachFilters.from_form(%{}) == %BeachFilters{}
    end
  end

  describe "to_opts/1" do
    test "daje opcije koje kontekst razumije" do
      opts = BeachFilters.to_opts(%BeachFilters{dog_status: [:allowed], radius_m: 5_000})

      assert opts[:dog_status] == [:allowed]
      assert opts[:within_m] == 5_000
      assert opts[:surface] == []
    end
  end
end
