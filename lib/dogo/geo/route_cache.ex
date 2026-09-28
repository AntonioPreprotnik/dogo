defmodule Dogo.Geo.RouteCache do
  @moduledoc """
  Cache OSRM odgovora.

  Ključ su zaokružene koordinate polazišta i odredišta, pa isti pogled na kartu
  ne gnjavi servis dvaput. TTL je kraći nego kod mjesta: ceste se mijenjaju
  češće od imena naselja, a i procjena vremena vožnje stari.
  """

  alias Dogo.Cache

  @table __MODULE__

  @doc false
  def child_spec(_opts) do
    Supervisor.child_spec({Cache, table: @table}, id: @table)
  end

  def fetch(key), do: Cache.fetch(@table, key)
  def put(key, value), do: Cache.put(@table, key, value, ttl_ms: ttl_ms())
  def clear, do: Cache.clear(@table)

  defp ttl_ms, do: Application.get_env(:dogo, :route_cache_ttl_ms) || :timer.hours(6)
end
