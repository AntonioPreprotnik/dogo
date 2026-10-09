defmodule DogoWeb.AdminDashboardTest do
  @moduledoc """
  LiveDashboard je od E8-S1 iza prijave admina, umjesto basic autha iz
  E7-S4 (ADR 0010).
  """
  use DogoWeb.ConnCase, async: true

  test "bez prijave vodi na prijavu", %{conn: conn} do
    conn = get(conn, "/admin/dashboard")
    assert redirected_to(conn) == ~p"/admin/log-in"
  end

  test "basic auth više ne otvara dashboard", %{conn: conn} do
    conn =
      conn
      |> put_req_header("authorization", Plug.BasicAuth.encode_basic_auth("admin", "secret"))
      |> get("/admin/dashboard")

    assert redirected_to(conn) == ~p"/admin/log-in"
  end

  describe "prijavljen admin" do
    setup :register_and_log_in_admin

    test "otvara dashboard", %{conn: conn} do
      conn = get(conn, "/admin/dashboard")
      assert redirected_to(conn) =~ "/admin/dashboard/home"

      conn = conn |> recycle() |> get(redirected_to(conn))
      assert html_response(conn, 200) =~ "Dashboard"
    end
  end
end
