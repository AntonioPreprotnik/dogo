defmodule Mix.Tasks.Islands.Import do
  @shortdoc "Stavlja uvoz poligona otoka u Oban red"

  @moduledoc """
  Stavlja `Dogo.Import.Jobs.ImportIslands` u red.

      mix islands.import
      mix islands.import --min-area 5

  Uvoz je idempotentan (upsert po `osm_id`) i nakon njega se plažama iznova
  pridružuju otoci.
  """
  use Mix.Task

  alias Dogo.Import.Jobs.ImportIslands

  @requirements ["app.start"]

  @impl Mix.Task
  def run(argv) do
    {opts, _rest} = OptionParser.parse!(argv, strict: [min_area: :float, batch_size: :integer])

    args =
      %{}
      |> maybe_put("min_area_km2", opts[:min_area])
      |> maybe_put("batch_size", opts[:batch_size])

    case args |> ImportIslands.new() |> Oban.insert() do
      {:ok, job} -> Mix.shell().info("Uvoz otoka je u redu (job ##{job.id}).")
      {:error, reason} -> Mix.raise("Job nije ubacen u red: #{inspect(reason)}")
    end
  end

  defp maybe_put(args, _key, nil), do: args
  defp maybe_put(args, key, value), do: Map.put(args, key, value)
end
