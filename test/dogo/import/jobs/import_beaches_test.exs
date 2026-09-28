defmodule Dogo.Import.Jobs.ImportBeachesTest do
  use Dogo.DataCase, async: true
  use Oban.Testing, repo: Dogo.Repo

  import Mox

  alias Dogo.Beaches
  alias Dogo.Import.Jobs.ImportBeaches
  alias Dogo.Import.Overpass.Element
  alias Dogo.OverpassMock

  setup :verify_on_exit!

  defp element(osm_id) do
    %Element{
      osm_id: osm_id,
      name: "Plaža #{osm_id}",
      centroid: %Geo.Point{coordinates: {16.44, 43.50}, srid: 4326},
      tags: %{}
    }
  end

  describe "perform/1" do
    test "uvozi plaže i vraća brojače" do
      expect(OverpassMock, :fetch_beaches, fn [] -> {:ok, [element("way/1")]} end)

      assert {:ok, %{inserted: 1, updated: 0, skipped: 0}} = perform_job(ImportBeaches, %{})
      assert Beaches.count_beaches() == 1
    end

    test "ponovno pokretanje ne mijenja broj plaža" do
      expect(OverpassMock, :fetch_beaches, 2, fn _ ->
        {:ok, [element("way/1"), element("way/2")]}
      end)

      assert {:ok, %{inserted: 2}} = perform_job(ImportBeaches, %{})
      assert {:ok, %{inserted: 0, updated: 2}} = perform_job(ImportBeaches, %{})

      assert Beaches.count_beaches() == 2
    end

    test "greška Overpassa vraća {:error, _}, pa Oban ponavlja job" do
      expect(OverpassMock, :fetch_beaches, fn _ -> {:error, {:http_error, 429}} end)

      assert {:error, {:http_error, 429}} = perform_job(ImportBeaches, %{})
    end

    test "bbox iz argumenata stiže do klijenta kao torka" do
      expect(OverpassMock, :fetch_beaches, fn opts ->
        assert opts[:bbox] == {43.49, 16.41, 43.52, 16.48}
        assert opts[:timeout] == 60
        {:ok, []}
      end)

      assert {:ok, _} =
               perform_job(ImportBeaches, %{
                 "bbox" => [43.49, 16.41, 43.52, 16.48],
                 "timeout" => 60
               })
    end
  end

  describe "opts_from_args/1" do
    test "prazni argumenti daju prazne opcije" do
      assert ImportBeaches.opts_from_args(%{}) == []
    end

    test "nepotpun bbox se ignorira umjesto da sruši job" do
      assert ImportBeaches.opts_from_args(%{"bbox" => [1, 2]}) == []
    end
  end

  describe "red" do
    test "job ide u red :imports" do
      assert {:ok, _job} = Oban.insert(ImportBeaches.new(%{}))

      assert_enqueued(worker: ImportBeaches, queue: :imports)
    end

    test "unique sprječava drugi isti uvoz u redu" do
      assert {:ok, %Oban.Job{id: id, conflict?: false}} = Oban.insert(ImportBeaches.new(%{}))
      assert {:ok, %Oban.Job{id: ^id, conflict?: true}} = Oban.insert(ImportBeaches.new(%{}))
    end

    test "uvoz drugog bboxa nije duplikat" do
      assert {:ok, %Oban.Job{id: first}} = Oban.insert(ImportBeaches.new(%{}))

      assert {:ok, %Oban.Job{id: second, conflict?: false}} =
               Oban.insert(ImportBeaches.new(%{"bbox" => [43.0, 16.0, 44.0, 17.0]}))

      refute first == second
    end
  end
end
