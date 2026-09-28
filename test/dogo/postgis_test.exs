defmodule Dogo.PostgisTest do
  @moduledoc """
  E0-S2: PostGIS is enabled and `Geo` structs survive a round trip through a
  `geometry(Point, 4326)` column.
  """
  use Dogo.DataCase, async: true

  alias Ecto.Adapters.SQL

  @split_rock %Geo.Point{coordinates: {16.4402, 43.5081}, srid: 4326}

  setup do
    SQL.query!(Dogo.Repo, """
    CREATE TEMPORARY TABLE geo_roundtrip (
      id serial PRIMARY KEY,
      geom geometry(Point, 4326)
    ) ON COMMIT DROP
    """)

    :ok
  end

  test "postgis extension is installed" do
    %{rows: [[version]]} = SQL.query!(Dogo.Repo, "SELECT PostGIS_Lib_Version()")
    assert version =~ ~r/^\d+\.\d+/
  end

  test "a point written to a geometry column reads back unchanged" do
    SQL.query!(Dogo.Repo, "INSERT INTO geo_roundtrip (geom) VALUES ($1)", [@split_rock])

    %{rows: [[point]]} = SQL.query!(Dogo.Repo, "SELECT geom FROM geo_roundtrip", [])

    assert point == @split_rock
  end

  test "distances are computed on the geography type, in metres" do
    dubrovnik = %Geo.Point{coordinates: {18.0944, 42.6507}, srid: 4326}

    %{rows: [[metres]]} =
      SQL.query!(Dogo.Repo, "SELECT ST_Distance($1::geography, $2::geography)", [
        @split_rock,
        dubrovnik
      ])

    # Split -> Dubrovnik is roughly 157 km as the crow flies.
    assert_in_delta metres / 1000, 157, 5
  end
end
