defmodule Dogo.Accounts.Admin do
  @moduledoc """
  Administrator aplikacije.

  Nastao iz `phx.gen.auth`, ali bez registracije i potvrde emaila: admin se
  stvara iz konzole (`mix admin.create`, `Dogo.Release.create_admin/1`) i
  prijavljuje se samo lozinkom. Vidi `docs/adr/0010-admin-bez-registracije.md`.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "admins" do
    field :email, :string
    field :password, :string, virtual: true, redact: true
    field :hashed_password, :string, redact: true
    field :authenticated_at, :utc_datetime, virtual: true

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset za novog admina: email i lozinka zajedno, jer prijave bez lozinke
  nema.
  """
  def create_changeset(admin, attrs) do
    admin
    |> cast(attrs, [:email])
    |> validate_email()
    |> password_changeset(attrs)
  end

  defp validate_email(changeset) do
    changeset
    |> update_change(:email, &String.trim/1)
    |> validate_required([:email])
    |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
      message: "must have the @ sign and no spaces"
    )
    |> validate_length(:email, max: 160)
    |> unsafe_validate_unique(:email, Dogo.Repo)
    |> unique_constraint(:email)
  end

  @doc """
  Changeset za promjenu lozinke.

  Duljina je ograničena i odozgo: bcrypt gleda samo prva 72 bajta, a duge
  lozinke su skupe za hashiranje.

  ## Opcije

    * `:hash_password` - hashira lozinku i briše je iz changeseta, da ne
      završi u logu. Za validaciju forme uživo postavi na `false`.
      Zadano `true`.
  """
  def password_changeset(admin, attrs, opts \\ []) do
    admin
    |> cast(attrs, [:password])
    |> validate_confirmation(:password, message: "does not match password")
    |> validate_required([:password])
    |> validate_length(:password, min: 12, max: 72)
    |> maybe_hash_password(opts)
  end

  defp maybe_hash_password(changeset, opts) do
    hash_password? = Keyword.get(opts, :hash_password, true)
    password = get_change(changeset, :password)

    if hash_password? && password && changeset.valid? do
      changeset
      |> validate_length(:password, max: 72, count: :bytes)
      |> put_change(:hashed_password, Bcrypt.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end

  @doc """
  Provjerava lozinku.

  Bez admina se svejedno poziva `Bcrypt.no_user_verify/0`, da trajanje
  odgovora ne otkrije postoji li email.
  """
  def valid_password?(%__MODULE__{hashed_password: hashed_password}, password)
      when is_binary(hashed_password) and byte_size(password) > 0 do
    Bcrypt.verify_pass(password, hashed_password)
  end

  def valid_password?(_, _) do
    Bcrypt.no_user_verify()
    false
  end
end
