defmodule DogoWeb.AdminSessionController do
  @moduledoc """
  Prijava, odjava i promjena lozinke admina.

  Kontroler, a ne LiveView, jer se sesija i cookie mogu postaviti samo u HTTP
  odgovoru. LiveView forme ovamo šalju podatke kroz `phx-trigger-action`.
  """
  use DogoWeb, :controller

  alias Dogo.Accounts
  alias DogoWeb.AdminAuth

  def create(conn, %{"admin" => admin_params}) do
    create(conn, admin_params, gettext("Welcome back!"))
  end

  def update_password(conn, %{"admin" => admin_params}) do
    admin = conn.assigns.current_scope.admin

    # Forma se prikazuje samo u sudo načinu, ali POST može stići i izravno.
    if Accounts.sudo_mode?(admin) do
      case Accounts.update_admin_password(admin, admin_params) do
        {:ok, {_admin, expired_tokens}} ->
          AdminAuth.disconnect_sessions(expired_tokens)

          conn
          |> put_session(:admin_return_to, ~p"/admin/settings")
          |> create(admin_params, gettext("Password updated."))

        {:error, _changeset} ->
          conn
          |> put_flash(:error, gettext("The password was not changed."))
          |> redirect(to: ~p"/admin/settings")
      end
    else
      conn
      |> put_flash(:error, gettext("Log in again to access this page."))
      |> redirect(to: ~p"/admin/log-in")
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, gettext("Logged out."))
    |> AdminAuth.log_out_admin()
  end

  defp create(conn, admin_params, info) do
    %{"email" => email, "password" => password} = admin_params

    if admin = Accounts.get_admin_by_email_and_password(email, password) do
      conn
      |> put_flash(:info, info)
      |> AdminAuth.log_in_admin(admin, admin_params)
    else
      # Ista poruka za nepoznat email i krivu lozinku, da se ne može
      # provjeravati koji emailovi postoje.
      conn
      |> put_flash(:error, gettext("Invalid email or password."))
      |> put_flash(:email, String.slice(email, 0, 160))
      |> redirect(to: ~p"/admin/log-in")
    end
  end
end
