defmodule Dogo.Geo.PlaceCache do
  @moduledoc """
  Cache rezultata geokodiranja.

  Nominatimova usage policy izrijekom traži cacheiranje. Imena mjesta se ne
  mijenjaju, pa je i dugi TTL bezopasan, a većina upita u praksi su ista
  prefiksna kucanja ("spl", "spli", "split").
  """

  alias Dogo.Cache

  @table __MODULE__

  @doc false
  def child_spec(_opts) do
    Supervisor.child_spec({Cache, table: @table}, id: @table)
  end

  @doc "Vraća `{:ok, value}` ili `:miss`."
  def fetch(key), do: Cache.fetch(@table, key)

  @doc "Sprema vrijednost pod ključem."
  def put(key, value), do: Cache.put(@table, key, value, ttl_ms: ttl_ms())

  @doc "Prazni cache. Za testove."
  def clear, do: Cache.clear(@table)

  defp ttl_ms, do: Application.get_env(:dogo, :place_cache_ttl_ms) || :timer.hours(24)
end
