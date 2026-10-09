defmodule DogoWeb.AdminLive.LoginTest do
  @moduledoc "E8-S1: prijava admina."
  use DogoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Dogo.AccountsFixtures

  test "prijava je samo lozinkom, bez registracije i magic linka", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/admin/log-in")

    assert has_element?(lv, "#login_form input[type=password]")
    refute has_element?(lv, "a[href*=register]")
    refute has_element?(lv, "#login_form_magic")
  end

  test "registracije nema ni kao rute", %{conn: conn} do
    assert conn |> get("/admins/register") |> html_response(404)
    assert conn |> get("/admin/register") |> html_response(404)
  end

  test "ispravni podaci prijavljuju admina", %{conn: conn} do
    admin = admin_fixture()
    {:ok, lv, _html} = live(conn, ~p"/admin/log-in")

    form =
      form(lv, "#login_form",
        admin: %{email: admin.email, password: valid_admin_password(), remember_me: true}
      )

    conn = submit_form(form, conn)

    assert redirected_to(conn) == ~p"/admin/beaches"
  end

  test "neispravni podaci vraćaju na prijavu s porukom", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/admin/log-in")

    form = form(lv, "#login_form", admin: %{email: "test@email.com", password: "123456"})
    render_submit(form)
    conn = follow_trigger_action(form, conn)

    assert Phoenix.Flash.get(conn.assigns.flash, :error)
    assert redirected_to(conn) == ~p"/admin/log-in"
  end

  test "sučelje je prevedeno (zadano hrvatski)", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/admin/log-in")
    assert html =~ "Prijava administratora"

    {:ok, _lv, html} =
      conn |> put_req_cookie(DogoWeb.Locale.cookie(), "de") |> live(~p"/admin/log-in")

    assert html =~ "Anmeldung für Administratoren"
  end

  test "ponovna prijava (sudo) ima popunjen email", %{conn: conn} do
    admin = admin_fixture()
    {:ok, lv, _html} = conn |> log_in_admin(admin) |> live(~p"/admin/log-in")

    assert has_element?(lv, ~s(#login_form input[name="admin[email]"][value="#{admin.email}"]))
  end
end
