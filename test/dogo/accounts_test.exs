defmodule Dogo.AccountsTest do
  @moduledoc "E8-S1: admini i sesije."
  use Dogo.DataCase, async: true

  import Dogo.AccountsFixtures

  alias Dogo.Accounts
  alias Dogo.Accounts.Admin
  alias Dogo.Accounts.AdminToken

  describe "get_admin_by_email_and_password/2" do
    test "nepoznat email ne vraća admina" do
      refute Accounts.get_admin_by_email_and_password("unknown@example.com", "hello world!")
    end

    test "kriva lozinka ne vraća admina" do
      admin = admin_fixture()
      refute Accounts.get_admin_by_email_and_password(admin.email, "invalid")
    end

    test "ispravni podaci vraćaju admina, email bez obzira na velika slova" do
      %{id: id} = admin = admin_fixture()

      assert %Admin{id: ^id} =
               Accounts.get_admin_by_email_and_password(admin.email, valid_admin_password())

      assert %Admin{id: ^id} =
               Accounts.get_admin_by_email_and_password(
                 String.upcase(admin.email),
                 valid_admin_password()
               )
    end
  end

  describe "get_admin!/1" do
    test "diže za nepostojeći ID" do
      assert_raise Ecto.NoResultsError, fn -> Accounts.get_admin!(-1) end
    end
  end

  describe "create_admin/1" do
    test "traži email i lozinku" do
      {:error, changeset} = Accounts.create_admin(%{})

      assert %{email: ["can't be blank"], password: ["can't be blank"]} = errors_on(changeset)
    end

    test "provjerava format emaila i duljinu lozinke" do
      {:error, changeset} = Accounts.create_admin(%{email: "not valid", password: "short"})

      assert "must have the @ sign and no spaces" in errors_on(changeset).email
      assert "should be at least 12 character(s)" in errors_on(changeset).password
    end

    test "odbija predugu lozinku (bcrypt gleda samo 72 bajta)" do
      {:error, changeset} =
        Accounts.create_admin(%{email: unique_admin_email(), password: String.duplicate("a", 73)})

      assert "should be at most 72 character(s)" in errors_on(changeset).password
    end

    test "email je jedinstven bez obzira na velika slova" do
      admin = admin_fixture()

      {:error, changeset} =
        Accounts.create_admin(valid_admin_attributes(email: String.upcase(admin.email)))

      assert "has already been taken" in errors_on(changeset).email
    end

    test "sprema hash, a ne lozinku" do
      admin = admin_fixture()

      assert is_binary(admin.hashed_password)
      assert is_nil(admin.password)
      refute admin.hashed_password == valid_admin_password()
    end
  end

  describe "create_admin_with_random_password/1" do
    test "vraća lozinku kojom se admin može prijaviti" do
      email = unique_admin_email()

      assert {:ok, %Admin{id: id}, password} = Accounts.create_admin_with_random_password(email)
      assert String.length(password) >= 20
      assert %Admin{id: ^id} = Accounts.get_admin_by_email_and_password(email, password)
    end

    test "vraća grešku za neispravan email" do
      assert {:error, %Ecto.Changeset{}} = Accounts.create_admin_with_random_password("nope")
    end
  end

  describe "sudo_mode?/2" do
    test "ovisi o vremenu zadnje prijave" do
      now = DateTime.utc_now()

      assert Accounts.sudo_mode?(%Admin{authenticated_at: now})
      assert Accounts.sudo_mode?(%Admin{authenticated_at: DateTime.add(now, -19, :minute)})
      refute Accounts.sudo_mode?(%Admin{authenticated_at: DateTime.add(now, -21, :minute)})
      refute Accounts.sudo_mode?(%Admin{authenticated_at: DateTime.add(now, -11, :minute)}, -10)
      refute Accounts.sudo_mode?(%Admin{})
    end
  end

  describe "update_admin_password/2" do
    setup do
      %{admin: admin_fixture()}
    end

    test "provjerava lozinku i potvrdu", %{admin: admin} do
      {:error, changeset} =
        Accounts.update_admin_password(admin, %{
          password: "short",
          password_confirmation: "another"
        })

      assert %{
               password: ["should be at least 12 character(s)"],
               password_confirmation: ["does not match password"]
             } = errors_on(changeset)
    end

    test "mijenja lozinku i briše sve sesije", %{admin: admin} do
      _ = Accounts.generate_admin_session_token(admin)

      {:ok, {admin, expired_tokens}} =
        Accounts.update_admin_password(admin, %{password: "new valid password"})

      assert [%AdminToken{}] = expired_tokens
      assert is_nil(admin.password)
      assert Accounts.get_admin_by_email_and_password(admin.email, "new valid password")
      refute Repo.get_by(AdminToken, admin_id: admin.id)
    end
  end

  describe "sesije" do
    setup do
      admin = admin_fixture()
      %{admin: admin, token: Accounts.generate_admin_session_token(admin)}
    end

    test "token je spremljen i vraća admina", %{admin: admin, token: token} do
      assert %AdminToken{context: "session"} = Repo.get_by(AdminToken, token: token)
      assert {session_admin, inserted_at} = Accounts.get_admin_by_session_token(token)
      assert session_admin.id == admin.id
      assert session_admin.authenticated_at != nil
      assert inserted_at != nil
    end

    test "nepoznat token ne vraća admina" do
      refute Accounts.get_admin_by_session_token("oops")
    end

    test "istekao token ne vraća admina", %{token: token} do
      dt = ~N[2020-01-01 00:00:00]
      {1, nil} = Repo.update_all(AdminToken, set: [inserted_at: dt, authenticated_at: dt])

      refute Accounts.get_admin_by_session_token(token)
    end

    test "odjava briše token", %{token: token} do
      assert Accounts.delete_admin_session_token(token) == :ok
      refute Accounts.get_admin_by_session_token(token)
    end

    test "novi token preuzima vrijeme prijave admina", %{admin: admin} do
      authenticated_at = DateTime.add(DateTime.utc_now(:second), -3600)
      token = Accounts.generate_admin_session_token(%{admin | authenticated_at: authenticated_at})

      assert Repo.get_by(AdminToken, token: token).authenticated_at == authenticated_at
    end
  end

  test "inspect ne ispisuje lozinku ni hash" do
    refute inspect(%Admin{password: "123456", hashed_password: "abc"}) =~ "123456"
    refute inspect(%Admin{password: "123456", hashed_password: "abc"}) =~ "abc"
  end
end
