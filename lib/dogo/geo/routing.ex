defmodule Dogo.Geo.Routing do
  @moduledoc """
  Procjena vožnje od jedne točke do više odredišta, iza behavioura.

  Zračna udaljenost na Jadranu vara i kad nema mora između: cesta ide oko
  uvale, preko prijevoja, kroz naselje. Ovo daje broj koji korisnika stvarno
  zanima — koliko mu treba.

  Servis je javni demo OSRM-a i zato se tretira kao **neobavezan**: ako ne
  odgovori na vrijeme, aplikacija prikaže zračnu udaljenost i nastavi dalje.
  """

  @type leg :: %{duration_s: float(), distance_m: float()}

  @doc """
  Trajanje i duljina vožnje od `origin` do svakog odredišta.

  Vraća popis iste duljine kao `destinations`; `nil` je odredište do kojeg
  ruta nije pronađena.
  """
  @callback table(Geo.Point.t(), [Geo.Point.t()]) :: {:ok, [leg() | nil]} | {:error, term()}

  @spec table(Geo.Point.t(), [Geo.Point.t()]) :: {:ok, [leg() | nil]} | {:error, term()}
  def table(_origin, []), do: {:ok, []}
  def table(origin, destinations), do: impl().table(origin, destinations)

  defp impl, do: Application.get_env(:dogo, :routing_client, Dogo.Geo.Routing.OSRM)
end
