defmodule DogoWeb.PageControllerTest do
  use DogoWeb.ConnCase, async: true

  import Dogo.BeachesFixtures

  test "GET / prikazuje naslovnicu", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)

    assert html =~ "Plaže za pse na hrvatskom Jadranu"
    assert html =~ "<title data-default=\"Plaže za pse\""
  end

  test "GET / prikazuje broj plaža u bazi", %{conn: conn} do
    beach_fixture()
    beach_fixture()

    assert get(conn, ~p"/") |> html_response(200) =~ "2 <span"
  end
end
