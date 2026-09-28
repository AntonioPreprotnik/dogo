defmodule Dogo.Geo.Geocoder do
  @moduledoc """
  Pretvaranje imena mjesta u koordinate, iza behavioura.

  Implementacija se bira konfiguracijom, pa testovi podmeću mock i nikad ne
  diraju mrežu:

      config :dogo, :geocoder, Dogo.Geo.Geocoder.Nominatim
  """

  alias Dogo.Geo.Place

  @callback search(String.t()) :: {:ok, [Place.t()]} | {:error, term()}

  @doc """
  Traži mjesta po imenu. Prazan ili prekratak upit ne ide dalje od ovog reda —
  Nominatim ne treba gnjaviti s jednim slovom.
  """
  @spec search(String.t()) :: {:ok, [Place.t()]} | {:error, term()}
  def search(query) when is_binary(query) do
    query = String.trim(query)

    if String.length(query) < 3 do
      {:ok, []}
    else
      impl().search(query)
    end
  end

  def search(_query), do: {:ok, []}

  defp impl, do: Application.get_env(:dogo, :geocoder, Dogo.Geo.Geocoder.Nominatim)
end
