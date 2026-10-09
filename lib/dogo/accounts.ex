defmodule Dogo.Accounts do
  @moduledoc """
  Administratori i njihove sesije.

  Javnih korisnika nema: aplikacija se koristi bez prijave, a admin postoji
  samo za ručne ispravke podataka (E8-S1). Vidi
  `docs/adr/0010-admin-bez-registracije.md`.
  """

  import Ecto.Query, warn: false

  alias Dogo.Accounts.Admin
  alias Dogo.Accounts.AdminToken
  alias Dogo.Repo

  @doc "Admin s danim emailom i lozinkom, ili `nil`."
  def get_admin_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    admin = Repo.get_by(Admin, email: email)
    if Admin.valid_password?(admin, password), do: admin
  end

  @doc "Dohvaća admina po ID-u ili diže `Ecto.NoResultsError`."
  def get_admin!(id), do: Repo.get!(Admin, id)

  @doc """
  Stvara admina. Poziva se samo iz konzole, nikad iz weba.
  """
  def create_admin(attrs) do
    %Admin{}
    |> Admin.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Stvara admina s nasumičnom lozinkom i vraća je, jer se lozinka nigdje ne
  sprema u čitljivom obliku. Lozinka ne prolazi kroz argumente naredbenog
  retka, pa ne ostaje u povijesti shella.
  """
  def create_admin_with_random_password(email) do
    password = :crypto.strong_rand_bytes(18) |> Base.url_encode64(padding: false)

    with {:ok, admin} <- create_admin(%{email: email, password: password}) do
      {:ok, admin, password}
    end
  end

  ## Postavke

  @doc """
  Je li admin u "sudo" načinu, tj. prijavio se lozinkom u zadnjih
  `minutes` minuta (zadano 20). Osjetljive radnje to traže.
  """
  def sudo_mode?(admin, minutes \\ -20)

  def sudo_mode?(%Admin{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.utc_now() |> DateTime.add(minutes, :minute))
  end

  def sudo_mode?(_admin, _minutes), do: false

  @doc "Changeset za formu promjene lozinke."
  def change_admin_password(admin, attrs \\ %{}, opts \\ []) do
    Admin.password_changeset(admin, attrs, opts)
  end

  @doc """
  Mijenja lozinku i briše sve sesije admina.

  Vraća ažuriranog admina i obrisane tokene, da web sloj može prekinuti
  otvorene LiveView veze.
  """
  def update_admin_password(admin, attrs) do
    changeset = Admin.password_changeset(admin, attrs)

    Repo.transact(fn ->
      with {:ok, admin} <- Repo.update(changeset) do
        tokens = Repo.all_by(AdminToken, admin_id: admin.id)
        Repo.delete_all(from t in AdminToken, where: t.id in ^Enum.map(tokens, & &1.id))
        {:ok, {admin, tokens}}
      end
    end)
  end

  ## Sesije

  @doc "Stvara i sprema token sesije."
  def generate_admin_session_token(admin) do
    {token, admin_token} = AdminToken.build_session_token(admin)
    Repo.insert!(admin_token)
    token
  end

  @doc """
  Admin za token sesije, kao `{admin, token_inserted_at}`, ili `nil`.
  """
  def get_admin_by_session_token(token) do
    {:ok, query} = AdminToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc "Briše token sesije (odjava)."
  def delete_admin_session_token(token) do
    Repo.delete_all(from(AdminToken, where: [token: ^token, context: "session"]))
    :ok
  end
end
