defmodule Dogo.Beaches.Beach do
  @moduledoc """
  Plaža uvezena iz OpenStreetMapa, s atributima relevantnima za vlasnike pasa.

  `geom` je centroid plaže i jedina obavezna geometrija; `area` je poligon kad
  ga OSM ima. Statusi vezani uz pse dijelom dolaze iz OSM tagova, a dijelom su
  generirani (vidi `dog_status_source`) — projekt je demonstracijski.

  Admin može plažu ručno ispraviti (`admin_changeset/2`). Tada se postavlja
  `edited_at` i uvoz je više ne dira; vidi
  `docs/adr/0011-rucne-izmjene-imaju-prednost-pred-uvozom.md`.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @surfaces [:pebble, :sand, :rock, :concrete, :mixed, :unknown]
  @dog_statuses [:designated, :allowed, :not_allowed, :unknown]
  @dog_status_sources [:osm, :generated, :manual]
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
    field :edited_at, :utc_datetime

    belongs_to :island, Dogo.Geo.Island

    # Popunjavaju ih upit i kontekst, ne baza.
    field :distance_m, :float, virtual: true
    field :across_sea, :boolean, virtual: true, default: false

    # Koordinate u admin formi; u bazu idu kao `geom`.
    field :lat, :float, virtual: true
    field :lon, :float, virtual: true

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

  @doc """
  Changeset za ručno uređivanje iz admina.

  Za razliku od `changeset/2` ne prima `osm_id`, `area` ni izvor statusa:
  `osm_id` ručno dodane plaže dodjeljuje kontekst, poligon se ne uređuje, a
  izvor postaje `:manual` čim admin promijeni status. Koordinate stižu kao
  `lat`/`lon` i pretvaraju se u `geom`.

  Svaka stvarna promjena postavlja `edited_at`.
  """
  def admin_changeset(beach, attrs) do
    beach
    |> put_coordinates()
    |> cast(normalize_amenities(attrs), [
      :name,
      :municipality,
      :surface,
      :dog_status,
      :amenities,
      :lat,
      :lon
    ])
    |> validate_required([:surface, :dog_status, :lat, :lon])
    |> validate_length(:name, max: 255)
    |> validate_length(:municipality, max: 255)
    |> validate_number(:lat, greater_than_or_equal_to: -90, less_than_or_equal_to: 90)
    |> validate_number(:lon, greater_than_or_equal_to: -180, less_than_or_equal_to: 180)
    |> put_geom()
    |> validate_point(:geom)
    |> validate_amenities()
    |> mark_status_manual()
    |> mark_edited()
  end

  @doc "Popunjava virtualna polja `lat` i `lon` iz `geom`."
  def put_coordinates(%__MODULE__{geom: %Geo.Point{coordinates: {lon, lat}}} = beach),
    do: %{beach | lat: lat, lon: lon}

  def put_coordinates(beach), do: beach

  # Checkboxi u formi šalju "true"/"false" kao tekst.
  defp normalize_amenities(%{"amenities" => %{} = amenities} = attrs) do
    Map.put(
      attrs,
      "amenities",
      Map.new(amenities, fn {key, value} -> {key, value in [true, "true"]} end)
    )
  end

  defp normalize_amenities(attrs), do: attrs

  defp put_geom(changeset) do
    lat = get_field(changeset, :lat)
    lon = get_field(changeset, :lon)

    if changeset.valid? and (changed?(changeset, :lat) or changed?(changeset, :lon)) do
      put_change(changeset, :geom, %Geo.Point{coordinates: {lon, lat}, srid: Dogo.Geo.srid()})
    else
      changeset
    end
  end

  defp mark_status_manual(changeset) do
    if changed?(changeset, :dog_status),
      do: put_change(changeset, :dog_status_source, :manual),
      else: changeset
  end

  defp mark_edited(%{changes: changes} = changeset) when map_size(changes) == 0, do: changeset

  defp mark_edited(changeset), do: put_change(changeset, :edited_at, DateTime.utc_now(:second))

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
