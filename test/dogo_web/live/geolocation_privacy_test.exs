defmodule DogoWeb.GeolocationPrivacyTest do
  @moduledoc """
  E4-S1 traži da korisnikova lokacija ne završi u logovima.

  Ovi testovi namjerno **uključuju** logiranje. U testnoj konfiguraciji je
  Logger na `:warning`, pa bi `refute log =~ koordinate` prolazio i kad filter
  uopće ne bi radio — test bi bio zelen bez ikakvog jamstva.

  Zato `async: false`: razina Loggera je globalna.
  """
  use DogoWeb.ConnCase, async: false

  # Logiranje je ovdje ukljuceno namjerno; ExUnit neka ga zadrzi za sebe umjesto
  # da zatrpa izlaz suitea. capture_log/1 unutar testova i dalje radi.
  @moduletag :capture_log

  import Dogo.BeachesFixtures
  import ExUnit.CaptureLog
  import Phoenix.LiveViewTest

  alias Dogo.Beaches.Beach
  alias Dogo.Repo

  @bounds %{
    "west" => 16.40,
    "south" => 43.48,
    "east" => 16.52,
    "north" => 43.54,
    "center_lon" => 16.51,
    "center_lat" => 43.535,
    "zoom" => 12.0
  }

  @latitude "43.5041"
  @longitude "16.4453"
  @user %{"location" => %{"lat" => 43.5041, "lon" => 16.4453}}

  setup do
    level = Logger.level()
    Logger.configure(level: :debug)
    on_exit(fn -> Logger.configure(level: level) end)

    beach_fixture(%{osm_id: "way/a", name: "Uz korisnika", geom: point(16.4460, 43.5045)})
    beach_fixture(%{osm_id: "way/b", name: "Uz sredinu", geom: point(16.5105, 43.5355)})

    :ok
  end

  test "provjera je smislena: logiranje je stvarno uključeno", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    log = capture_log(fn -> render_hook(view, "bounds_changed", @bounds) end)

    assert log =~ "HANDLE EVENT"
    assert log =~ "SELECT"
  end

  test "koordinate ne završe u logu LiveView eventa", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    log =
      capture_log(fn ->
        render_hook(view, "bounds_changed", @bounds)
        render_hook(view, "user_located", @user)
      end)

    assert log =~ "user_located"
    assert log =~ "FILTERED"
    refute log =~ @latitude
    refute log =~ @longitude
  end

  test "koordinate ne završe ni u logu Ecto upita", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    render_hook(view, "bounds_changed", @bounds)

    log = capture_log(fn -> render_hook(view, "user_located", @user) end)

    refute log =~ @latitude
    refute log =~ @longitude
  end

  test "lokacija se ne sprema u bazu", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    render_hook(view, "bounds_changed", @bounds)
    render_hook(view, "user_located", @user)

    # Plaze su jedina tablica u koju pisemo, i broj im se nije promijenio.
    assert Repo.aggregate(Beach, :count) == 2
  end

  test "sam event s lokacijom ne patcha URL", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    render_hook(view, "bounds_changed", @bounds)
    assert_patch(view)

    render_hook(view, "user_located", @user)

    refute_received {_ref, {:patch, _topic, _opts}}
  end

  test "karta centrirana na korisnika ne upisuje koordinate u URL", %{conn: conn} do
    # Scenarij koji je prvi test propustio: nakon geolokacije se karta sama
    # pomakne i javi nove granice cija je sredina korisnikova lokacija.
    {:ok, view, _html} = live(conn, ~p"/")
    render_hook(view, "user_located", @user)

    render_hook(view, "bounds_changed", centered_on_user(@bounds))

    refute_received {_ref, {:patch, _topic, _opts}}
  end

  test "ni drugi moveend nakon animacije ne procuri", %{conn: conn} do
    # MapLibre nakon flyTo emitira jos jedan moveend, s koordinatama koje se
    # razlikuju tek u zadnjim decimalama. Zbog njega je zastavica u hooku bila
    # nedovoljna.
    {:ok, view, _html} = live(conn, ~p"/")
    render_hook(view, "user_located", @user)

    render_hook(view, "bounds_changed", centered_on_user(@bounds))

    render_hook(view, "bounds_changed", %{
      centered_on_user(@bounds)
      | "center_lat" => 43.50420199430363,
        "center_lon" => 16.445328433002032
    })

    refute_received {_ref, {:patch, _topic, _opts}}
  end

  test "kad korisnik odmakne kartu, URL opet prati pogled", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    render_hook(view, "user_located", @user)
    render_hook(view, "bounds_changed", centered_on_user(@bounds))

    render_hook(view, "bounds_changed", @bounds)

    path = assert_patch(view)
    assert path =~ "lat=43.535"
    refute path =~ @latitude
  end

  test "bez poznate lokacije se pozicija uvijek upisuje", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    render_hook(view, "bounds_changed", centered_on_user(@bounds))

    assert assert_patch(view) =~ "lat=#{@latitude}"
  end

  defp centered_on_user(bounds) do
    %{bounds | "center_lat" => 43.5041, "center_lon" => 16.4453}
  end
end
