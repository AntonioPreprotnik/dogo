defmodule Dogo.Import.Overpass.HTTPTest do
  @moduledoc """
  Testovi klijenta idu kroz `Req.Test` plug: nema mrežnih poziva.
  """
  use ExUnit.Case, async: true

  @moduletag :capture_log

  alias Dogo.Import.Overpass.HTTP
  alias Dogo.OverpassFixtures

  setup do
    Req.Test.verify_on_exit!()
  end

  defp json_fixture(conn, name) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.resp(200, OverpassFixtures.raw(name))
  end

  describe "fetch_beaches/1" do
    test "vraća parsirane elemente" do
      Req.Test.stub(HTTP, &json_fixture(&1, "beaches_split"))

      assert {:ok, elements} = HTTP.fetch_beaches()
      assert length(elements) == 4
      assert Enum.any?(elements, &(&1.name == "Bačvice"))
    end

    test "šalje upit kao form polje 'data' i User-Agent s kontaktom" do
      Req.Test.stub(HTTP, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        params = URI.decode_query(body)

        assert params["data"] =~ ~s(["natural"="beach"])
        assert params["data"] =~ ~s(["leisure"="beach_resort"])
        assert [user_agent] = Plug.Conn.get_req_header(conn, "user-agent")
        assert user_agent =~ "dogo"

        json_fixture(conn, "beaches_split")
      end)

      assert {:ok, _} = HTTP.fetch_beaches()
    end

    test "Overpass remark se vraća kao greška" do
      Req.Test.stub(HTTP, fn conn ->
        Plug.Conn.resp(conn, 200, ~s({"elements":[],"remark":"runtime error: Query timed out"}))
      end)

      assert {:error, {:overpass_remark, _}} = HTTP.fetch_beaches()
    end
  end

  describe "retry" do
    test "ponavlja na 429 i uspije iz drugog pokušaja" do
      Req.Test.stub(HTTP, counting_stub([429, 200]))

      assert {:ok, elements} = HTTP.fetch_beaches()
      assert length(elements) == 4
    end

    test "ponavlja na 504, koji Overpass vraća kad mu je dispatcher zauzet" do
      Req.Test.stub(HTTP, counting_stub([504, 504, 200]))

      assert {:ok, _} = HTTP.fetch_beaches()
    end

    test "odustaje nakon iscrpljenih pokušaja i vraća zadnji status" do
      Req.Test.stub(HTTP, counting_stub([503, 503, 503, 503]))

      assert {:error, {:http_error, 503}} = HTTP.fetch_beaches()
    end

    test "ne ponavlja na 400, jer kriv upit neće postati ispravan" do
      counter = :counters.new(1, [])

      Req.Test.stub(HTTP, fn conn ->
        :counters.add(counter, 1, 1)
        Plug.Conn.resp(conn, 400, "bad request")
      end)

      assert {:error, {:http_error, 400}} = HTTP.fetch_beaches()
      assert :counters.get(counter, 1) == 1
    end

    test "backoff raste eksponencijalno" do
      delays = Enum.map(0..4, &HTTP.retry_delay/1)

      assert delays == [1_000, 2_000, 4_000, 8_000, 16_000]
    end
  end

  describe "build_query/1" do
    test "bez bboxa pretražuje cijelu Hrvatsku" do
      query = HTTP.build_query()

      assert query =~ ~s(area["ISO3166-1"="HR"][admin_level=2]->.searchArea)
      assert query =~ "(area.searchArea)"
    end

    test "s bboxom pretražuje samo zadani pravokutnik" do
      query = HTTP.build_query(bbox: {43.49, 16.41, 43.52, 16.48})

      assert query =~ "(43.49,16.41,43.52,16.48)"
      refute query =~ "searchArea"
    end

    test "timeout se propagira u sam upit" do
      assert HTTP.build_query(timeout: 30) =~ "[out:json][timeout:30]"
    end
  end

  defp counting_stub(statuses) do
    counter = :counters.new(1, [])

    fn conn ->
      :counters.add(counter, 1, 1)
      index = min(:counters.get(counter, 1), length(statuses)) - 1

      case Enum.at(statuses, index) do
        200 -> json_fixture(conn, "beaches_split")
        status -> Plug.Conn.resp(conn, status, "busy")
      end
    end
  end
end
