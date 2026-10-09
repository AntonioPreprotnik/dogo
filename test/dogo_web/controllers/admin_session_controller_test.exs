defmodule DogoWeb.AdminSessionControllerTest do
  @moduledoc "E8-S1: prijava, odjava i promjena lozinke."
  use DogoWeb.ConnCase, async: true

  import Dogo.AccountsFixtures

  alias Dogo.Accounts

  setup do
    %{admin: admin_fixture()}
  end

  describe "POST /admin/log-in" do
    test "prijavljuje admina i vodi na popis plaža", %{conn: conn, admin: admin} do
      conn =
        post(conn, ~p"/admin/log-in", %{
          "admin" => %{"email" => admin.email, "password" => valid_admin_password()}
        })

      assert get_session(conn, :admin_token)
      assert redirected_to(conn) == ~p"/admin/beaches"

      response = conn |> get(~p"/admin/beaches") |> html_response(200)
      assert response =~ admin.email
      assert response =~ ~p"/admin/log-out"
    end

    test "s 'zapamti me' postavlja cookie", %{conn: conn, admin: admin} do
      conn =
        post(conn, ~p"/admin/log-in", %{
          "admin" => %{
            "email" => admin.email,
            "password" => valid_admin_password(),
            "remember_me" => "true"
          }
        })

      assert conn.resp_cookies["_dogo_web_admin_remember_me"]
    end

    test "vraća na stranicu koja je tražila prijavu", %{conn: conn, admin: admin} do
      conn =
        conn
        |> init_test_session(admin_return_to: "/admin/imports")
        |> post(~p"/admin/log-in", %{
          "admin" => %{"email" => admin.email, "password" => valid_admin_password()}
        })

      assert redirected_to(conn) == "/admin/imports"
      assert Phoenix.Flash.get(conn.assigns.flash, :info)
    end

    test "kriva lozinka vraća na prijavu bez sesije", %{conn: conn, admin: admin} do
      conn =
        post(conn, ~p"/admin/log-in", %{
          "admin" => %{"email" => admin.email, "password" => "invalid_password"}
        })

      refute get_session(conn, :admin_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :error)
      assert Phoenix.Flash.get(conn.assigns.flash, :email) == admin.email
      assert redirected_to(conn) == ~p"/admin/log-in"
    end

    test "nepoznat email daje istu poruku kao kriva lozinka", %{conn: conn, admin: admin} do
      wrong_password =
        post(conn, ~p"/admin/log-in", %{
          "admin" => %{"email" => admin.email, "password" => "invalid_password"}
        })

      unknown_email =
        post(conn, ~p"/admin/log-in", %{
          "admin" => %{"email" => "nobody@example.com", "password" => "invalid_password"}
        })

      assert Phoenix.Flash.get(wrong_password.assigns.flash, :error) ==
               Phoenix.Flash.get(unknown_email.assigns.flash, :error)
    end
  end

  describe "POST /admin/update-password" do
    setup :register_and_log_in_admin

    test "mijenja lozinku, odjavljuje ostale sesije i ponovno prijavljuje", %{
      conn: conn,
      admin: admin
    } do
      other_session = Accounts.generate_admin_session_token(admin)

      conn =
        post(conn, ~p"/admin/update-password", %{
          "admin" => %{
            "email" => admin.email,
            "password" => "new valid password",
            "password_confirmation" => "new valid password"
          }
        })

      assert redirected_to(conn) == ~p"/admin/settings"
      assert get_session(conn, :admin_token)
      refute Accounts.get_admin_by_session_token(other_session)
      assert Accounts.get_admin_by_email_and_password(admin.email, "new valid password")
    end

    @tag token_authenticated_at: DateTime.add(DateTime.utc_now(:second), -30, :minute)
    test "bez nedavne prijave ne mijenja lozinku", %{conn: conn, admin: admin} do
      conn =
        post(conn, ~p"/admin/update-password", %{
          "admin" => %{"email" => admin.email, "password" => "new valid password"}
        })

      assert redirected_to(conn) == ~p"/admin/log-in"
      assert Accounts.get_admin_by_email_and_password(admin.email, valid_admin_password())
    end

    test "neispravna lozinka ostavlja staru", %{conn: conn, admin: admin} do
      conn =
        post(conn, ~p"/admin/update-password", %{
          "admin" => %{"email" => admin.email, "password" => "short"}
        })

      assert redirected_to(conn) == ~p"/admin/settings"
      assert Phoenix.Flash.get(conn.assigns.flash, :error)
      assert Accounts.get_admin_by_email_and_password(admin.email, valid_admin_password())
    end
  end

  describe "DELETE /admin/log-out" do
    test "odjavljuje admina", %{conn: conn, admin: admin} do
      conn = conn |> log_in_admin(admin) |> delete(~p"/admin/log-out")

      assert redirected_to(conn) == ~p"/admin/log-in"
      refute get_session(conn, :admin_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info)
    end

    test "radi i bez prijave", %{conn: conn} do
      conn = delete(conn, ~p"/admin/log-out")

      assert redirected_to(conn) == ~p"/admin/log-in"
      refute get_session(conn, :admin_token)
    end
  end
end
