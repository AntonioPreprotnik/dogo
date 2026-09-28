defmodule Dogo.Geo.PlaceCache do
  @moduledoc """
  ETS cache rezultata geokodiranja.

  Nominatimova usage policy izrijekom traži cacheiranje. Imena mjesta se ne
  mijenjaju, pa je i dugi TTL bezopasan, a većina upita u praksi su ista
  prefiksna kucanja ("spl", "spli", "split").
  """
  use GenServer

  @table __MODULE__
  @default_ttl_ms :timer.hours(24)

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Vraća `{:ok, value}` ili `:miss`."
  @spec fetch(String.t()) :: {:ok, term()} | :miss
  def fetch(key) do
    case :ets.lookup(@table, key) do
      [{^key, value, expires_at}] ->
        if monotonic_ms() < expires_at, do: {:ok, value}, else: :miss

      [] ->
        :miss
    end
  rescue
    ArgumentError -> :miss
  end

  @doc "Sprema vrijednost pod ključem."
  @spec put(String.t(), term()) :: :ok
  def put(key, value) do
    :ets.insert(@table, {key, value, monotonic_ms() + ttl_ms()})
    :ok
  rescue
    ArgumentError -> :ok
  end

  @doc "Prazni cache. Za testove."
  def clear do
    :ets.delete_all_objects(@table)
    :ok
  rescue
    ArgumentError -> :ok
  end

  @impl GenServer
  def init(_opts) do
    # `read_concurrency`: cita se iz svakog LiveView procesa, pise rijetko.
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    {:ok, %{}}
  end

  # `|| @default_ttl_ms` namjerno: kljuc eksplicitno postavljen na nil ne smije
  # srusiti cache. Default u get_env/3 pokriva samo nepostojeci kljuc.
  defp ttl_ms, do: Application.get_env(:dogo, :place_cache_ttl_ms) || @default_ttl_ms
  defp monotonic_ms, do: System.monotonic_time(:millisecond)
end
