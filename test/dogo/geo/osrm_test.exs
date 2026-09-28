defmodule Dogo.Geo.Routing.OSRMTest do
  @moduledoc "E5-S3. Testovi idu kroz `Req.Test` plug — nema mrežnih poziva."
  use ExUnit.Case, async: false

  @moduletag :capture_log

  alias Dogo.Geo.RouteCache
  alias Dogo.Geo.Routing
  alias Dogo.Geo.Routing.OSRM

  @origin %Geo.Point{coordinates: {16.4392, 43.5081}, srid: 4326}
  @bacvice %Geo.Point{coordinates: {16.4453, 43.5041}, srid: 4326}
  @znjan %Geo.Point{coordinates: {16.4700, 43.5015}, srid: 4326}

  # Stvarni oblik odgovora OSRM `table` servisa: prvi stupac je polaziste
  # prema samom sebi.
  @ok_body ~s({"code":"Ok","durations":[[0,205.3,432.1]],"distances":[[0,1216.3,3712.4]]})

  setup do
    RouteCache.clear()
    Req.Test.verify_on_exit!()
  end

  defp stub(body, status \\ 200) do
    counter = :counters.new(1, [])

    Req.Test.stub(OSRM, fn conn ->
      :counters.add(counter, 1, 1)
      send(self(), {:osrm_request, conn.request_path, conn.query_string})
      Plug.Conn.resp(conn, status, body)
    end)

    counter
  end

  describe "table/2" do
    test "vraća trajanje i duljinu za svako odredište" do
      stub(@ok_body)

      assert {:ok, [bacvice, znjan]} = OSRM.table(@origin, [@bacvice, @znjan])

      assert bacvice == %{duration_s: 205.3, distance_m: 1216.3}
      assert znjan == %{duration_s: 432.1, distance_m: 3712.4}
    end

    test "sva odredišta idu u jednom zahtjevu" do
      counter = stub(@ok_body)

      OSRM.table(@origin, [@bacvice, @znjan])

      assert :counters.get(counter, 1) == 1
      assert_received {:osrm_request, path, query}
      assert path =~ "16.439,43.508;16.445,43.504;16.47,43.502"
      assert URI.decode_query(query)["sources"] == "0"
    end

    test "koordinate se zaokružuju na tri decimale prije slanja" do
      stub(@ok_body)

      # Na ~110 m preciznosti: manje podataka o korisniku odlazi trecoj strani,
      # a odgovor na "koliko mi treba" se ne mijenja.
      OSRM.table(%Geo.Point{coordinates: {16.4392456, 43.5081789}, srid: 4326}, [@bacvice])

      assert_received {:osrm_request, path, _query}
      assert path =~ "16.439,43.508"
      refute path =~ "16.4392456"
    end

    test "odredište bez rute je nil, ostala prolaze" do
      stub(~s({"code":"Ok","durations":[[0,null,100]],"distances":[[0,null,2000]]}))

      assert {:ok, [nil, %{duration_s: 100.0}]} = OSRM.table(@origin, [@bacvice, @znjan])
    end

    test "prazan popis odredišta ne dira mrežu" do
      assert {:ok, []} = Routing.table(@origin, [])
    end

    test "OSRM greška se vraća pozivatelju" do
      stub(~s({"code":"NoRoute"}))

      assert {:error, {:osrm_error, "NoRoute"}} = OSRM.table(@origin, [@bacvice])
    end

    test "HTTP greška se vraća pozivatelju" do
      stub("busy", 503)

      assert {:error, {:http_error, 503}} = OSRM.table(@origin, [@bacvice])
    end

    test "prekid veze ne ruši klijenta" do
      Req.Test.stub(OSRM, &Req.Test.transport_error(&1, :econnrefused))

      assert {:error, %Req.TransportError{}} = OSRM.table(@origin, [@bacvice])
    end
  end

  describe "cache" do
    test "isti upit ne ide dvaput na mrežu" do
      counter = stub(@ok_body)

      assert {:ok, first} = OSRM.table(@origin, [@bacvice, @znjan])
      assert {:ok, second} = OSRM.table(@origin, [@bacvice, @znjan])

      assert first == second
      assert :counters.get(counter, 1) == 1
    end

    test "sitan pomak unutar zaokruživanja pogađa isti zapis" do
      counter = stub(@ok_body)

      OSRM.table(@origin, [@bacvice])
      OSRM.table(%Geo.Point{coordinates: {16.43921, 43.50812}, srid: 4326}, [@bacvice])

      assert :counters.get(counter, 1) == 1
    end

    test "drugi skup odredišta ide na mrežu" do
      counter = stub(@ok_body)

      OSRM.table(@origin, [@bacvice])
      OSRM.table(@origin, [@znjan])

      assert :counters.get(counter, 1) == 2
    end

    test "neuspjeh se ne cacheira" do
      counter = stub("busy", 503)

      assert {:error, _} = OSRM.table(@origin, [@bacvice])
      assert {:error, _} = OSRM.table(@origin, [@bacvice])

      assert :counters.get(counter, 1) == 2
    end
  end
end
