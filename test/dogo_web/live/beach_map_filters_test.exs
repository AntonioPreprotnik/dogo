defmodule DogoWeb.BeachMapFiltersTest do
  @moduledoc "E3-S6: filteri i pozicija karte žive u URL-u."
  use DogoWeb.ConnCase, async: true

  import Dogo.BeachesFixtures
  import Phoenix.LiveViewTest

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
      osm_id: "way/za-pse",
      name: "Za pse",
      geom: point(16.4505, 43.5050),
      dog_status: :designated,
      surface: :sand,
      amenities: %{"water" => true, "shade" => true}
    })

    beach_fixture(%{
      osm_id: "way/zabranjeno",
      name: "Zabranjeno",
      geom: point(16.4600, 43.5100),
      dog_status: :not_allowed,
      surface: :pebble,
      amenities: %{"water" => false}
    })

    beach_fixture(%{
      osm_id: "way/daleko",
      name: "Daleko",
      geom: point(16.5100, 43.5350),
      dog_status: :allowed,
      surface: :rock,
      amenities: %{}
    })

    :ok
  end

  defp listed(view) do
    html = render(view)

    for name <- ["Za pse", "Zabranjeno", "Daleko"], String.contains?(html, name), do: name
  end

  describe "filteri iz URL-a" do
    test "bez filtera se vide sve plaže", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_hook(view, "bounds_changed", @bounds)

      assert listed(view) == ["Za pse", "Zabranjeno", "Daleko"]
    end

    test "status za pse se primjenjuje već na prvi upit", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?dog=designated")
      render_hook(view, "bounds_changed", @bounds)

      assert listed(view) == ["Za pse"]
    end

    test "podloga i sadržaji se kombiniraju", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?surface=sand,pebble&amenities=water")
      render_hook(view, "bounds_changed", @bounds)

      assert listed(view) == ["Za pse"]
    end

    test "radijus reže po stvarnoj udaljenosti od sredine karte", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?radius=5000")
      render_hook(view, "bounds_changed", @bounds)

      assert listed(view) == ["Za pse", "Zabranjeno"]
    end

    test "neispravan filter daje prazan filter, ne grešku", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?dog=izmisljeno&radius=999")
      render_hook(view, "bounds_changed", @bounds)

      assert listed(view) == ["Za pse", "Zabranjeno", "Daleko"]
    end

    test "prazan rezultat zbog filtera ima drugu poruku", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?dog=designated&surface=rock")
      html = render_hook(view, "bounds_changed", @bounds)

      assert html =~ "ne odgovara filterima"
    end
  end

  describe "pozicija karte iz URL-a" do
    test "karta se otvara na poziciji iz linka", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/?lat=43.51&lon=16.44&zoom=13.5")

      assert html =~ ~s(&quot;lat&quot;:43.51)
      assert html =~ ~s(&quot;lon&quot;:16.44)
      assert html =~ ~s(&quot;zoom&quot;:13.5)
    end

    test "bez pozicije se otvara cijeli Jadran", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ ~s(&quot;zoom&quot;:7)
    end

    test "smeće u poziciji pada natrag na zadano", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/?lat=daleko&zoom=")

      assert html =~ ~s(&quot;lat&quot;:43.7)
      assert html =~ ~s(&quot;zoom&quot;:7)
    end

    test "pomak karte upisuje poziciju u URL", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?dog=allowed")

      render_hook(view, "bounds_changed", @bounds)

      assert_patched(view, "/?dog=allowed&lat=43.505&lon=16.45&zoom=12.0")
    end
  end

  describe "promjena filtera" do
    test "upisuje se u URL", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_hook(view, "bounds_changed", @bounds)

      view
      |> form("form[phx-change=filter]")
      |> render_change(%{"dog" => %{"designated" => "true"}})

      # Zoom mora prezivjeti promjenu filtera: bez njega isti link u novoj
      # kartici otvara drugi pogled.
      assert_patched(view, "/?dog=designated&lat=43.505&lon=16.45&zoom=12.0")
      assert listed(view) == ["Za pse"]
    end

    test "čišćenje filtera prazni URL", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?dog=designated")
      render_hook(view, "bounds_changed", @bounds)

      view |> element("button", "Očisti filtere") |> render_click()

      assert_patched(view, "/?lat=43.505&lon=16.45&zoom=12.0")
      assert listed(view) == ["Za pse", "Zabranjeno", "Daleko"]
    end

    test "gumb za čišćenje se pojavljuje tek kad filter postoji", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      refute has_element?(view, "button", "Očisti filtere")

      {:ok, view, _html} = live(conn, ~p"/?dog=allowed")
      assert has_element?(view, "button", "Očisti filtere")
    end
  end

  describe "djeljivost" do
    test "URL nakon promjene filtera sadrzi i poziciju i zoom", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_hook(view, "bounds_changed", @bounds)
      # Pomak karte i sam patcha URL; taj patch prvo potrosimo.
      assert_patch(view)

      view
      |> form("form[phx-change=filter]")
      |> render_change(%{"surface" => %{"sand" => "true"}})

      path = assert_patch(view)
      assert path =~ "surface=sand"
      assert path =~ "lat=43.505"
      assert path =~ "lon=16.45"
      assert path =~ "zoom=12.0"
    end

    test "isti link u novoj sesiji daje isti prikaz", %{conn: conn} do
      url = ~p"/?dog=designated&surface=sand&amenities=water&lat=43.51&lon=16.44&zoom=13"

      {:ok, first, _html} = live(conn, url)
      render_hook(first, "bounds_changed", @bounds)

      {:ok, second, second_html} = live(build_conn(), url)
      render_hook(second, "bounds_changed", @bounds)

      assert listed(first) == listed(second)
      assert second_html =~ ~s(&quot;zoom&quot;:13.0)
      assert has_element?(second, "button", "Očisti filtere")
    end
  end
end
