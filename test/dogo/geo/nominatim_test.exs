defmodule Dogo.Geo.Geocoder.NominatimTest do
  @moduledoc """
  E4-S2. Testovi idu kroz `Req.Test` plug — nema mrežnih poziva.
  """
  use ExUnit.Case, async: false

  @moduletag :capture_log

  alias Dogo.Geo.Geocoder.Nominatim
  alias Dogo.Geo.Place
  alias Dogo.Geo.PlaceCache

  @fixture Path.join(__DIR__, "../../support/fixtures/nominatim/split.json")

  setup do
    PlaceCache.clear()
    Req.Test.verify_on_exit!()
  end

  defp stub_json(body \\ File.read!(@fixture)) do
    counter = :counters.new(1, [])

    Req.Test.stub(Nominatim, fn conn ->
      :counters.add(counter, 1, 1)
      send(self(), {:nominatim_params, conn.query_string})

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, body)
    end)

    counter
  end

  describe "search/1" do
    test "vraća mjesta s koordinatama" do
      stub_json()

      assert {:ok, [%Place{} = split, %Place{} = luka]} = Nominatim.search("Split")

      assert split.name == "Split"
      assert split.description =~ "Splitsko-dalmatinska"
      assert %Geo.Point{coordinates: {16.4399659, 43.5116383}, srid: 4326} = split.point
      assert luka.name == "Splitska luka"
    end

    test "pretraga je ograničena na Hrvatsku i na pet rezultata" do
      stub_json()

      Nominatim.search("Split")

      assert_received {:nominatim_params, query_string}
      params = URI.decode_query(query_string)

      assert params["countrycodes"] == "hr"
      assert params["limit"] == "5"
      assert params["format"] == "jsonv2"
      assert params["q"] == "Split"
    end

    test "šalje User-Agent s kontaktom, kako traži usage policy" do
      Req.Test.stub(Nominatim, fn conn ->
        assert [user_agent] = Plug.Conn.get_req_header(conn, "user-agent")
        assert user_agent =~ "dogo"

        Plug.Conn.resp(conn, 200, "[]")
      end)

      assert {:ok, []} = Nominatim.search("Split")
    end

    test "rezultat bez upotrebljivih koordinata se preskače" do
      stub_json(~s([{"lat": "abc", "lon": "16.4", "display_name": "Krivo"}]))

      assert {:ok, []} = Nominatim.search("Krivo")
    end

    test "HTTP greška se vraća pozivatelju" do
      Req.Test.stub(Nominatim, &Plug.Conn.resp(&1, 429, "rate limited"))

      assert {:error, {:http_error, 429}} = Nominatim.search("Split")
    end
  end

  describe "cache" do
    test "isti upit se ne pita dvaput" do
      counter = stub_json()

      assert {:ok, first} = Nominatim.search("Split")
      assert {:ok, second} = Nominatim.search("Split")

      assert first == second
      assert :counters.get(counter, 1) == 1
    end

    test "ključ ne razlikuje velika slova ni razmake" do
      counter = stub_json()

      Nominatim.search("Split")
      Nominatim.search("  split  ")
      Nominatim.search("SPLIT")

      assert :counters.get(counter, 1) == 1
    end

    test "različit upit ide na mrežu" do
      counter = stub_json()

      Nominatim.search("Split")
      Nominatim.search("Zadar")

      assert :counters.get(counter, 1) == 2
    end

    test "neuspjeh se ne cacheira" do
      counter = :counters.new(1, [])

      Req.Test.stub(Nominatim, fn conn ->
        :counters.add(counter, 1, 1)
        Plug.Conn.resp(conn, 500, "boom")
      end)

      assert {:error, _} = Nominatim.search("Split")
      assert {:error, _} = Nominatim.search("Split")

      assert :counters.get(counter, 1) == 2
    end

    test "istekli zapis se ponovno dohvaća" do
      previous = Application.get_env(:dogo, :place_cache_ttl_ms)
      Application.put_env(:dogo, :place_cache_ttl_ms, 1)

      on_exit(fn ->
        if previous,
          do: Application.put_env(:dogo, :place_cache_ttl_ms, previous),
          else: Application.delete_env(:dogo, :place_cache_ttl_ms)
      end)

      counter = stub_json()

      Nominatim.search("Split")
      Process.sleep(5)
      Nominatim.search("Split")

      assert :counters.get(counter, 1) == 2
    end
  end
end
