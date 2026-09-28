defmodule Dogo.Geo.Island do
  @moduledoc """
  Hrvatski otok, kao poligon iz OpenStreetMapa.

  Služi za odgovor na pitanje "je li ova plaža preko mora?" — vidi
  `Dogo.Geo.Islands`.
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "islands" do
    field :osm_id, :string
    field :name, :string
    field :geom, Geo.PostGIS.Geometry
    field :area_m2, :float

    timestamps(type: :utc_datetime)
  end
end
