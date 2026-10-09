defmodule DogoWeb.AdminLive.BeachIndexTest do
  @moduledoc "E8-S1: admin popis plaža."
  use DogoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Dogo.BeachesFixtures

  alias Dogo.Beaches

  test "bez prijave vodi na prijavu i pamti kamo se htjelo", %{conn: conn} do
    conn = get(conn, ~p"/admin/beaches?q=split")

    assert redirected_to(conn) == ~p"/admin/log-in"
    assert get_session(conn, :admin_return_to) == "/admin/beaches?q=split"
  end

  describe "prijavljen admin" do
    setup :register_and_log_in_admin

    test "prikazuje plaže i oznaku ručne izmjene", %{conn: conn, scope: scope} do
      beach = beach_fixture(name: "Bačvice")
      edited = beach_fixture(name: "Kašjuni")

      {:ok, _} =
        Beaches.update_beach_as_admin(scope, edited, %{"name" => "Kašjuni (ispravljeno)"})

      {:ok, lv, _html} = live(conn, ~p"/admin/beaches")

      assert has_element?(lv, "#beaches", "Bačvice")
      assert has_element?(lv, "#beaches", "Kašjuni (ispravljeno)")
      assert has_element?(lv, "#edit-beach-#{beach.id}")
      assert has_element?(lv, "#beaches [data-role=edited-at]")
    end

    test "pretraga ide u URL", %{conn: conn} do
      beach_fixture(name: "Bačvice")
      beach_fixture(name: "Zlatni rat")
      {:ok, lv, _html} = live(conn, ~p"/admin/beaches")

      lv |> form("#beach-search", %{q: "zlatni"}) |> render_change()

      assert_patch(lv, ~p"/admin/beaches?q=zlatni")
      assert has_element?(lv, "#beaches", "Zlatni rat")
      refute has_element?(lv, "#beaches", "Bačvice")
    end

    test "bez rezultata prikazuje poruku", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/admin/beaches?q=nema")
      assert has_element?(lv, "#no-beaches")
    end

    test "stranice", %{conn: conn} do
      for n <- 1..26, do: beach_fixture(name: "Plaža #{String.pad_leading("#{n}", 2, "0")}")

      {:ok, lv, _html} = live(conn, ~p"/admin/beaches")
      refute has_element?(lv, "#beaches", "Plaža 26")

      lv |> element("#next-page") |> render_click()
      assert_patch(lv, ~p"/admin/beaches?page=2")
      assert has_element?(lv, "#beaches", "Plaža 26")
      assert has_element?(lv, "#previous-page")
    end

    test "brisanje miče plažu, a za OSM plažu upozorava da se vraća", %{conn: conn} do
      beach = beach_fixture(name: "Bačvice")
      {:ok, lv, _html} = live(conn, ~p"/admin/beaches")

      delete = element(lv, "#delete-beach-#{beach.id}")
      assert render(delete) =~ "OpenStreetMap"

      render_click(delete)

      refute has_element?(lv, "#beaches", "Bačvice")
      assert_raise Ecto.NoResultsError, fn -> Beaches.get_beach!(beach.id) end
    end
  end
end
