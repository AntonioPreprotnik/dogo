defmodule Dogo.Import.Overpass.Element do
  @moduledoc """
  Jedan element iz Overpass odgovora, sveden na ono što uvoz treba.

  `osm_id` je stabilan kroz uvoze i služi kao ključ upserta (E1-S3).
  """

  @type t :: %__MODULE__{
          osm_id: String.t(),
          name: String.t() | nil,
          centroid: Geo.Point.t(),
          area: Geo.MultiPolygon.t() | nil,
          tags: %{optional(String.t()) => String.t()}
        }

  @enforce_keys [:osm_id, :centroid]
  defstruct [:osm_id, :name, :centroid, :area, tags: %{}]
end
