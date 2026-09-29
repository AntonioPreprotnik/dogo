defmodule Mix.Tasks.ImportTasksTest do
  @moduledoc """
  Naredbe iz README-a samo stavljaju job u red; ovdje se provjerava da
  argumenti komandne linije stignu do joba ispravno pretvoreni.
  """
  # Mix.shell je globalna postavka, pa test ne ide paralelno s drugima.
  use Dogo.DataCase, async: false
  use Oban.Testing, repo: Dogo.Repo

  alias Dogo.Import.Jobs.ImportBeaches
  alias Dogo.Import.Jobs.ImportIslands

  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
  end

  describe "mix beaches.import" do
    test "bez argumenata uvozi cijelu Hrvatsku" do
      Mix.Tasks.Beaches.Import.run([])

      assert_enqueued(worker: ImportBeaches, args: %{})
      assert_received {:mix_shell, :info, ["Uvoz je u redu" <> _]}
    end

    test "bbox i timeout postaju argumenti joba" do
      Mix.Tasks.Beaches.Import.run(["--bbox", "43.49, 16.41,43.52,16.48", "--timeout", "60"])

      assert_enqueued(
        worker: ImportBeaches,
        args: %{"bbox" => [43.49, 16.41, 43.52, 16.48], "timeout" => 60}
      )
    end

    test "bbox s krivim brojem koordinata je greška" do
      assert_raise Mix.Error, ~r/--bbox ocekuje/, fn ->
        Mix.Tasks.Beaches.Import.run(["--bbox", "43.49,16.41"])
      end

      refute_enqueued(worker: ImportBeaches)
    end

    test "koordinata koja nije broj je greška" do
      assert_raise Mix.Error, ~r/Neispravna koordinata: abc/, fn ->
        Mix.Tasks.Beaches.Import.run(["--bbox", "43.49,abc,43.52,16.48"])
      end
    end
  end

  describe "mix islands.import" do
    test "bez argumenata koristi zadane vrijednosti" do
      Mix.Tasks.Islands.Import.run([])

      assert_enqueued(worker: ImportIslands, args: %{})
      assert_received {:mix_shell, :info, ["Uvoz otoka je u redu" <> _]}
    end

    test "prag površine i veličina serije postaju argumenti joba" do
      Mix.Tasks.Islands.Import.run(["--min-area", "5", "--batch-size", "4"])

      assert_enqueued(worker: ImportIslands, args: %{"min_area_km2" => 5.0, "batch_size" => 4})
    end
  end
end
