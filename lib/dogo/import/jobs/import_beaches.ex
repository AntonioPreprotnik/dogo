defmodule Dogo.Import.Jobs.ImportBeaches do
  @moduledoc """
  Oban job koji uvozi plaže s Overpassa.

  Job je idempotentan (upsert po `osm_id`), pa ga je sigurno ponovno pokrenuti.
  `unique` sprječava da se u redu nakupi više istih uvoza — Overpass ima
  ograničenja i ne želimo ga gađati paralelno.
  """
  use Oban.Worker,
    queue: :imports,
    max_attempts: 3,
    unique: [period: 300, states: [:available, :scheduled, :executing, :retryable]]

  alias Dogo.Import

  # Oban tretira {:ok, _} kao uspjeh, a {:error, _} kao neuspjeh i ponavlja
  # job — sto je tocno ono sto zelimo kad je Overpass preopterecen.
  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    args
    |> opts_from_args()
    |> Import.import_beaches()
  end

  @doc """
  Pretvara JSON argumente joba u opcije Overpass klijenta.

  Bbox stiže kao lista brojeva, jer JSON nema torke.
  """
  def opts_from_args(args) do
    []
    |> put_bbox(args["bbox"])
    |> put_timeout(args["timeout"])
  end

  defp put_bbox(opts, [min_lat, min_lon, max_lat, max_lon]) do
    Keyword.put(opts, :bbox, {min_lat, min_lon, max_lat, max_lon})
  end

  defp put_bbox(opts, _), do: opts

  defp put_timeout(opts, timeout) when is_integer(timeout),
    do: Keyword.put(opts, :timeout, timeout)

  defp put_timeout(opts, _), do: opts
end
