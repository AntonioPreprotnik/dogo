defmodule Dogo.AccountsFixtures do
  @moduledoc """
  Pomoćne funkcije za stvaranje admina i sesija u testovima.
  """

  import Ecto.Query

  alias Dogo.Accounts
  alias Dogo.Accounts.Scope

  def unique_admin_email, do: "admin#{System.unique_integer()}@example.com"
  def valid_admin_password, do: "hello world!"

  def valid_admin_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      email: unique_admin_email(),
      password: valid_admin_password()
    })
  end

  def admin_fixture(attrs \\ %{}) do
    {:ok, admin} =
      attrs
      |> valid_admin_attributes()
      |> Accounts.create_admin()

    admin
  end

  def admin_scope_fixture(admin \\ admin_fixture()), do: Scope.for_admin(admin)

  def override_token_authenticated_at(token, authenticated_at) when is_binary(token) do
    Dogo.Repo.update_all(
      from(t in Accounts.AdminToken, where: t.token == ^token),
      set: [authenticated_at: authenticated_at]
    )
  end

  def offset_admin_token(token, amount_to_add, unit) do
    dt = DateTime.add(DateTime.utc_now(:second), amount_to_add, unit)

    Dogo.Repo.update_all(
      from(ut in Accounts.AdminToken, where: ut.token == ^token),
      set: [inserted_at: dt, authenticated_at: dt]
    )
  end
end
