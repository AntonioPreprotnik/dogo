defmodule DogoWeb.DrivingTimeTest do
  @moduledoc """
  E5-S3: vrijeme vožnje stiže naknadno i nikad ne smije zadržati listu.
  """
  use DogoWeb.ConnCase, async: true

  # Jedan test namjerno rusi zadatak; njegov stack trace ne treba u izlazu.
  @moduletag :capture_log

  import Dogo.BeachesFixtures
  import Mox
  import Phoenix.LiveViewTest

  alias Dogo.RoutingMock

  setup :verify_on_exit!
  setup :set_mox_from_context

  @bounds %{
    "west" => 16.40,
    "south" => 43.48,
    "east" => 16.52,
    "north" => 43.54,
    "center_lon" => 16.45,
    "center_lat" => 43.505,
    "zoom" => 12.0
  }

  setup do
    beach_fixture(%{osm_id: "way/a", name: "Bliza", geom: point(16.4505, 43.5050)})
    beach_fixture(%{osm_id: "way/b", name: "Dalja", geom: point(16.4700, 43.5150)})
    :ok
  end

  defp leg(minutes, km), do: %{duration_s: minutes * 60.0, distance_m: km * 1000.0}

  test "lista se prikaže odmah sa zračnom udaljenošću", %{conn: conn} do
    # Rutiranje namjerno kasni; lista ne smije cekati na njega.
    expect(RoutingMock, :table, fn _origin, _dests ->
      Process.sleep(50)
      {:ok, [leg(3, 1.2), leg(7, 3.7)]}
    end)

    {:ok, view, _html} = live(conn, ~p"/")
    html = render_hook(view, "bounds_changed", @bounds)

    assert html =~ "Bliza"
    assert html =~ "≈"
    refute html =~ ~s(data-role="driving")

    # ...a zatim stigne i vrijeme voznje.
    html = render_async(view)

    assert html =~ "3 min"
    assert html =~ "7 min"
    refute html =~ "≈"
  end

  test "greška rutiranja ostavlja zračnu udaljenost s oznakom", %{conn: conn} do
    expect(RoutingMock, :table, fn _origin, _dests -> {:error, {:http_error, 503}} end)

    {:ok, view, _html} = live(conn, ~p"/")
    render_hook(view, "bounds_changed", @bounds)

    html = render_async(view)

    assert html =~ "Bliza"
    assert html =~ "≈"
    refute html =~ ~s(data-role="driving")
  end

  test "pad zadatka ne ruši stranicu", %{conn: conn} do
    expect(RoutingMock, :table, fn _origin, _dests -> raise "OSRM je pukao" end)

    {:ok, view, _html} = live(conn, ~p"/")
    render_hook(view, "bounds_changed", @bounds)

    assert render_async(view) =~ "Bliza"
  end

  test "traži se najviše deset plaža", %{conn: conn} do
    for i <- 1..15 do
      beach_fixture(%{osm_id: "way/m#{i}", geom: point(16.45 + i / 10_000, 43.505)})
    end

    expect(RoutingMock, :table, fn _origin, destinations ->
      assert length(destinations) == 10
      {:ok, List.duplicate(leg(5, 2.0), 10)}
    end)

    {:ok, view, _html} = live(conn, ~p"/")
    render_hook(view, "bounds_changed", @bounds)
    render_async(view)
  end

  test "isti vrh liste se ne pita dvaput", %{conn: conn} do
    expect(RoutingMock, :table, 1, fn _origin, _dests -> {:ok, [leg(3, 1.2), leg(7, 3.7)]} end)

    {:ok, view, _html} = live(conn, ~p"/")
    render_hook(view, "bounds_changed", @bounds)
    render_async(view)

    # Isti pogled, isti vrh liste: nema novog zahtjeva.
    render_hook(view, "bounds_changed", @bounds)
    render_async(view)
  end

  test "promjena vrha liste traži nove podatke", %{conn: conn} do
    expect(RoutingMock, :table, 2, fn _origin, _dests -> {:ok, [leg(3, 1.2)]} end)

    {:ok, view, _html} = live(conn, ~p"/")
    render_hook(view, "bounds_changed", @bounds)
    render_async(view)

    render_hook(view, "bounds_changed", %{
      @bounds
      | "west" => 16.44,
        "east" => 16.46,
        "south" => 43.50,
        "north" => 43.51
    })

    render_async(view)
  end

  test "prazan pogled ne zove rutiranje", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    render_hook(view, "bounds_changed", %{
      @bounds
      | "west" => 13.1,
        "east" => 13.2,
        "south" => 45.0,
        "north" => 45.1,
        "center_lon" => 13.15,
        "center_lat" => 45.05
    })
  end

  test "vrijeme se formatira u minutama i satima" do
    import DogoWeb.BeachComponents

    assert format_duration(59) == "1 min"
    assert format_duration(205.3) == "3 min"
    assert format_duration(3_600) == "1 h"
    assert format_duration(7_500) == "2 h 5 min"
    assert format_duration(nil) == nil
  end
end
