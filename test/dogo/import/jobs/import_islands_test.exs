defmodule Dogo.Import.Jobs.ImportIslandsTest do
  use Dogo.DataCase, async: true
  use Oban.Testing, repo: Dogo.Repo

  import Mox

  alias Dogo.Geo.Island
  alias Dogo.Import.Jobs.ImportIslands
  alias Dogo.Import.Overpass.Parser
  alias Dogo.OverpassFixtures
  alias Dogo.OverpassMock

  setup :verify_on_exit!

  defp krk do
    {:ok, islands} = "island_krk" |> OverpassFixtures.decoded() |> Parser.parse_islands()
    islands
  end

  describe "perform/1" do
    test "uvozi otoke sa snimljenog odgovora i vraća brojače" do
      expect(OverpassMock, :fetch_islands, fn [] -> {:ok, krk()} end)

      assert {:ok, %{inserted: 1, skipped: 0}} = perform_job(ImportIslands, %{})
      assert %Island{name: "Krk"} = Repo.one(Island)
    end

    test "greška Overpassa vraća {:error, _}, pa Oban ponavlja job" do
      expect(OverpassMock, :fetch_islands, fn _ ->
        {:error, %Req.TransportError{reason: :econnrefused}}
      end)

      assert {:error, %Req.TransportError{}} = perform_job(ImportIslands, %{})
    end

    test "prag površine i veličina serije stižu do klijenta" do
      expect(OverpassMock, :fetch_islands, fn opts ->
        assert opts[:min_area_km2] == 5
        assert opts[:batch_size] == 4
        {:ok, []}
      end)

      assert {:ok, _} = perform_job(ImportIslands, %{"min_area_km2" => 5, "batch_size" => 4})
    end
  end

  describe "opts_from_args/1" do
    test "ignorira vrijednosti koje nisu brojevi" do
      assert ImportIslands.opts_from_args(%{"min_area_km2" => "5", "batch_size" => nil}) == []
    end
  end

  describe "enqueue" do
    test "dva uzastopna uvoza ne stvaraju dva joba" do
      assert {:ok, first} = Oban.insert(ImportIslands.new(%{}))
      assert {:ok, second} = Oban.insert(ImportIslands.new(%{}))

      assert second.conflict?
      assert first.id == second.id
    end
  end
end
