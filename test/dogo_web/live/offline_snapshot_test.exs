defmodule DogoWeb.OfflineSnapshotTest do
  @moduledoc """
  E6-S3: nakon svake promjene liste server šalje sažetak koji preglednik
  sprema u IndexedDB i prikazuje kad socket nije dostupan.

  Sam prikaz radi JavaScript (assets/js/offline.js); ovdje se provjerava
  ugovor: što stiže, kojim redom, na kojem jeziku i čega u tome nema.
  """
  use DogoWeb.ConnCase, async: true

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
    beach_fixture(%{
      osm_id: "way/a",
      name: "Bliza",
      geom: point(16.4505, 43.5050),
      dog_status: :allowed,
      surface: :pebble
    })

    beach_fixture(%{osm_id: "way/b", name: "Dalja", geom: point(16.4700, 43.5150)})
    :ok
  end

  defp leg(minutes), do: %{duration_s: minutes * 60.0, distance_m: minutes * 500.0}

  defp names(%{beaches: beaches}), do: Enum.map(beaches, & &1.name)

  # Pomak karte salje sazetak vise puta (i patch pozicije ponovno osvjezi
  # listu); preglednik cuva zadnji, pa i test gleda zadnji.
  defp last_snapshot(last \\ nil) do
    receive do
      {_ref, {:push_event, "offline_snapshot", payload}} -> last_snapshot(payload)
    after
      0 -> last
    end
  end

  test "stiže čim se lista prikaže, sa zračnom udaljenošću i prevedenim tekstom", %{conn: conn} do
    stub(RoutingMock, :table, fn _, _ -> {:error, :unavailable} end)

    {:ok, view, _html} = live(conn, ~p"/")
    render_hook(view, "bounds_changed", @bounds)

    assert_push_event(view, "offline_snapshot", snapshot)

    assert names(snapshot) == ["Bliza", "Dalja"]
    assert [bliza | _] = snapshot.beaches
    assert bliza.details == "Psi dozvoljeni · Šljunak"
    assert bliza.distance =~ ~r/^≈ \d+ m$/

    assert bliza.navigate_url =~
             "https://www.google.com/maps/dir/?api=1&destination=43.505,16.4505"

    assert snapshot.labels.offline == "Izvan mreže"
    assert snapshot.labels.saved_at =~ "%{time}"
  end

  test "kad stigne vrijeme vožnje, šalje se ponovno, s njim", %{conn: conn} do
    stub(RoutingMock, :table, fn _, _ -> {:ok, [leg(12), leg(3)]} end)

    {:ok, view, _html} = live(conn, ~p"/")
    render_hook(view, "bounds_changed", @bounds)
    render_async(view)
    snapshot = last_snapshot()

    assert [%{distance: "12 min · " <> _}, %{distance: "3 min · " <> _}] = snapshot.beaches
  end

  test "prati odabrani redoslijed", %{conn: conn} do
    stub(RoutingMock, :table, fn _, _ -> {:ok, [leg(12), leg(3)]} end)

    {:ok, view, _html} = live(conn, ~p"/?sort=driving")
    render_hook(view, "bounds_changed", @bounds)
    render_async(view)

    assert names(last_snapshot()) == ["Dalja", "Bliza"]
  end

  test "prazna lista ne briše zadnje korisne rezultate", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    # Pucina: nijedne plaze u pogledu.
    render_hook(view, "bounds_changed", %{
      @bounds
      | "west" => 15.0,
        "east" => 15.1,
        "south" => 42.5,
        "north" => 42.6,
        "center_lon" => 15.05,
        "center_lat" => 42.55
    })

    refute_push_event(view, "offline_snapshot", _)
  end

  test "ne sadrži korisnikovu lokaciju", %{conn: conn} do
    stub(RoutingMock, :table, fn _, _ -> {:ok, [leg(4), leg(6)]} end)

    {:ok, view, _html} = live(conn, ~p"/")
    render_hook(view, "user_located", %{"location" => %{"lat" => 43.50417, "lon" => 16.44531}})
    render_hook(view, "bounds_changed", @bounds)
    render_async(view)

    payload = inspect(last_snapshot())
    assert payload =~ "Bliza"
    refute payload =~ "43.504"
    refute payload =~ "16.445"
  end

  test "stranica ima skriveni kontejner koji LiveView ne dira", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, ~s(#offline-results[hidden][phx-update="ignore"]))
  end
end
