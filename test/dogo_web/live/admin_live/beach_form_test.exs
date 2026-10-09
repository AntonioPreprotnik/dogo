defmodule DogoWeb.AdminLive.BeachFormTest do
  @moduledoc "E8-S1: ručno dodavanje i ispravljanje plaže."
  use DogoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Dogo.BeachesFixtures

  alias Dogo.Beaches

  test "bez prijave nema forme", %{conn: conn} do
    beach = beach_fixture()

    assert {:error, {:redirect, %{to: "/admin/log-in"}}} = live(conn, ~p"/admin/beaches/new")

    assert {:error, {:redirect, %{to: "/admin/log-in"}}} =
             live(conn, ~p"/admin/beaches/#{beach}/edit")
  end

  describe "prijavljen admin" do
    setup :register_and_log_in_admin

    test "dodaje novu plažu", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/admin/beaches/new")

      {:ok, _lv, _html} =
        lv
        |> form("#beach-form",
          beach: %{
            name: "Nova plaža",
            lat: "43.51",
            lon: "16.45",
            dog_status: "designated",
            surface: "sand",
            amenities: %{water: "true", shade: "false"}
          }
        )
        |> render_submit()
        |> follow_redirect(conn, ~p"/admin/beaches")

      assert %{entries: [beach]} =
               Beaches.list_beaches_for_admin(
                 Dogo.AccountsFixtures.admin_scope_fixture(),
                 query: "Nova plaža"
               )

      assert beach.dog_status_source == :manual
      assert beach.amenities["water"] == true
    end

    test "ispravlja plažu iz uvoza i upozorava da je uvoz više neće mijenjati", %{conn: conn} do
      beach = beach_fixture(name: "Bačvice", dog_status: :allowed, dog_status_source: :osm)

      {:ok, lv, _html} = live(conn, ~p"/admin/beaches/#{beach}/edit")

      assert has_element?(lv, "#import-notice")
      assert has_element?(lv, "#beach-form input[name='beach[lat]'][value='43.5041']")
      assert has_element?(lv, "#beach_amenities_water[checked]")
      refute has_element?(lv, "#beach_amenities_shade[checked]")

      lv
      |> form("#beach-form", beach: %{name: "Bačvice (ispravljeno)", dog_status: "not_allowed"})
      |> render_submit()

      assert_redirect(lv, ~p"/admin/beaches")

      updated = Beaches.get_beach!(beach.id)
      assert updated.name == "Bačvice (ispravljeno)"
      assert updated.dog_status_source == :manual
      assert updated.edited_at
    end

    test "već ispravljena plaža nema upozorenje o uvozu", %{conn: conn, scope: scope} do
      beach = beach_fixture()
      {:ok, beach} = Beaches.update_beach_as_admin(scope, beach, %{"name" => "Ispravljeno"})

      {:ok, lv, _html} = live(conn, ~p"/admin/beaches/#{beach}/edit")
      refute has_element?(lv, "#import-notice")
    end

    test "točka izvan Hrvatske prikazuje grešku i ne sprema", %{conn: conn} do
      beach = beach_fixture()
      {:ok, lv, _html} = live(conn, ~p"/admin/beaches/#{beach}/edit")

      lv |> form("#beach-form", beach: %{lat: "48.2", lon: "16.37"}) |> render_submit()

      assert has_element?(lv, "[data-role=geom-error]")
      assert Beaches.get_beach!(beach.id).geom == beach.geom
    end

    test "validacija uživo", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/admin/beaches/new")

      html = lv |> form("#beach-form", beach: %{lat: "", lon: "16.4"}) |> render_change()
      assert html =~ "can&#39;t be blank" or html =~ "ne smije biti prazno"
    end
  end
end
