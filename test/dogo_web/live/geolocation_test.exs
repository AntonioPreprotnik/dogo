defmodule DogoWeb.GeolocationTest do
  @moduledoc """
  E4-S1. Naglasak je na zahtjevu iz storyja: lokacija se ne sprema i ne
  završava u logovima.
  """
  use DogoWeb.ConnCase, async: true

  import Dogo.BeachesFixtures
  import Phoenix.LiveViewTest

  @bounds %{
    "west" => 16.40,
    "south" => 43.48,
    "east" => 16.52,
    "north" => 43.54,
    "center_lon" => 16.51,
    "center_lat" => 43.535,
    "zoom" => 12.0
  }

  # Korisnik je kod Bačvica, daleko od sredine gornjeg pravokutnika.
  @user %{"location" => %{"lat" => 43.5041, "lon" => 16.4453}}

  setup do
    beach_fixture(%{
      osm_id: "way/uz-korisnika",
      name: "Uz korisnika",
      geom: point(16.4460, 43.5045)
    })

    beach_fixture(%{osm_id: "way/uz-sredinu", name: "Uz sredinu", geom: point(16.5105, 43.5355)})
    :ok
  end

  defp listed(view) do
    html = render(view)

    for name <- ["Uz korisnika", "Uz sredinu"], String.contains?(html, name), do: name
  end

  # Imena plaža redoslijedom kojim se pojavljuju u listi.
  defp order(view) do
    html = render(view)

    ["Uz korisnika", "Uz sredinu"]
    |> Enum.map(fn name -> {elem(:binary.match(html, name), 0), name} end)
    |> Enum.sort()
    |> Enum.map(&elem(&1, 1))
  end

  describe "referentna točka" do
    test "bez lokacije se mjeri od sredine karte", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_hook(view, "bounds_changed", @bounds)

      assert render(view) =~ "Najbliže sredini karte"
      assert listed(view) == ["Uz korisnika", "Uz sredinu"]
      assert order(view) == ["Uz sredinu", "Uz korisnika"]
    end

    test "s lokacijom se mjeri od korisnika", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_hook(view, "bounds_changed", @bounds)
      render_hook(view, "user_located", @user)

      assert render(view) =~ "Najbliže tebi"
      assert order(view) == ["Uz korisnika", "Uz sredinu"]
    end

    test "lokacija stigla prije granica karte ne ruši ništa", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert render_hook(view, "user_located", @user)
      assert render_hook(view, "bounds_changed", @bounds) =~ "Najbliže tebi"
    end

    test "neispravan payload ne postavlja lokaciju", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_hook(view, "bounds_changed", @bounds)
      render_hook(view, "user_located", %{"location" => %{"lat" => "sjever", "lon" => nil}})

      assert render(view) =~ "Najbliže sredini karte"
    end
  end

  describe "odbijena lokacija" do
    test "odbijanje objasni sto se dogodilo", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      html = render_hook(view, "geolocation_error", %{"reason" => "denied"})

      assert html =~ "Bez tvoje lokacije"
      assert html =~ "Najbliže sredini karte"
    end

    test "preglednik bez geolokacije dobije svoju poruku", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert render_hook(view, "geolocation_error", %{"reason" => "unavailable"}) =~ "ne nudi lokaciju"
    end

    test "bez odbijanja nema nikakve poruke", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/")

      refute html =~ "Bez tvoje lokacije"
      refute has_element?(view, ~s([data-role="geolocation-notice"]))
    end
  end
end
