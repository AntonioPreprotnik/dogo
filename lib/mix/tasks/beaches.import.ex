defmodule Mix.Tasks.Beaches.Import do
  @shortdoc "Stavlja uvoz plaza s Overpassa u Oban red"

  @moduledoc """
  Stavlja `Dogo.Import.Jobs.ImportBeaches` u red.

      mix beaches.import
      mix beaches.import --bbox 43.49,16.41,43.52,16.48
      mix beaches.import --timeout 60

  Zadatak samo ubacuje job; izvršava ga Oban radnik. Uvoz je idempotentan, pa
  je ponovno pokretanje sigurno.
  """
  use Mix.Task

  alias Dogo.Import.Jobs.ImportBeaches

  @requirements ["app.start"]

  @impl Mix.Task
  def run(argv) do
    {opts, _rest} = OptionParser.parse!(argv, strict: [bbox: :string, timeout: :integer])

    args =
      %{}
      |> maybe_put_bbox(opts[:bbox])
      |> maybe_put("timeout", opts[:timeout])

    case args |> ImportBeaches.new() |> Oban.insert() do
      {:ok, job} ->
        Mix.shell().info("Uvoz je u redu (job ##{job.id}).")

      {:error, reason} ->
        Mix.raise("Job nije ubacen u red: #{inspect(reason)}")
    end
  end

  defp maybe_put_bbox(args, nil), do: args

  defp maybe_put_bbox(args, bbox) do
    case String.split(bbox, ",") do
      [_, _, _, _] = parts ->
        Map.put(args, "bbox", Enum.map(parts, &parse_coordinate/1))

      _ ->
        Mix.raise("--bbox ocekuje min_lat,min_lon,max_lat,max_lon")
    end
  end

  defp parse_coordinate(value) do
    case value |> String.trim() |> Float.parse() do
      {number, ""} -> number
      _ -> Mix.raise("Neispravna koordinata: #{value}")
    end
  end

  defp maybe_put(args, _key, nil), do: args
  defp maybe_put(args, key, value), do: Map.put(args, key, value)
end
