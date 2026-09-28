defmodule Dogo.Beaches.Beach do
  @moduledoc """
  Plaža uvezena iz OpenStreetMapa, s atributima relevantnima za vlasnike pasa.

  `geom` je centroid plaže i jedina obavezna geometrija; `area` je poligon kad
  ga OSM ima. Statusi vezani uz pse dijelom dolaze iz OSM tagova, a dijelom su
  generirani (vidi `dog_status_source`) — projekt je demonstracijski.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @surfaces [:pebble, :sand, :rock, :concrete, :mixed, :unknown]
  @dog_statuses [:designated, :allowed, :not_allowed, :unknown]
  @dog_status_sources [:osm, :generated]
  @amenity_keys ~w(dog_shower shade water bins parking)

  @type t :: %__MODULE__{}

  schema "beaches" do
    field :osm_id, :string
    field :name, :string
    field :geom, Geo.PostGIS.Geometry
    field :area, Geo.PostGIS.Geometry
    field :surface, Ecto.Enum, values: @surfaces, default: :unknown
    field :dog_status, Ecto.Enum, values: @dog_statuses, default: :unknown
    field :dog_status_source, Ecto.Enum, values: @dog_status_sources, default: :generated
    field :amenities, :map, default: %{}
    field :municipality, :string

    belongs_to :island, Dogo.Geo.Island

    # Popunjava ga prostorni upit, ne baza.
    field :distance_m, :float, virtual: true

    timestamps(type: :utc_datetime)
  end

  @doc "Popis dozvoljenih vrijednosti za `surface`."
  def surfaces, do: @surfaces

  @doc "Popis dozvoljenih vrijednosti za `dog_status`."
  def dog_statuses, do: @dog_statuses

  @doc "Popis prepoznatih ključeva u `amenities`."
  def amenity_keys, do: @amenity_keys

  @doc """
  Changeset za uvoz i ručno uređivanje plaže.
  """
  def changeset(beach, attrs) do
    beach
    |> cast(attrs, [
      :osm_id,
      :name,
      :geom,
      :area,
      :surface,
      :dog_status,
      :dog_status_source,
      :amenities,
      :municipality
    ])
    |> validate_required([:osm_id, :geom])
    |> validate_point(:geom)
    |> validate_amenities()
    |> unique_constraint(:osm_id)
  end

  defp validate_point(changeset, field) do
    validate_change(changeset, field, fn ^field, value ->
      cond do
        not match?(%Geo.Point{}, value) ->
          [{field, "mora biti točka (Geo.Point)"}]

        value.srid != Dogo.Geo.srid() ->
          [{field, "mora biti u SRID-u #{Dogo.Geo.srid()}"}]

        not Dogo.Geo.within_croatia?(value) ->
          [{field, "mora biti unutar bounding boxa hrvatske obale"}]

        true ->
          []
      end
    end)
  end

  defp validate_amenities(changeset) do
    validate_change(changeset, :amenities, fn :amenities, amenities ->
      unknown = Map.keys(amenities) -- @amenity_keys
      non_boolean = for {key, value} <- amenities, not is_boolean(value), do: key

      cond do
        unknown != [] -> [amenities: "nepoznati sadržaji: #{Enum.join(unknown, ", ")}"]
        non_boolean != [] -> [amenities: "vrijednosti moraju biti true/false"]
        true -> []
      end
    end)
  end
end
