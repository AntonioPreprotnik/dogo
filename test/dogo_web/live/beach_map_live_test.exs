defmodule DogoWeb.BeachMapLiveTest do
  use DogoWeb.ConnCase, async: true

  import Dogo.BeachesFixtures
  import Phoenix.LiveViewTest

  alias Dogo.Beaches
  alias Dogo.Repo

  # Bbox oko Splita.
  @bounds %{
    "west" => 16.40,
    "south" => 43.48,
    "east" => 16.50,
    "north" => 43.53,
    "center_lon" => 16.45,
    "center_lat" => 43.505,
    "zoom" => 12
  }

  describe "kontejner karte" do
    test "nosi hook i phx-update=ignore, da ga LiveView ne pregazi", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ ~s(id="beach-map")
      assert html =~ ~s(phx-hook="BeachMap")
      assert html =~ ~s(phx-update="ignore")
    end

    test "konfiguracija karte stiže klijentu kao data atribut", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "tiles.openfreemap.org"
      assert html =~ "styleUrl"
      assert html =~ "center"
    end
  end

  describe "bounds_changed" do
    setup do
      beach_fixture(%{osm_id: "way/in-1", name: "Bačvice", geom: point(16.4453, 43.5041)})
      beach_fixture(%{osm_id: "way/in-2", name: "Žnjan", geom: point(16.4700, 43.5015)})
      beach_fixture(%{osm_id: "way/out", name: "Dubrovnik", geom: point(18.0944, 42.6507)})
      :ok
    end

    test "server vraća GeoJSON samo za vidljivi dio karte", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "bounds_changed", @bounds)

      assert_push_event(view, "beaches", %{geojson: geojson})
      assert geojson.type == "FeatureCollection"

      names = Enum.map(geojson.features, & &1.properties.name)
      assert Enum.sort(names) == ["Bačvice", "Žnjan"]
    end

    test "feature ima koordinate u GeoJSON redoslijedu [lon, lat]", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "bounds_changed", @bounds)
      assert_push_event(view, "beaches", %{geojson: geojson})

      feature = Enum.find(geojson.features, &(&1.properties.name == "Bačvice"))

      assert feature.geometry == %{type: "Point", coordinates: [16.4453, 43.5041]}
    end

    test "feature nosi status za pse i njegov izvor", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "bounds_changed", @bounds)
      assert_push_event(view, "beaches", %{geojson: geojson})

      properties = hd(geojson.features).properties

      assert properties.dog_status in Beaches.Beach.dog_statuses()
      assert properties.dog_status_source in [:osm, :generated]
    end

    test "broj vidljivih plaža se prikazuje", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert render_hook(view, "bounds_changed", @bounds) =~ "Vidljivo: 2"
    end

    test "prazan pogled ne puca", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      html =
        render_hook(view, "bounds_changed", %{
          @bounds
          | "west" => 13.1,
            "east" => 13.2,
            "south" => 45.0,
            "north" => 45.1,
            "center_lon" => 13.15,
            "center_lat" => 45.05
        })

      assert html =~ "Vidljivo: 0"
      assert_push_event(view, "beaches", %{geojson: %{features: []}})
    end

    test "event bez centra pada natrag na sredinu pravokutnika", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      html =
        render_hook(view, "bounds_changed", %{
          "west" => 16.40,
          "south" => 43.48,
          "east" => 16.50,
          "north" => 43.53,
          "zoom" => 12
        })

      assert html =~ "Vidljivo: 2"
      assert_push_event(view, "beaches", %{geojson: %{features: [_, _]}})
    end
  end

  describe "lista rezultata" do
    setup do
      # Namjerno upisane obrnutim redoslijedom od ocekivanog.
      beach_fixture(%{osm_id: "way/daleko", name: "Daleko", geom: point(16.4900, 43.5290)})
      beach_fixture(%{osm_id: "way/blizu", name: "Blizu", geom: point(16.4505, 43.5050)})
      beach_fixture(%{osm_id: "way/srednje", name: "Srednje", geom: point(16.4700, 43.5150)})
      :ok
    end

    test "poredana je po udaljenosti od sredine karte", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_hook(view, "bounds_changed", @bounds)

      html = render(view)

      positions = Enum.map(["Blizu", "Srednje", "Daleko"], &index_of(html, &1))

      assert Enum.all?(positions, &is_integer/1)
      assert positions == Enum.sort(positions)
    end

    test "stavka bez imena se razlikuje po podlozi", %{conn: conn} do
      beach_fixture(%{
        osm_id: "way/bezimena",
        name: nil,
        surface: :rock,
        geom: point(16.4510, 43.5055)
      })

      {:ok, view, _html} = live(conn, ~p"/")
      render_hook(view, "bounds_changed", @bounds)

      beach = Beaches.get_beach_by_osm_id(osm_id("way/bezimena"))

      html = view |> element(~s([data-beach-id="#{beach.id}"])) |> render()

      assert html =~ "Plaža bez imena"
      assert html =~ "Stijene"
    end

    test "svaka stavka prikazuje udaljenost", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_hook(view, "bounds_changed", @bounds)

      beach = Beaches.get_beach_by_osm_id(osm_id("way/blizu"))

      assert view
             |> element(~s([data-beach-id="#{beach.id}"] [data-role="distance"]))
             |> render() =~ ~r/\d+ m/
    end

    test "prazan pogled objasni sto napraviti", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      html =
        render_hook(view, "bounds_changed", %{
          @bounds
          | "west" => 13.1,
            "south" => 45.0,
            "east" => 13.2,
            "north" => 45.1,
            "center_lon" => 13.15,
            "center_lat" => 45.05
        })

      assert html =~ "Nema plaža u ovom dijelu karte"
    end

    test "klik na stavku posalje karti fly_to na tu plazu", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_hook(view, "bounds_changed", @bounds)

      beach = Beaches.get_beach_by_osm_id(osm_id("way/srednje"))

      view
      |> element(~s([data-beach-id="#{beach.id}"]))
      |> render_click()

      assert_push_event(view, "fly_to", %{lon: 16.47, lat: 43.515, zoom: zoom})
      assert zoom > 12
    end

    test "odabrana stavka je oznacena i nudi link na detalj", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_hook(view, "bounds_changed", @bounds)

      beach = Beaches.get_beach_by_osm_id(osm_id("way/blizu"))

      html = view |> element(~s([data-beach-id="#{beach.id}"])) |> render_click()

      assert html =~ ~s(aria-current="true")
      assert html =~ ~p"/beaches/#{beach.id}"
    end

    test "klik na plazu koja vise nije u pogledu se ignorira", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_hook(view, "bounds_changed", @bounds)

      assert render_click(view, "select_beach", %{"id" => "999999"})
      refute_push_event(view, "fly_to", %{})
    end
  end

  describe "previše plaža za zoom" do
    test "iznad tvrdog limita upozorava i reže rezultat", %{conn: conn} do
      # Stvarno prekoračimo limit od 500, umjesto da ga smanjujemo za test —
      # inače ne bismo testirali prag koji aplikacija stvarno koristi.
      over_limit = Beaches.bbox_limit() + 1
      now = DateTime.utc_now(:second)

      rows =
        for i <- 1..over_limit do
          %{
            osm_id: "way/bulk-#{i}",
            name: "Plaža #{i}",
            geom: point(16.41 + rem(i, 80) / 10_000, 43.49 + div(i, 80) / 10_000),
            surface: :pebble,
            dog_status: :unknown,
            dog_status_source: :generated,
            amenities: %{},
            inserted_at: now,
            updated_at: now
          }
        end

      Repo.insert_all(Beaches.Beach, rows)

      {:ok, view, _html} = live(conn, ~p"/")

      html = render_hook(view, "bounds_changed", @bounds)

      assert html =~ "Previše plaža za ovaj zoom"
      assert html =~ "prikazano prvih #{Beaches.bbox_limit()}"

      assert_push_event(view, "beaches", %{geojson: geojson})
      assert length(geojson.features) == Beaches.bbox_limit()
    end
  end

  defp index_of(html, needle) do
    case :binary.match(html, needle) do
      {position, _length} -> position
      :nomatch -> nil
    end
  end
end
