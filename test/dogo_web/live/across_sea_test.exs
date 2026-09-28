defmodule DogoWeb.AcrossSeaTest do
  @moduledoc "E5-S2: oznaka 'preko mora' i filter bez trajekta."
  use DogoWeb.ConnCase, async: true

  import Dogo.BeachesFixtures
  import Ecto.Query
  import Phoenix.LiveViewTest

  alias Dogo.Geo.Island
  alias Dogo.Import.Islands, as: Import
  alias Dogo.Import.Overpass.IslandElement
  alias Dogo.Repo

  @bounds %{
    "west" => 15.90,
    "south" => 42.90,
    "east" => 16.60,
    "north" => 43.60,
    "center_lon" => 16.25,
    "center_lat" => 43.25,
    "zoom" => 10.0
  }

  defp square(osm_id, name, lon, lat) do
    corners = [
      {lon, lat},
      {lon + 0.1, lat},
      {lon + 0.1, lat + 0.1},
      {lon, lat + 0.1},
      {lon, lat}
    ]

    lines = corners |> Enum.chunk_every(2, 1, :discard) |> Enum.map(&Enum.to_list/1)
    %IslandElement{osm_id: osm_id, name: name, lines: lines}
  end

  setup do
    Import.store([
      square("relation/most", "S mostom", 16.0, 43.0),
      square("relation/trajekt", "Bez mosta", 16.4, 43.4)
    ])

    Repo.update_all(
      from(i in Island, where: i.name == "S mostom"),
      set: [bridge_connected: true]
    )

    beach_fixture(%{osm_id: "way/kopno", name: "Kopnena", geom: point(16.25, 43.20)})
    beach_fixture(%{osm_id: "way/most", name: "Mostovna", geom: point(16.05, 43.05)})
    beach_fixture(%{osm_id: "way/trajekt", name: "Trajektna", geom: point(16.45, 43.45)})

    Import.assign_beaches()
    :ok
  end

  defp locate(view, lon, lat) do
    render_hook(view, "user_located", %{"location" => %{"lat" => lat, "lon" => lon}})
    view
  end

  defp across_sea_names(view) do
    html = render(view)

    for name <- ["Kopnena", "Mostovna", "Trajektna"],
        String.contains?(html, name),
        marked_across_sea?(html, name),
        do: name
  end

  # Oznaka stoji unutar iste stavke, iza imena i prije sljedece stavke.
  defp marked_across_sea?(html, name) do
    case String.split(html, name, parts: 2) do
      [_before, rest] ->
        item = rest |> String.split("data-role=\"beach-list-item\"", parts: 2) |> hd()
        String.contains?(item, ~s(data-role="across-sea"))

      _ ->
        false
    end
  end

  describe "oznaka preko mora" do
    test "korisnik na kopnu: samo trajektni otok je preko mora", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_hook(view, "bounds_changed", @bounds)
      locate(view, 16.25, 43.20)

      assert across_sea_names(view) == ["Trajektna"]
    end

    test "korisnik na otoku bez mosta: kopno i drugi otok su preko mora", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_hook(view, "bounds_changed", @bounds)
      locate(view, 16.45, 43.45)

      assert across_sea_names(view) == ["Kopnena", "Mostovna"]
    end

    test "korisnik na otoku s mostom: nista nije preko mora osim trajektnog", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_hook(view, "bounds_changed", @bounds)
      locate(view, 16.05, 43.05)

      assert across_sea_names(view) == ["Trajektna"]
    end

    test "bez lokacije se polaziste uzima od sredine karte", %{conn: conn} do
      # Sredina @bounds je na kopnu, pa je trajektni otok preko mora, a
      # mostovni nije. Isto polaziste od kojeg se mjere i udaljenosti.
      {:ok, view, _html} = live(conn, ~p"/")
      render_hook(view, "bounds_changed", @bounds)

      assert across_sea_names(view) == ["Trajektna"]
    end

    test "kad je sredina karte na otoku bez mosta, kopno je preko mora", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "bounds_changed", %{
        @bounds
        | "center_lon" => 16.45,
          "center_lat" => 43.45
      })

      assert across_sea_names(view) == ["Kopnena", "Mostovna"]
    end
  end

  describe "filter bez trajekta" do
    test "s kopna izostavlja trajektni otok", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?ferry=no")
      render_hook(view, "bounds_changed", @bounds)
      locate(view, 16.25, 43.20)

      html = render(view)

      assert html =~ "Kopnena"
      assert html =~ "Mostovna"
      refute html =~ "Trajektna"
    end

    test "s otoka bez mosta ostaje samo taj otok", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?ferry=no")
      render_hook(view, "bounds_changed", @bounds)
      locate(view, 16.45, 43.45)

      html = render(view)

      assert html =~ "Trajektna"
      refute html =~ "Kopnena"
      refute html =~ "Mostovna"
    end

    test "bez lokacije se polaziste uzima od sredine karte", %{conn: conn} do
      # Sredina @bounds je na kopnu, pa trajektni otok ispada.
      {:ok, view, _html} = live(conn, ~p"/?ferry=no")

      html = render_hook(view, "bounds_changed", @bounds)

      assert html =~ "Kopnena"
      refute html =~ "Trajektna"
    end

    test "filter putuje kroz URL", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_hook(view, "bounds_changed", @bounds)
      assert_patch(view)

      view
      |> form("form[phx-change=filter]")
      |> render_change(%{"ferry" => "true"})

      assert assert_patch(view) =~ "ferry=no"
    end

    test "bez filtera se vide sve plaze", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_hook(view, "bounds_changed", @bounds)

      assert html =~ "Kopnena"
      assert html =~ "Mostovna"
      assert html =~ "Trajektna"
    end
  end
end
