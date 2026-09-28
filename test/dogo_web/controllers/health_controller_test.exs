defmodule DogoWeb.HealthControllerTest do
  use DogoWeb.ConnCase, async: true

  test "GET /health returns 200 when the database answers", %{conn: conn} do
    conn = get(conn, ~p"/health")

    assert json_response(conn, 200) == %{"status" => "ok", "database" => "ok"}
  end
end
