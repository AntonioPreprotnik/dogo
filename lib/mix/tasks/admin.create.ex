defmodule Mix.Tasks.Admin.Create do
  @shortdoc "Stvara admina s privremenom lozinkom"

  @moduledoc """
  Stvara admina i ispisuje privremenu lozinku.

      mix admin.create ana@example.com

  Registracije u sučelju nema (ADR 0010), pa je ovo jedini način da admin
  nastane. U produkciji, gdje nema Mixa, isto radi
  `Dogo.Release.create_admin/1`.
  """
  use Mix.Task

  alias Dogo.Accounts

  @requirements ["app.start"]

  @impl Mix.Task
  def run([email]) do
    case Accounts.create_admin_with_random_password(email) do
      {:ok, admin, password} ->
        Mix.shell().info("Admin #{admin.email} stvoren. Privremena lozinka: #{password}")
        Mix.shell().info("Promijeni je nakon prve prijave, na /admin/settings.")

      {:error, changeset} ->
        Mix.raise("Admin nije stvoren: #{inspect(changeset.errors)}")
    end
  end

  def run(_argv), do: Mix.raise("Upotreba: mix admin.create EMAIL")
end
