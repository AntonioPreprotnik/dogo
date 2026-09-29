defmodule DogoWeb.ErrorStatesTest do
  @moduledoc """
  E4-S3: svako stanje u kojem nešto ne radi mora imati poruku, umjesto prazne
  karte o kojoj korisnik ne zna što misliti.
  """
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

  describe "geolokacija" do
    test "svaki razlog ima svoju poruku", %{conn: conn} do
      for {reason, fragment} <- [
            {"denied", "Bez tvoje lokacije"},
            {"unavailable", "ne nudi lokaciju"},
            {"timeout", "nije stigla na vrijeme"},
            {"unknown", "nije bilo moguće dohvatiti"}
          ] do
        {:ok, view, _html} = live(conn, ~p"/")

        assert render_hook(view, "geolocation_error", %{"reason" => reason}) =~ fragment
      end
    end

    test "timeout objasni zašto se moglo dogoditi", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      html = render_hook(view, "geolocation_error", %{"reason" => "timeout"})

      assert html =~ "GPS zna šutjeti"
      assert html =~ "Upiši mjesto"
    end

    test "nepoznat razlog ne ruši stranicu", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert render_hook(view, "geolocation_error", %{"reason" => "nesto_novo"}) =~
               "nije bilo moguće dohvatiti"
    end

    test "svaki razlog nudi i pretragu mjesta", %{conn: conn} do
      for reason <- ~w(denied unavailable timeout unknown) do
        {:ok, view, _html} = live(conn, ~p"/")
        render_hook(view, "geolocation_error", %{"reason" => reason})

        assert has_element?(view, ~s([data-role="place-fallback"] input[name="q"]))
      end
    end
  end

  describe "nedostupan tile server" do
    test "bez greške nema poruke", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      refute has_element?(view, ~s([data-role="tiles-notice"]))
    end

    test "poruka kaže da lista i dalje radi", %{conn: conn} do
      beach_fixture(%{osm_id: "way/a", name: "Bačvice", geom: point(16.4453, 43.5041)})

      {:ok, view, _html} = live(conn, ~p"/")
      render_hook(view, "bounds_changed", @bounds)

      html = render_hook(view, "map_tiles", %{"ok" => false})

      assert html =~ "Pozadinska karta se ne učitava"
      assert html =~ "i dalje rade"
      # Lista je i dalje tu; pad karte ne ruši ostatak stranice.
      assert html =~ "Bačvice"
    end

    test "poruka nestane kad se ploče učitaju", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "map_tiles", %{"ok" => false})
      assert has_element?(view, ~s([data-role="tiles-notice"]))

      render_hook(view, "map_tiles", %{"ok" => true})
      refute has_element?(view, ~s([data-role="tiles-notice"]))
    end
  end

  describe "prazan rezultat" do
    test "bez filtera predlaže pomicanje karte", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert render_hook(view, "bounds_changed", @bounds) =~ "Pomakni ili odzumiraj kartu"
    end

    test "s filterima kaže da su filteri krivac", %{conn: conn} do
      beach_fixture(%{osm_id: "way/a", geom: point(16.4453, 43.5041), dog_status: :not_allowed})

      {:ok, view, _html} = live(conn, ~p"/?dog=designated")

      assert render_hook(view, "bounds_changed", @bounds) =~ "ne odgovara filterima"
    end
  end

  describe "trazenje lokacije" do
    test "bez odgovora preglednika nudi gumb umjesto dijaloga", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      html = render_hook(view, "geolocation_idle", %{})

      assert html =~ "Koristi moju lokaciju"
      assert has_element?(view, ~s([data-role="request-location"]))
    end

    test "klik na gumb trazi lokaciju od hooka", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_hook(view, "geolocation_idle", %{})

      html = view |> element(~s([data-role="request-location"])) |> render_click()

      assert_push_event(view, "request_location", %{})
      assert html =~ "Čekam lokaciju"
    end

    test "dok cekamo, gumb je onemogucen", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_hook(view, "geolocation_idle", %{})
      render_click(view, "request_location", %{})

      assert has_element?(view, ~s([data-role="request-location"][disabled]))
    end

    test "nakon odbijanja nema vise gumba, nego pretrage mjesta", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_hook(view, "geolocation_idle", %{})
      render_hook(view, "geolocation_error", %{"reason" => "denied"})

      refute has_element?(view, ~s([data-role="request-location"]))
      assert has_element?(view, ~s([data-role="place-fallback"]))
    end
  end
end
