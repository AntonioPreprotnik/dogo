defmodule Dogo.Repo.Migrations.CreateAdminsAuthTables do
  use Ecto.Migration

  # Prema phx.gen.auth, bez potvrde emaila i magic linkova: admin se stvara
  # iz konzole, a prijava je samo lozinkom (ADR 0010).
  def change do
    execute "CREATE EXTENSION IF NOT EXISTS citext", ""

    create table(:admins) do
      add :email, :citext, null: false
      add :hashed_password, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:admins, [:email])

    create table(:admins_tokens) do
      add :admin_id, references(:admins, on_delete: :delete_all), null: false
      add :token, :binary, null: false
      add :context, :string, null: false
      add :authenticated_at, :utc_datetime

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:admins_tokens, [:admin_id])
    create unique_index(:admins_tokens, [:context, :token])
  end
end
