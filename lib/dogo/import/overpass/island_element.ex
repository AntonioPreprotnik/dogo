defmodule Dogo.Import.Overpass.IslandElement do
  @moduledoc """
  Otok iz Overpassa, sveden na ono što je potrebno za izgradnju poligona.

  `lines` je popis linija. Zatvorena linija (`way`) daje jednu, a relacija po
  jednu za svaki vanjski član. Sastavljanje u poligon prepuštamo PostGIS-u —
  vidi `Dogo.Import.Islands`.
  """

  @type line :: [{float(), float()}]

  @type t :: %__MODULE__{
          osm_id: String.t(),
          name: String.t() | nil,
          lines: [line()]
        }

  @enforce_keys [:osm_id, :lines]
  defstruct [:osm_id, :name, lines: []]
end
