defmodule Dogo.Import.Jobs.ImportIslands do
  @moduledoc """
  Oban job koji uvozi poligone otoka i pridružuje im plaže.

  Traje dulje od uvoza plaža jer geometrija ide u serijama, pa ima veći
  `max_attempts` i dulji `unique` prozor.
  """
  use Oban.Worker,
    queue: :imports,
    max_attempts: 3,
    unique: [period: 1800, states: [:available, :scheduled, :executing, :retryable]]

  alias Dogo.Import.Islands

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    args
    |> opts_from_args()
    |> Islands.import_islands()
  end

  @doc "Pretvara JSON argumente joba u opcije uvoza."
  def opts_from_args(args) do
    []
    |> put_number(:min_area_km2, args["min_area_km2"])
    |> put_number(:batch_size, args["batch_size"])
  end

  defp put_number(opts, key, value) when is_number(value), do: Keyword.put(opts, key, value)
  defp put_number(opts, _key, _value), do: opts
end
