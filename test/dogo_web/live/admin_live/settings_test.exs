defmodule DogoWeb.AdminLive.SettingsTest do
  @moduledoc "E8-S1: promjena lozinke."
  use DogoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Dogo.AccountsFixtures

  alias Dogo.Accounts

  test "bez prijave vodi na prijavu", %{conn: conn} do
    assert {:error, {:redirect, %{to: path}}} = live(conn, ~p"/admin/settings")
    assert path == ~p"/admin/log-in"
  end

  test "bez nedavne prijave traži ponovnu prijavu", %{conn: conn} do
    admin = admin_fixture()

    assert {:error, {:redirect, %{to: path}}} =
             conn
             |> log_in_admin(admin,
               token_authenticated_at: DateTime.add(DateTime.utc_now(:second), -11, :minute)
             )
             |> live(~p"/admin/settings")

    assert path == ~p"/admin/log-in"
  end

  describe "promjena lozinke" do
    setup :register_and_log_in_admin

    test "nema promjene emaila, samo lozinke", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/admin/settings")

      assert has_element?(lv, "#password_form")
      refute has_element?(lv, "#email_form")
    end

    test "prikazuje greške uživo", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/admin/settings")

      html =
        lv
        |> element("#password_form")
        |> render_change(%{
          "admin" => %{"password" => "too short", "password_confirmation" => "does not match"}
        })

      assert html =~ "should be at least 12 character(s)"
      assert html =~ "does not match password"
    end

    test "ispravna lozinka se predaje kontroleru", %{conn: conn, admin: admin} do
      {:ok, lv, _html} = live(conn, ~p"/admin/settings")

      form =
        form(lv, "#password_form", %{
          "admin" => %{
            "email" => admin.email,
            "password" => "new valid password",
            "password_confirmation" => "new valid password"
          }
        })

      render_submit(form)
      new_conn = follow_trigger_action(form, conn)

      assert redirected_to(new_conn) == ~p"/admin/settings"
      assert get_session(new_conn, :admin_token) != get_session(conn, :admin_token)
      assert Accounts.get_admin_by_email_and_password(admin.email, "new valid password")
    end
  end
end
