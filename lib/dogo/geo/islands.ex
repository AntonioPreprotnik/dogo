defmodule Dogo.Geo.Islands do
  @moduledoc """
  Otoci i pitanje "treba li mi trajekt?".

  Zračna udaljenost na Jadranu vara: plaža koja je 3 km zračno može biti dva
  sata puta ako je preko kanala. Ovaj modul odgovara na to pitanje.

  Model je namjerno grub i zato predvidiv: svijet se dijeli na **kopno** (i sve
  otoke povezane mostom) i na **pojedinačne otoke bez mosta**. Unutar iste
  skupine se vozi, između njih se plovi.
  """

  import Ecto.Query

  alias Dogo.Geo.Island
  alias Dogo.Repo

  # Ista tolerancija kao pri pridruživanju plaža otocima: točka zna pasti koji
  # metar u more, a kanali su svugdje puno širi.
  @snap_distance_m 150

  @typedoc """
  Gdje se netko nalazi: `:mainland` (kopno ili otok s mostom) ili konkretan
  otok bez mosta.
  """
  @type location :: :mainland | %Island{}

  @doc """
  Otok na kojem je zadana točka, ili `nil` ako je na kopnu.
  """
  @spec at(Geo.Point.t() | nil, keyword()) :: Island.t() | nil
  def at(point, opts \\ [])
  def at(nil, _opts), do: nil

  def at(%Geo.Point{} = point, opts) do
    query =
      from i in Island,
        where:
          fragment(
            "ST_DWithin(?::geography, ?::geography, ?)",
            i.geom,
            type(^point, Geo.PostGIS.Geometry),
            ^@snap_distance_m
          ),
        order_by:
          fragment(
            "ST_Distance(?::geography, ?::geography)",
            i.geom,
            type(^point, Geo.PostGIS.Geometry)
          ),
        limit: 1

    Repo.one(query, Keyword.take(opts, [:log]))
  end

  @doc """
  Dolazi li se do ovog mjesta cestom s kopna?

  Kopno (`nil`) i otoci s mostom — da. Ostali otoci — ne.
  """
  @spec road_connected?(Island.t() | nil) :: boolean()
  def road_connected?(nil), do: true
  def road_connected?(%Island{bridge_connected: bridge_connected}), do: bridge_connected

  @doc """
  Treba li trajekt za put s jednog mjesta na drugo?

  Oba argumenta su otok ili `nil` za kopno.

      iex> Dogo.Geo.Islands.across_sea?(nil, nil)
      false
  """
  @spec across_sea?(Island.t() | nil, Island.t() | nil) :: boolean()
  def across_sea?(from, to) do
    cond do
      # Ista kopnena masa: nema mora između.
      island_id(from) == island_id(to) -> false
      # Oba su spojena na cestovnu mrežu kopna, pa se može voziti okolo.
      road_connected?(from) and road_connected?(to) -> false
      true -> true
    end
  end

  defp island_id(nil), do: nil
  defp island_id(%Island{id: id}), do: id
end
