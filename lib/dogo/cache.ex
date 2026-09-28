defmodule Dogo.Cache do
  @moduledoc """
  Jednostavan ETS cache s vremenom isteka.

  Koristi se za odgovore vanjskih servisa: geokodiranja (`Dogo.Geo.PlaceCache`)
  i rutiranja (`Dogo.Geo.RouteCache`). Obje usluge su besplatne i imaju usage
  policy koji cacheiranje izrijekom traži.

  Tablica je `:public` i `read_concurrency: true` — čita se iz svakog
  LiveView procesa, piše rijetko.
  """
  use GenServer

  @type table :: atom()

  @doc "Pokreće cache. Obavezna opcija `:table`, neobavezna `:ttl_ms`."
  def start_link(opts) do
    table = Keyword.fetch!(opts, :table)
    GenServer.start_link(__MODULE__, opts, name: table)
  end

  @doc "Vraća `{:ok, value}` ili `:miss`."
  @spec fetch(table(), term()) :: {:ok, term()} | :miss
  def fetch(table, key) do
    case :ets.lookup(table, key) do
      [{^key, value, expires_at}] ->
        if monotonic_ms() < expires_at, do: {:ok, value}, else: :miss

      [] ->
        :miss
    end
  rescue
    # Tablica jos ne postoji (npr. u testu bez pokrenute aplikacije).
    ArgumentError -> :miss
  end

  @doc "Sprema vrijednost pod ključem."
  @spec put(table(), term(), term(), keyword()) :: :ok
  def put(table, key, value, opts \\ []) do
    ttl = Keyword.get(opts, :ttl_ms) || ttl_ms(table)
    :ets.insert(table, {key, value, monotonic_ms() + ttl})
    :ok
  rescue
    ArgumentError -> :ok
  end

  @doc "Prazni cache. Za testove."
  @spec clear(table()) :: :ok
  def clear(table) do
    :ets.delete_all_objects(table)
    :ok
  rescue
    ArgumentError -> :ok
  end

  @impl GenServer
  def init(opts) do
    table = Keyword.fetch!(opts, :table)
    :ets.new(table, [:named_table, :public, :set, read_concurrency: true])

    {:ok, %{table: table}}
  end

  # `||` namjerno: ključ eksplicitno postavljen na nil ne smije srušiti cache.
  # Default u `get_env/3` pokriva samo nepostojeći ključ.
  defp ttl_ms(table) do
    Application.get_env(:dogo, :"#{table}_ttl_ms") || :timer.hours(24)
  end

  defp monotonic_ms, do: System.monotonic_time(:millisecond)
end
