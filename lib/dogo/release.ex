defmodule Dogo.Release do
  @moduledoc """
  Tasks that run inside a release, where Mix is not available.

  Invoked from the Fly.io release command: `bin/dogo eval "Dogo.Release.migrate()"`.
  """
  @app :dogo

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  @doc """
  Stvara admina s nasumičnom lozinkom i ispisuje je. Lozinka se nakon prve
  prijave mijenja u postavkama.

      fly ssh console -C '/app/bin/dogo eval "Dogo.Release.create_admin(\\"ana@example.com\\")"'
  """
  def create_admin(email) do
    load_app()

    {:ok, _, _} =
      Ecto.Migrator.with_repo(Dogo.Repo, fn _repo ->
        email |> Dogo.Accounts.create_admin_with_random_password() |> report_admin()
      end)

    :ok
  end

  defp report_admin({:ok, admin, password}) do
    IO.puts("Admin #{admin.email} stvoren. Privremena lozinka: #{password}")
  end

  defp report_admin({:error, changeset}) do
    IO.puts("Admin nije stvoren: #{inspect(changeset.errors)}")
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.ensure_loaded(@app)
  end
end
