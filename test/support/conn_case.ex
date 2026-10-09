defmodule DogoWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use DogoWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  alias Dogo.Accounts
  alias Dogo.Accounts.Scope
  alias Dogo.AccountsFixtures

  using do
    quote do
      # The default endpoint for testing
      @endpoint DogoWeb.Endpoint

      use DogoWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import DogoWeb.ConnCase
    end
  end

  setup tags do
    Dogo.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc """
  Stvara admina i prijavljuje ga u `conn`.

      setup :register_and_log_in_admin

  U kontekst testa dodaje `conn`, `admin` i `scope`. Tag
  `token_authenticated_at` postavlja vrijeme prijave (za sudo testove).
  """
  def register_and_log_in_admin(%{conn: conn} = context) do
    admin = AccountsFixtures.admin_fixture()
    scope = Scope.for_admin(admin)

    opts =
      context
      |> Map.take([:token_authenticated_at])
      |> Enum.into([])

    %{conn: log_in_admin(conn, admin, opts), admin: admin, scope: scope}
  end

  @doc "Prijavljuje danog admina u `conn`."
  def log_in_admin(conn, admin, opts \\ []) do
    token = Accounts.generate_admin_session_token(admin)

    maybe_set_token_authenticated_at(token, opts[:token_authenticated_at])

    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:admin_token, token)
  end

  defp maybe_set_token_authenticated_at(_token, nil), do: nil

  defp maybe_set_token_authenticated_at(token, authenticated_at) do
    AccountsFixtures.override_token_authenticated_at(token, authenticated_at)
  end
end
