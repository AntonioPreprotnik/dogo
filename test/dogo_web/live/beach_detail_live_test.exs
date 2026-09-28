defmodule DogoWeb.BeachDetailLiveTest do
  use DogoWeb.ConnCase, async: true

  import Dogo.BeachesFixtures
  import Phoenix.LiveViewTest

  describe "prikaz plaže" do
    setup do
      beach =
        beach_fixture(%{
          osm_id: "way/84533701",
          name: "Plaža Ježinac",
          municipality: "Split",
          geom: point(16.4166951, 43.5035702),
          surface: :pebble,
          dog_status: :designated,
          dog_status_source: :osm,
          amenities: %{"water" => true, "shade" => false, "dog_shower" => true}
        })

      %{beach: beach}
    end

    test "prikazuje naziv, općinu i podlogu", %{conn: conn, beach: beach} do
      {:ok, _view, html} = live(conn, ~p"/beaches/#{beach.id}")

      assert html =~ "Plaža Ježinac"
      assert html =~ "Split"
      assert html =~ "Šljunak"
      assert html =~ "way/84533701"
    end

    test "prikazuje status za pse zajedno s izvorom", %{conn: conn, beach: beach} do
      {:ok, _view, html} = live(conn, ~p"/beaches/#{beach.id}")

      assert html =~ "Plaža za pse"
      assert html =~ "iz OSM-a"
      assert html =~ ~s(data-source="osm")
    end

    test "generirani status je označen kao generiran", %{conn: conn} do
      beach = beach_fixture(%{osm_id: "way/gen", dog_status_source: :generated})

      {:ok, _view, html} = live(conn, ~p"/beaches/#{beach.id}")

      assert html =~ "generirano"
    end

    test "sadržaji se prikazuju i kad ih nema", %{conn: conn, beach: beach} do
      {:ok, view, _html} = live(conn, ~p"/beaches/#{beach.id}")

      assert has_element?(view, ~s([data-amenity="water"][data-present="true"]))
      assert has_element?(view, ~s([data-amenity="dog_shower"][data-present="true"]))
      assert has_element?(view, ~s([data-amenity="shade"][data-present="false"]))
      # Sadržaj koji uopće nije u mapi tretira se kao "nema".
      assert has_element?(view, ~s([data-amenity="parking"][data-present="false"]))
    end

    test "plaža bez imena ima zamjenski naslov", %{conn: conn} do
      beach = beach_fixture(%{osm_id: "way/noname", name: nil})

      {:ok, _view, html} = live(conn, ~p"/beaches/#{beach.id}")

      assert html =~ "Plaža bez imena"
    end
  end

  describe "navigacija" do
    setup do
      %{beach: beach_fixture(%{osm_id: "way/nav", geom: point(16.4166951, 43.5035702)})}
    end

    test "Google Maps link nosi koordinate kao odredište", %{conn: conn, beach: beach} do
      {:ok, view, _html} = live(conn, ~p"/beaches/#{beach.id}")

      assert view
             |> element(~s([data-role="navigate-google"]))
             |> render() =~ "destination=43.5035702,16.4166951"
    end

    test "Apple Maps link nosi iste koordinate", %{conn: conn, beach: beach} do
      {:ok, view, _html} = live(conn, ~p"/beaches/#{beach.id}")

      assert view
             |> element(~s([data-role="navigate-apple"]))
             |> render() =~ "daddr=43.5035702,16.4166951"
    end
  end

  describe "mini karta" do
    test "nosi hook, ignore i boju po statusu", %{conn: conn} do
      beach = beach_fixture(%{osm_id: "way/mini", dog_status: :not_allowed})

      {:ok, _view, html} = live(conn, ~p"/beaches/#{beach.id}")

      assert html =~ ~s(phx-hook="BeachMiniMap")
      assert html =~ ~s(phx-update="ignore")
      assert html =~ "e11d48"
    end
  end

  test "nepostojeća plaža vraća 404", %{conn: conn} do
    assert_raise Ecto.NoResultsError, fn -> live(conn, ~p"/beaches/999999") end
  end
end
