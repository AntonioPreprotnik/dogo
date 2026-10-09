defmodule Dogo.Accounts.AdminToken do
  @moduledoc """
  Token sesije admina.

  Sesije su u bazi, a ne samo u potpisanom cookieju, da ih se može opozvati:
  odjava i promjena lozinke brišu tokene, pa stari cookie više ne vrijedi.
  """
  use Ecto.Schema

  import Ecto.Query

  alias Dogo.Accounts.AdminToken

  @rand_size 32
  @session_validity_in_days 14

  schema "admins_tokens" do
    field :token, :binary
    field :context, :string
    field :authenticated_at, :utc_datetime
    belongs_to :admin, Dogo.Accounts.Admin

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc """
  Novi token sesije. Ide u potpisanu sesiju, pa se ne hashira.
  """
  def build_session_token(admin) do
    token = :crypto.strong_rand_bytes(@rand_size)
    dt = admin.authenticated_at || DateTime.utc_now(:second)

    {token,
     %AdminToken{token: token, context: "session", admin_id: admin.id, authenticated_at: dt}}
  end

  @doc """
  Upit koji za važeći token vraća `{admin, token_inserted_at}`.

  Token vrijedi #{@session_validity_in_days} dana od izdavanja.
  """
  def verify_session_token_query(token) do
    query =
      from token in by_token_and_context_query(token, "session"),
        join: admin in assoc(token, :admin),
        where: token.inserted_at > ago(@session_validity_in_days, "day"),
        select: {%{admin | authenticated_at: token.authenticated_at}, token.inserted_at}

    {:ok, query}
  end

  defp by_token_and_context_query(token, context) do
    from AdminToken, where: [token: ^token, context: ^context]
  end
end
