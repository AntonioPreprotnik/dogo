defmodule Dogo.Import.Attributes do
  @moduledoc """
  Pretvara Overpass element u atribute plaže.

  OSM za hrvatske plaže gotovo nikad nema `dog=*` tag, a demo bez tog podatka
  nema smisla. Zato se nedostajući atributi **generiraju iz osm_id-a**: isti
  ulaz uvijek daje isti rezultat, pa uvoz ostaje idempotentan, a demo izgleda
  isto pri svakom pokretanju.

  Izvor statusa se uvijek bilježi u `dog_status_source`, a sučelje ga prikazuje
  (E1-S5) — generirani podatak se nikad ne predstavlja kao stvarno pravilo.
  """

  alias Dogo.Import.Overpass.Element

  # Vjerojatnosti u postocima. Zbroj designated + allowed je namjerno manjina:
  # plaža na kojima je pas izričito dobrodošao stvarno je malo.
  @dog_status_distribution [designated: 8, allowed: 22, not_allowed: 30, unknown: 40]
  @surface_distribution [pebble: 50, rock: 20, sand: 15, concrete: 10, mixed: 5]

  # Sadržaj => vjerojatnost da postoji, u postocima.
  @amenity_distribution %{
    "dog_shower" => 25,
    "shade" => 45,
    "water" => 35,
    "bins" => 60,
    "parking" => 55
  }

  @osm_dog_values %{
    "designated" => :designated,
    "yes" => :allowed,
    "leashed" => :allowed,
    "on_leash" => :allowed,
    "no" => :not_allowed
  }

  @osm_surface_values %{
    "sand" => :sand,
    "pebbles" => :pebble,
    "pebblestone" => :pebble,
    "gravel" => :pebble,
    "fine_gravel" => :pebble,
    "rock" => :rock,
    "bare_rock" => :rock,
    "stone" => :rock,
    "concrete" => :concrete,
    "paving_stones" => :concrete,
    "mixed" => :mixed
  }

  @doc """
  Atributi spremni za `Dogo.Beaches.Beach.changeset/2`.
  """
  @spec build(Element.t()) :: map()
  def build(%Element{} = element) do
    {dog_status, source} = dog_status(element)

    %{
      osm_id: element.osm_id,
      name: element.name,
      geom: element.centroid,
      area: element.area,
      surface: surface(element),
      dog_status: dog_status,
      dog_status_source: source,
      amenities: amenities(element.osm_id, dog_status),
      municipality: municipality(element)
    }
  end

  @doc """
  Status za pse i njegov izvor.

  OSM tag ima prednost; nepoznata vrijednost taga tretira se kao da taga nema,
  jer bi je inače prikazali kao provjeren podatak.
  """
  @spec dog_status(Element.t()) :: {atom(), :osm | :generated}
  def dog_status(%Element{tags: tags, osm_id: osm_id}) do
    case Map.fetch(@osm_dog_values, tags["dog"] || "") do
      {:ok, status} -> {status, :osm}
      :error -> {pick(osm_id, "dog_status", @dog_status_distribution), :generated}
    end
  end

  @doc "Podloga iz OSM taga `surface`, inače generirana."
  @spec surface(Element.t()) :: atom()
  def surface(%Element{tags: tags, osm_id: osm_id}) do
    Map.get_lazy(@osm_surface_values, tags["surface"] || "", fn ->
      pick(osm_id, "surface", @surface_distribution)
    end)
  end

  @doc """
  Sadržaji plaže, generirani iz osm_id-a.

  Tuš za pse postoji samo tamo gdje su psi uopće dozvoljeni — inače demo
  proturječi sam sebi.
  """
  @spec amenities(String.t(), atom()) :: %{String.t() => boolean()}
  def amenities(osm_id, dog_status) do
    dogs_welcome? = dog_status in [:designated, :allowed]

    Map.new(@amenity_distribution, fn {amenity, probability} ->
      present? = draw(osm_id, amenity) < probability

      {amenity, present? and (amenity != "dog_shower" or dogs_welcome?)}
    end)
  end

  @doc "Općina iz OSM adresnih tagova; ne generira se jer bi bila neprovjerljiva."
  @spec municipality(Element.t()) :: String.t() | nil
  def municipality(%Element{tags: tags}) do
    tags["addr:city"] || tags["is_in:city"] || tags["addr:municipality"]
  end

  # Deterministički broj 0..99 iz osm_id-a i imena polja. SHA-256 je stabilan
  # kroz verzije OTP-a, za razliku od :erlang.phash2/1.
  defp draw(osm_id, field) do
    <<value::unsigned-integer-16, _rest::binary>> =
      :crypto.hash(:sha256, "#{osm_id}|#{field}")

    rem(value, 100)
  end

  defp pick(osm_id, field, distribution) do
    draw = draw(osm_id, field)

    {value, _} =
      Enum.reduce_while(distribution, {nil, 0}, fn {value, weight}, {_, acc} ->
        if draw < acc + weight, do: {:halt, {value, acc}}, else: {:cont, {value, acc + weight}}
      end)

    value
  end
end
