defmodule DogoWeb.DashboardAuthTest do
  @moduledoc "E7-S4: LiveDashboard u produkciji je iza basic autha."
  # Vjerodajnice su u Application envu, koji je globalan.
  use DogoWeb.ConnCase, async: false

  @path "/admin/dashboard"

  setup do
    previous = Application.get_env(:dogo, :dashboard_auth)
    on_exit(fn -> Application.put_env(:dogo, :dashboard_auth, previous) end)
  end

  defp configure(username, password) do
    Application.put_env(:dogo, :dashboard_auth, username: username, password: password)
  end

  defp with_auth(conn, username, password) do
    put_req_header(conn, "authorization", Plug.BasicAuth.encode_basic_auth(username, password))
  end

  test "bez postavljenih vjerodajnica dashboard ne postoji", %{conn: conn} do
    configure(nil, nil)

    assert conn |> get(@path) |> response(404)
  end

  test "prazna lozinka ne otvara dashboard", %{conn: conn} do
    configure("admin", "")

    assert conn |> with_auth("admin", "") |> get(@path) |> response(404)
  end

  test "bez autentifikacije traži prijavu", %{conn: conn} do
    configure("admin", "tajna")

    conn = get(conn, @path)

    assert response(conn, 401)
    assert [~s(Basic realm=) <> _] = get_resp_header(conn, "www-authenticate")
  end

  test "kriva lozinka je odbijena", %{conn: conn} do
    configure("admin", "tajna")

    assert conn |> with_auth("admin", "kriva") |> get(@path) |> response(401)
  end

  test "ispravne vjerodajnice otvaraju dashboard", %{conn: conn} do
    configure("admin", "tajna")

    conn = conn |> with_auth("admin", "tajna") |> get(@path)

    assert conn.status in [200, 302]
    refute conn.status == 401
  end
end
