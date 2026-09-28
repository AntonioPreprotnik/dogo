defmodule DogoWeb.HealthController do
  @moduledoc """
  Liveness/readiness probe used by the platform (Fly.io) and by CI smoke checks.

  Returns 200 only when the database answers, so a deploy with a broken
  `DATABASE_URL` fails fast instead of serving errors.
  """
  use DogoWeb, :controller

  alias Ecto.Adapters.SQL

  def index(conn, _params) do
    case SQL.query(Dogo.Repo, "SELECT 1", []) do
      {:ok, _} ->
        json(conn, %{status: "ok", database: "ok"})

      {:error, _} ->
        conn |> put_status(:service_unavailable) |> json(%{status: "error", database: "error"})
    end
  end
end
