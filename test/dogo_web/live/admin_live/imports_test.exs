defmodule DogoWeb.AdminLive.ImportsTest do
  @moduledoc "E8-S1: ponovno pokretanje uvoza iz sučelja."
  use DogoWeb.ConnCase, async: true
  use Oban.Testing, repo: Dogo.Repo

  import Phoenix.LiveViewTest

  alias Dogo.Import.Jobs.ImportBeaches
  alias Dogo.Import.Jobs.ImportIslands

  test "bez prijave vodi na prijavu", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/admin/log-in"}}} = live(conn, ~p"/admin/imports")
  end

  describe "prijavljen admin" do
    setup :register_and_log_in_admin

    test "bez jobova prikazuje praznu listu", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/admin/imports")
      assert has_element?(lv, "#no-jobs")
    end

    test "gumbi stavljaju uvoz plaža i otoka u red i prikazuju job", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/admin/imports")

      lv |> element("#import-beaches") |> render_click()
      assert_enqueued(worker: ImportBeaches)

      lv |> element("#import-islands") |> render_click()
      assert_enqueued(worker: ImportIslands)

      assert has_element?(lv, "#jobs [data-role=job-state][data-state=available]", "čeka")
      refute has_element?(lv, "#no-jobs")
    end

    test "dvostruki klik ne pravi drugi uvoz", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/admin/imports")

      lv |> element("#import-beaches") |> render_click()
      lv |> element("#import-beaches") |> render_click()

      assert [_] = all_enqueued(worker: ImportBeaches)
    end

    test "dok job čeka, stranica se osvježava", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/admin/imports")
      lv |> element("#import-beaches") |> render_click()

      [job] = all_enqueued(worker: ImportBeaches)
      Dogo.Repo.update_all(Oban.Job, set: [state: "completed", completed_at: DateTime.utc_now()])
      send(lv.pid, :refresh)

      assert has_element?(lv, "#job-#{job.id} [data-role=job-state][data-state=completed]")
    end
  end
end
