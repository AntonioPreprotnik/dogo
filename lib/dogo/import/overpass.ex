defmodule Dogo.Import.Overpass do
  @moduledoc """
  Pristup Overpass API-ju, iza behavioura.

  Implementacija se bira konfiguracijom, pa testovi mogu podmetnuti mock i
  nikad ne diraju mrežu:

      config :dogo, :overpass_client, Dogo.Import.Overpass.HTTP
  """

  alias Dogo.Import.Overpass.Element
  alias Dogo.Import.Overpass.IslandElement

  @typedoc """
  Opcije uvoza.

  - `:bbox` — `{min_lat, min_lon, max_lat, max_lon}`; bez njega se uvozi
    cijela Hrvatska. Uvoz po regijama je mitigacija za Overpass timeoute.
  - `:timeout` — vrijednost `[timeout:...]` u samom upitu, u sekundama.
  """
  @type opts :: [bbox: {float(), float(), float(), float()}, timeout: pos_integer()]

  @callback fetch_beaches(opts()) :: {:ok, [Element.t()]} | {:error, term()}
  @callback fetch_islands(keyword()) :: {:ok, [IslandElement.t()]} | {:error, term()}

  @doc """
  Dohvaća plaže s Overpassa kroz konfiguriranu implementaciju.
  """
  @spec fetch_beaches(opts()) :: {:ok, [Element.t()]} | {:error, term()}
  def fetch_beaches(opts \\ []), do: impl().fetch_beaches(opts)

  @doc """
  Dohvaća poligone hrvatskih otoka.

  Opcije: `:min_area_km2` (zadano 1.0) i `:batch_size`.
  """
  @spec fetch_islands(keyword()) :: {:ok, [IslandElement.t()]} | {:error, term()}
  def fetch_islands(opts \\ []), do: impl().fetch_islands(opts)

  defp impl do
    Application.get_env(:dogo, :overpass_client, Dogo.Import.Overpass.HTTP)
  end
end
