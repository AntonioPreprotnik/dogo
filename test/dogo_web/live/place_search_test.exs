defmodule DogoWeb.PlaceSearchTest do
  @moduledoc "E4-S2: kad korisnik odbije lokaciju, mjesto se upisuje ručno."
  use DogoWeb.ConnCase, async: true

  import Dogo.BeachesFixtures
  import Mox
  import Phoenix.LiveViewTest

  alias Dogo.Geo.Place
  alias Dogo.GeocoderMock

  setup :verify_on_exit!
  setup :set_mox_from_context

  @split %Place{
    name: "Split",
    description: "Splitsko-dalmatinska županija, Hrvatska",
    point: %Geo.Point{coordinates: {16.4399659, 43.5116383}, srid: 4326}
  }

  defp deny_location(view) do
    render_hook(view, "geolocation_denied", %{"code" => 1})
    view
  end

  defp search(view, query) do
    view
    |> form("form[phx-change=search_place]")
    |> render_change(%{"q" => query})
  end

  describe "kada se polje pojavljuje" do
    test "nakon odbijene geolokacije", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/")

      refute html =~ "Upiši mjesto"

      assert deny_location(view) |> render() =~ "Upiši mjesto"
      assert has_element?(view, ~s([data-role="place-fallback"] input[name="q"]))
    end

    test "i kad preglednik uopće ne nudi lokaciju", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert render_hook(view, "geolocation_unavailable", %{}) =~ "Upiši mjesto"
    end

    test "ne pojavljuje se ako je lokacija dobivena", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "user_located", %{"location" => %{"lat" => 43.5, "lon" => 16.44}})

      refute has_element?(view, ~s([data-role="place-fallback"]))
    end
  end

  describe "pretraga" do
    setup %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      %{view: deny_location(view)}
    end

    test "prekratak upit ne ide na geokoder", %{view: view} do
      # Bez `expect` — svaki poziv mocka bi ovdje srušio test.
      search(view, "sp")

      refute has_element?(view, ~s([data-role="place-result"]))
    end

    test "nudi pronađena mjesta", %{view: view} do
      expect(GeocoderMock, :search, fn "Split" -> {:ok, [@split]} end)

      search(view, "Split")
      render_async(view)

      assert has_element?(view, ~s([data-role="place-result"]), "Split")
      assert render(view) =~ "Splitsko-dalmatinska"
    end

    test "prazan rezultat se objasni", %{view: view} do
      expect(GeocoderMock, :search, fn _ -> {:ok, []} end)

      search(view, "Xyzzy")

      assert render_async(view) =~ "Nema mjesta s tim imenom"
    end

    test "greška geokodera ne ruši stranicu", %{view: view} do
      expect(GeocoderMock, :search, fn _ -> {:error, {:http_error, 429}} end)

      search(view, "Split")

      assert render_async(view) =~ "Pretraga mjesta trenutno ne radi"
      assert has_element?(view, "#beach-map")
    end

    test "rušenje pretrage ne ruši LiveView", %{view: view} do
      expect(GeocoderMock, :search, fn _ -> raise "Nominatim je pukao" end)

      search(view, "Split")

      assert render_async(view) =~ "Pretraga mjesta trenutno ne radi"
    end
  end

  describe "odabir mjesta" do
    setup %{conn: conn} do
      beach_fixture(%{osm_id: "way/split", name: "Bačvice", geom: point(16.4453, 43.5041)})

      {:ok, view, _html} = live(conn, ~p"/")
      view = deny_location(view)

      expect(GeocoderMock, :search, fn _ -> {:ok, [@split]} end)
      search(view, "Split")
      render_async(view)

      %{view: view}
    end

    test "karta odleti na odabrano mjesto", %{view: view} do
      view |> element(~s([data-role="place-result"])) |> render_click()

      assert_push_event(view, "fly_to", %{lon: 16.4399659, lat: 43.5116383, zoom: zoom})
      assert zoom > 7
    end

    test "nakon odabira se popis i upit čiste", %{view: view} do
      html = view |> element(~s([data-role="place-result"])) |> render_click()

      refute html =~ ~s(data-role="place-result")
      assert html =~ ~s(value="")
    end
  end
end
