defmodule Dogo.TelemetryTest do
  @moduledoc """
  E7-S4: prostorni upiti i pozivi vanjskim servisima emitiraju telemetry
  evente — bez koordinata u metapodacima.
  """
  # RouteCache je globalan (ETS), a OSRM test ga cisti.
  use Dogo.DataCase, async: false

  @moduletag :capture_log

  import Dogo.BeachesFixtures

  alias Dogo.Beaches
  alias Dogo.Geo.RouteCache
  alias Dogo.Geo.Routing.OSRM
  alias Dogo.Import.Overpass.HTTP, as: Overpass

  @events [
    [:dogo, :beaches, :query, :stop],
    [:dogo, :external, :request, :stop]
  ]

  @split %Geo.Point{coordinates: {16.4392, 43.5081}, srid: 4326}

  setup do
    test_pid = self()
    handler_id = "telemetry-test-#{inspect(test_pid)}"

    # Handler se izvrsava u procesu koji emitira event; drugi testovi koji
    # paralelno rade upite ne smiju zavrsiti u ovom sanducicu.
    :telemetry.attach_many(
      handler_id,
      @events,
      fn event, measurements, metadata, _config ->
        if self() == test_pid, do: send(test_pid, {:event, event, measurements, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)
    :ok
  end

  describe "prostorni upiti" do
    setup do
      %{beach: beach_fixture(%{osm_id: "way/1", geom: point(16.4453, 43.5041)})}
    end

    test "nearest mjeri trajanje i bilježi naziv upita" do
      Beaches.nearest(@split)

      assert_received {:event, [:dogo, :beaches, :query, :stop], %{duration: duration}, meta}
      assert is_integer(duration) and duration > 0
      assert meta.query == :nearest
    end

    test "within_bbox i cluster_in_bbox imaju svoj naziv" do
      bbox = {16.40, 43.48, 16.52, 43.54}

      Beaches.within_bbox(bbox, near: @split)
      Beaches.cluster_in_bbox(bbox)

      assert_received {:event, _, _, %{query: :within_bbox}}
      assert_received {:event, _, _, %{query: :cluster_in_bbox}}
    end

    test "metapodaci ne sadrže koordinate" do
      Beaches.within_bbox({16.40, 43.48, 16.52, 43.54}, near: @split)

      assert_received {:event, _, _, meta}
      refute inspect(meta) =~ "43.5081"
      refute inspect(meta) =~ "16.4392"
    end

    test "upit vraća isti rezultat kao bez mjerenja", %{beach: %{id: id}} do
      assert [%{id: ^id}] = Beaches.nearest(@split)
      assert {:ok, [%{id: ^id}]} = Beaches.within_bbox({16.40, 43.48, 16.52, 43.54})
    end
  end

  describe "vanjski servisi" do
    setup do
      RouteCache.clear()
      Req.Test.verify_on_exit!()
    end

    test "uspješan OSRM poziv ima result: :ok" do
      Req.Test.stub(OSRM, fn conn ->
        Plug.Conn.resp(conn, 200, ~s({"code":"Ok","durations":[[0,60]],"distances":[[0,500]]}))
      end)

      OSRM.table(@split, [point(16.4453, 43.5041)])

      assert_received {:event, [:dogo, :external, :request, :stop], _, meta}
      assert meta.service == :osrm
      assert meta.result == :ok
    end

    test "neuspješan OSRM poziv ima result: :error" do
      Req.Test.stub(OSRM, &Plug.Conn.resp(&1, 503, "busy"))

      OSRM.table(@split, [point(16.4453, 43.5041)])

      assert_received {:event, _, _, %{service: :osrm, result: :error}}
    end

    test "pogodak u cacheu nije poziv servisu" do
      Req.Test.stub(OSRM, fn conn ->
        Plug.Conn.resp(conn, 200, ~s({"code":"Ok","durations":[[0,60]],"distances":[[0,500]]}))
      end)

      OSRM.table(@split, [point(16.4453, 43.5041)])
      OSRM.table(@split, [point(16.4453, 43.5041)])

      assert_received {:event, _, _, %{service: :osrm}}
      refute_received {:event, _, _, %{service: :osrm}}
    end

    test "Overpass se bilježi kao zaseban servis" do
      Req.Test.stub(Overpass, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"elements":[]}))
      end)

      Overpass.fetch_beaches()

      assert_received {:event, _, _, %{service: :overpass, result: :ok}}
    end

    test "metapodaci ne sadrže polazište rute" do
      Req.Test.stub(OSRM, &Plug.Conn.resp(&1, 503, "busy"))

      OSRM.table(@split, [point(16.4453, 43.5041)])

      assert_received {:event, _, _, meta}
      refute inspect(meta) =~ "16.439"
    end
  end

  describe "DogoWeb.Telemetry.metrics/0" do
    test "sadrži metrike domene i uvoza" do
      names = Enum.map(DogoWeb.Telemetry.metrics(), &Enum.join(&1.name, "."))

      assert "dogo.beaches.query.stop.duration" in names
      assert "dogo.external.request.stop.duration" in names
      assert "oban.job.stop.duration" in names
    end
  end
end
