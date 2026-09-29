defmodule DogoWeb.Plugs.DashboardAuth do
  @moduledoc """
  Basic auth za LiveDashboard u produkciji (E7-S4).

  Vjerodajnice dolaze iz okoline (`DASHBOARD_USER`, `DASHBOARD_PASSWORD`,
  vidi `config/runtime.exs`). **Bez njih je dashboard isključen** i ruta
  vraća 404: zaboravljena varijabla ne smije značiti otvoren dashboard.

  Aplikacija još nema korisnike ni admina (E8 je opcionalan), pa je basic
  auth preko HTTPS-a razumna mjera, kako preporuča i Phoenix.
  """
  import Plug.Conn

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    case Application.get_env(:dogo, :dashboard_auth) do
      [username: username, password: password]
      when is_binary(username) and username != "" and is_binary(password) and password != "" ->
        Plug.BasicAuth.basic_auth(conn, username: username, password: password)

      _ ->
        conn |> send_resp(:not_found, "Not Found") |> halt()
    end
  end
end
