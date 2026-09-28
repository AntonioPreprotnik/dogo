defmodule Dogo.Import.AttributesTest do
  use ExUnit.Case, async: true

  alias Dogo.Beaches.Beach
  alias Dogo.Import.Attributes
  alias Dogo.Import.Overpass.Element

  defp element(osm_id, tags \\ %{}) do
    %Element{
      osm_id: osm_id,
      name: tags["name"],
      centroid: %Geo.Point{coordinates: {16.44, 43.50}, srid: 4326},
      tags: tags
    }
  end

  describe "OSM ima podatak" do
    test "dog=designated se preuzima i izvor je :osm" do
      assert %{dog_status: :designated, dog_status_source: :osm} =
               Attributes.build(element("way/1", %{"dog" => "designated"}))
    end

    test "dog=leashed je :allowed" do
      assert %{dog_status: :allowed, dog_status_source: :osm} =
               Attributes.build(element("way/2", %{"dog" => "leashed"}))
    end

    test "dog=no je :not_allowed" do
      assert %{dog_status: :not_allowed, dog_status_source: :osm} =
               Attributes.build(element("way/3", %{"dog" => "no"}))
    end

    test "nepoznata vrijednost taga se ne predstavlja kao OSM podatak" do
      assert %{dog_status_source: :generated} =
               Attributes.build(element("way/4", %{"dog" => "ponekad"}))
    end

    test "surface iz OSM-a se mapira na nasu enumeraciju" do
      assert %{surface: :pebble} = Attributes.build(element("way/5", %{"surface" => "pebbles"}))
      assert %{surface: :sand} = Attributes.build(element("way/6", %{"surface" => "sand"}))
      assert %{surface: :rock} = Attributes.build(element("way/7", %{"surface" => "bare_rock"}))
    end

    test "opcina dolazi iz adresnih tagova" do
      assert %{municipality: "Split"} =
               Attributes.build(element("way/8", %{"addr:city" => "Split"}))

      assert %{municipality: nil} = Attributes.build(element("way/9"))
    end
  end

  describe "determinizam" do
    test "dva pokretanja daju identicne atribute" do
      element = element("way/123456")

      assert Attributes.build(element) == Attributes.build(element)
    end

    test "rezultat ovisi samo o osm_id-u, ne o redoslijedu uvoza" do
      first = Attributes.build(element("way/123456"))
      second = Attributes.build(element("way/999999"))
      first_again = Attributes.build(element("way/123456"))

      assert first == first_again

      refute Map.take(first, [:dog_status, :surface, :amenities]) ==
               Map.take(second, [:dog_status, :surface, :amenities])
    end

    test "vrijednosti su zakucane, pa promjena algoritma ne prode nezapazeno" do
      # Ako ovaj test padne, generirani demo se promijenio za sve plaze.
      assert %{
               dog_status: :not_allowed,
               surface: :pebble,
               amenities: %{
                 "bins" => true,
                 "dog_shower" => false,
                 "parking" => true,
                 "shade" => false,
                 "water" => true
               }
             } = Attributes.build(element("way/234567891"))
    end
  end

  describe "raspodjela" do
    setup do
      generated =
        for id <- 1..5_000, do: Attributes.build(element("way/#{id}"))

      %{generated: generated, total: length(generated)}
    end

    test "sve vrijednosti su unutar dozvoljene enumeracije", %{generated: generated} do
      assert Enum.all?(generated, &(&1.dog_status in Beach.dog_statuses()))
      assert Enum.all?(generated, &(&1.surface in Beach.surfaces()))
    end

    test "plaze na kojima je pas dobrodosao su manjina", %{generated: generated, total: total} do
      welcoming =
        Enum.count(generated, &(&1.dog_status in [:designated, :allowed]))

      assert welcoming / total < 0.4
      assert welcoming / total > 0.2
    end

    test "svaki status se pojavljuje", %{generated: generated} do
      statuses = generated |> Enum.map(& &1.dog_status) |> Enum.uniq() |> Enum.sort()

      assert statuses == Enum.sort(Beach.dog_statuses())
    end
  end

  describe "sadrzaji" do
    test "kljucevi su tocno oni koje shema prepoznaje" do
      %{amenities: amenities} = Attributes.build(element("way/10"))

      assert amenities |> Map.keys() |> Enum.sort() == Enum.sort(Beach.amenity_keys())
      assert Enum.all?(Map.values(amenities), &is_boolean/1)
    end

    test "tus za pse ne postoji tamo gdje psi nisu dozvoljeni" do
      forbidden =
        for id <- 1..500,
            attrs = Attributes.build(element("way/#{id}")),
            attrs.dog_status in [:not_allowed, :unknown],
            do: attrs.amenities["dog_shower"]

      assert forbidden != []
      assert Enum.all?(forbidden, &(&1 == false))
    end

    test "tus za pse ponekad postoji tamo gdje psi jesu dozvoljeni" do
      allowed =
        for id <- 1..500,
            attrs = Attributes.build(element("way/#{id}")),
            attrs.dog_status in [:designated, :allowed],
            do: attrs.amenities["dog_shower"]

      assert Enum.any?(allowed)
    end
  end

  test "generirani atributi prolaze changeset sheme" do
    attrs = Attributes.build(element("way/42", %{"name" => "Testna"}))

    assert %Ecto.Changeset{valid?: true} = Beach.changeset(%Beach{}, attrs)
  end
end
