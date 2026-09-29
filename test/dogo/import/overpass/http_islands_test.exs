defmodule Dogo.Import.Overpass.HTTPIslandsTest do
  @moduledoc """
  Dvofazni dohvat otoka (ADR 0005): prvo granice svih otoka, pa geometrija
  samo onih dovoljno velikih, u serijama. Sve kroz `Req.Test`, bez mreže.
  """
  use ExUnit.Case, async: true

  @moduletag :capture_log

  alias Dogo.Import.Overpass.HTTP
  alias Dogo.OverpassFixtures

  # Otok od ~0,01 stupnja je hrid (~0,9 km²), otok od 0,1 stupnja je
  # ~87 km². Prag je 1 km².
  @big_way %{
    "type" => "way",
    "id" => 101,
    "tags" => %{"name" => "Veliki"},
    "bounds" => %{"minlat" => 43.0, "maxlat" => 43.1, "minlon" => 16.0, "maxlon" => 16.1}
  }
  @big_relation %{
    "type" => "relation",
    "id" => 202,
    "tags" => %{"name" => "Relacija"},
    "bounds" => %{"minlat" => 44.0, "maxlat" => 44.1, "minlon" => 14.5, "maxlon" => 14.6}
  }
  @rock %{
    "type" => "way",
    "id" => 303,
    "tags" => %{"name" => "Hrid"},
    "bounds" => %{"minlat" => 43.0, "maxlat" => 43.01, "minlon" => 16.0, "maxlon" => 16.01}
  }

  setup do
    Req.Test.verify_on_exit!()
  end

  defp query(conn) do
    {:ok, body, conn} = Plug.Conn.read_body(conn)
    {URI.decode_query(body)["data"], conn}
  end

  defp json(conn, body) when is_map(body) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.resp(200, Jason.encode!(body))
  end

  defp raw(conn, name) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.resp(200, OverpassFixtures.raw(name))
  end

  # Stub koji sam razlikuje fazu po upitu i biljezi sve upite geometrije.
  defp two_phase_stub(bounds_elements, recorder) do
    fn conn ->
      {data, conn} = query(conn)

      if data =~ "out bb tags" do
        json(conn, %{"elements" => bounds_elements})
      else
        Agent.update(recorder, &[data | &1])
        raw(conn, "island_krk")
      end
    end
  end

  describe "fetch_islands/1" do
    test "geometriju traži samo za otoke iznad praga površine" do
      {:ok, recorder} = Agent.start_link(fn -> [] end)
      Req.Test.stub(HTTP, two_phase_stub([@big_way, @big_relation, @rock], recorder))

      assert {:ok, [island]} = HTTP.fetch_islands(batch_pause_ms: 0)
      assert island.osm_id == "relation/1924210"

      assert [geometry_query] = Agent.get(recorder, & &1)
      assert geometry_query =~ "way(id:101);"
      assert geometry_query =~ "relation(id:202);"
      refute geometry_query =~ "303"
      assert geometry_query =~ "out geom"
    end

    test "dijeli dohvat geometrije u serije zadane veličine" do
      {:ok, recorder} = Agent.start_link(fn -> [] end)
      Req.Test.stub(HTTP, two_phase_stub([@big_way, @big_relation], recorder))

      assert {:ok, islands} = HTTP.fetch_islands(batch_size: 1, batch_pause_ms: 0)
      assert length(islands) == 2

      queries = Agent.get(recorder, &Enum.reverse/1)
      assert length(queries) == 2
      assert Enum.at(queries, 0) =~ "way(id:101);"
      refute Enum.at(queries, 0) =~ "relation("
      assert Enum.at(queries, 1) =~ "relation(id:202);"
      refute Enum.at(queries, 1) =~ "way(id:"
    end

    test "prag površine je podesiv" do
      {:ok, recorder} = Agent.start_link(fn -> [] end)
      Req.Test.stub(HTTP, two_phase_stub([@big_way, @rock], recorder))

      assert {:ok, _} = HTTP.fetch_islands(min_area_km2: 0.5, batch_pause_ms: 0)

      assert [geometry_query] = Agent.get(recorder, & &1)
      assert geometry_query =~ "way(id:101,303);"
    end

    test "bez kandidata ne šalje upit za geometriju" do
      {:ok, recorder} = Agent.start_link(fn -> [] end)
      Req.Test.stub(HTTP, two_phase_stub([@rock], recorder))

      assert {:ok, []} = HTTP.fetch_islands(batch_pause_ms: 0)
      assert Agent.get(recorder, & &1) == []
    end

    test "greška u jednoj seriji prekida uvoz, umjesto da vrati pola otoka" do
      counter = :counters.new(1, [])

      Req.Test.stub(HTTP, fn conn ->
        {data, conn} = query(conn)

        cond do
          data =~ "out bb tags" ->
            json(conn, %{"elements" => [@big_way, @big_relation]})

          :counters.get(counter, 1) == 0 ->
            :counters.add(counter, 1, 1)
            raw(conn, "island_krk")

          true ->
            Plug.Conn.resp(conn, 400, "bad request")
        end
      end)

      assert {:error, {:http_error, 400}} = HTTP.fetch_islands(batch_size: 1, batch_pause_ms: 0)
    end

    test "Overpass remark u prvoj fazi je greška" do
      Req.Test.stub(HTTP, &json(&1, %{"elements" => [], "remark" => "runtime error: timeout"}))

      assert {:error, {:overpass_remark, "runtime error: timeout"}} = HTTP.fetch_islands()
    end

    test "Overpass remark u drugoj fazi je greška" do
      Req.Test.stub(HTTP, fn conn ->
        {data, conn} = query(conn)

        if data =~ "out bb tags",
          do: json(conn, %{"elements" => [@big_way]}),
          else: json(conn, %{"elements" => [], "remark" => "out of memory"})
      end)

      assert {:error, {:overpass_remark, "out of memory"}} =
               HTTP.fetch_islands(batch_pause_ms: 0)
    end

    test "odgovor koji nije JSON je greška, ne pad" do
      Req.Test.stub(HTTP, &Plug.Conn.resp(&1, 200, "<html>maintenance</html>"))

      assert {:error, {:invalid_json, _}} = HTTP.fetch_islands()
    end

    test "mrežna greška se vraća kao greška" do
      Req.Test.stub(HTTP, &Req.Test.transport_error(&1, :econnrefused))

      assert {:error, %Req.TransportError{reason: :econnrefused}} = HTTP.fetch_islands()
    end
  end

  describe "bbox_area_km2/1" do
    test "uzima u obzir skraćivanje stupnja duljine prema sjeveru" do
      square = fn lat ->
        HTTP.bbox_area_km2(%{
          "minlat" => lat,
          "maxlat" => lat + 0.1,
          "minlon" => 16.0,
          "maxlon" => 16.1
        })
      end

      # Na ekvatoru ~124 km², na 43. paraleli ~90 km².
      assert_in_delta square.(0.0), 123.9, 0.5
      assert_in_delta square.(43.0), 90.5, 0.5
    end
  end
end
