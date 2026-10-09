defmodule Mix.Tasks.Admin.CreateTest do
  @moduledoc "E8-S1: admin nastaje samo iz konzole."
  # Mix.shell je globalna postavka, pa test ne ide paralelno s drugima.
  use Dogo.DataCase, async: false

  alias Dogo.Accounts
  alias Mix.Tasks.Admin.Create

  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
  end

  test "stvara admina i ispisuje privremenu lozinku kojom se može prijaviti" do
    Create.run(["ana@example.com"])

    assert_received {:mix_shell, :info,
                     ["Admin ana@example.com stvoren. Privremena lozinka: " <> password]}

    assert Accounts.get_admin_by_email_and_password("ana@example.com", password)
  end

  test "neispravan email ili postojeći admin prekidaju naredbu" do
    Create.run(["ana@example.com"])

    assert_raise Mix.Error, ~r/has already been taken/, fn ->
      Create.run(["ana@example.com"])
    end

    assert_raise Mix.Error, ~r/Upotreba/, fn -> Create.run([]) end
  end
end
