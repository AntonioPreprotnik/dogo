defmodule DogoWeb.DrivingSortTest do
  @moduledoc """
  E5-S4: lista se može poredati po vremenu vožnje umjesto po zračnoj
  udaljenosti. Zračno bliža plaža nije nužno i brža — to je cijela poanta.
  """
  use DogoWeb.ConnCase, async: true

  import Dogo.BeachesFixtures
  import Mox
  import Phoenix.LiveViewTest

  alias Dogo.RoutingMock
  alias DogoWeb.BeachFilters

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
    # Poluotok: zracno najbliza, ali cesta ide okolo.
    beach_fixture(%{osm_id: "way/a", name: "Poluotok", geom: point(16.4505, 43.5050)})
    beach_fixture(%{osm_id: "way/b", name: "Uvala", geom: point(16.4600, 43.5100)})
    beach_fixture(%{osm_id: "way/c", name: "Otocic", geom: point(16.4700, 43.5150)})
    :ok
  end

  defp leg(minutes), do: %{duration_s: minutes * 60.0, distance_m: minutes * 500.0}

  # Imena plaza redom kojim ih lista prikazuje.
  defp list_order(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(~s([data-role="beach-list-item"] .truncate))
    |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))
  end

  defp open(conn, path, legs) do
    stub(RoutingMock, :table, fn _origin, _dests -> legs end)

    {:ok, view, _html} = live(conn, path)
    render_hook(view, "bounds_changed", @bounds)
    render_async(view)

    # Pomak karte upisuje poziciju u URL; taj patch nije predmet testova.
    assert_patch(view)
    view
  end

  test "zadano je poredano po zračnoj udaljenosti", %{conn: conn} do
    view = open(conn, ~p"/", {:ok, [leg(12), leg(5), leg(3)]})

    assert list_order(view) == ["Poluotok", "Uvala", "Otocic"]
  end

  test "po vremenu vožnje najbrža plaža ide prva", %{conn: conn} do
    view = open(conn, ~p"/?sort=driving", {:ok, [leg(12), leg(5), leg(3)]})

    assert list_order(view) == ["Otocic", "Uvala", "Poluotok"]
  end

  test "plaža bez rute ide iza onih s poznatim vremenom", %{conn: conn} do
    view = open(conn, ~p"/?sort=driving", {:ok, [leg(12), nil, leg(3)]})

    assert list_order(view) == ["Otocic", "Poluotok", "Uvala"]
  end

  test "bez OSRM-a ostaje zračni poredak, uz objašnjenje", %{conn: conn} do
    view = open(conn, ~p"/?sort=driving", {:error, {:http_error, 503}})

    assert list_order(view) == ["Poluotok", "Uvala", "Otocic"]
    assert has_element?(view, ~s([data-role="sort-fallback"]))
  end

  test "s dostupnim vremenom nema objašnjenja", %{conn: conn} do
    view = open(conn, ~p"/?sort=driving", {:ok, [leg(12), leg(5), leg(3)]})

    refute has_element?(view, ~s([data-role="sort-fallback"]))
  end

  test "izbor redoslijeda ide u URL", %{conn: conn} do
    view = open(conn, ~p"/", {:ok, [leg(12), leg(5), leg(3)]})

    view |> form(~s([data-role="sort"]), %{"sort" => "driving"}) |> render_change()

    assert_patch(view) =~ "sort=driving"
    assert list_order(view) == ["Otocic", "Uvala", "Poluotok"]
  end

  test "promjena filtera ne vraća redoslijed na zadani", %{conn: conn} do
    view = open(conn, ~p"/?sort=driving", {:ok, [leg(12), leg(5), leg(3)]})

    render_change(view, "filter", %{"surface" => %{"sand" => "true"}})

    path = assert_patch(view)
    assert path =~ "sort=driving"
    assert path =~ "surface=sand"
  end

  test "brisanje filtera ne briše redoslijed", %{conn: conn} do
    view = open(conn, ~p"/?sort=driving&surface=sand", {:ok, []})

    render_click(view, "clear_filters", %{})

    path = assert_patch(view)
    assert path =~ "sort=driving"
    refute path =~ "surface"
  end

  test "OSRM se pita za iste plaže bez obzira na redoslijed", %{conn: conn} do
    test_pid = self()

    stub(RoutingMock, :table, fn _origin, dests ->
      send(test_pid, {:destinations, dests})
      {:ok, Enum.map(dests, fn _ -> leg(4) end)}
    end)

    {:ok, view, _html} = live(conn, ~p"/?sort=driving")
    render_hook(view, "bounds_changed", @bounds)
    render_async(view)

    assert_received {:destinations, dests}
    assert length(dests) == 3
  end

  describe "BeachFilters" do
    test "redoslijed se čita iz URL-a i piše natrag" do
      filters = BeachFilters.parse(%{"sort" => "driving"})

      assert filters.sort == :driving
      assert BeachFilters.to_params(filters) == %{"sort" => "driving"}
    end

    test "zadani redoslijed se ne piše u URL, a nepoznat pada na zadani" do
      assert BeachFilters.parse(%{}).sort == :distance
      assert BeachFilters.parse(%{"sort" => "name"}).sort == :distance
      assert BeachFilters.to_params(BeachFilters.parse(%{})) == %{}
    end

    test "redoslijed nije filter" do
      refute BeachFilters.active?(BeachFilters.parse(%{"sort" => "driving"}))
    end
  end
end
