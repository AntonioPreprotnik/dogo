defmodule Dogo.BeachesTest do
  use Dogo.DataCase, async: true

  import Dogo.BeachesFixtures

  alias Dogo.Beaches
  alias Dogo.Beaches.Beach
  alias Ecto.Adapters.SQL

  describe "create_beach/1" do
    test "sprema plažu i vraća geometriju kao Geo.Point" do
      assert {:ok, %Beach{} = beach} = Beaches.create_beach(valid_attrs())

      reloaded = Beaches.get_beach!(beach.id)
      assert reloaded.geom == point()
      assert reloaded.name == "Bačvice"
      assert reloaded.surface == :sand
      assert reloaded.dog_status == :allowed
      assert reloaded.amenities == %{"water" => true, "shade" => false}
    end

    test "zadane vrijednosti su 'unknown' i generirani izvor" do
      attrs =
        valid_attrs()
        |> Map.drop([:surface, :dog_status, :dog_status_source])

      assert {:ok, beach} = Beaches.create_beach(attrs)
      assert beach.surface == :unknown
      assert beach.dog_status == :unknown
      assert beach.dog_status_source == :generated
    end

    test "osm_id je obavezan i jedinstven" do
      assert {:error, changeset} = Beaches.create_beach(Map.delete(valid_attrs(), :osm_id))
      assert %{osm_id: ["can't be blank"]} = errors_on(changeset)

      attrs = valid_attrs(%{osm_id: osm_id("way/duplikat")})
      assert {:ok, _} = Beaches.create_beach(attrs)
      assert {:error, changeset} = Beaches.create_beach(attrs)
      assert %{osm_id: ["has already been taken"]} = errors_on(changeset)
    end
  end

  describe "changeset validacija geometrije" do
    test "odbija točku izvan hrvatske obale" do
      # Nica, Francuska.
      attrs = valid_attrs(%{geom: point(7.2620, 43.7102)})

      assert {:error, changeset} = Beaches.create_beach(attrs)
      assert %{geom: ["mora biti unutar bounding boxa hrvatske obale"]} = errors_on(changeset)
    end

    test "odbija točku u krivom SRID-u" do
      attrs = valid_attrs(%{geom: %Geo.Point{coordinates: {16.44, 43.50}, srid: 3857}})

      assert {:error, changeset} = Beaches.create_beach(attrs)
      assert %{geom: ["mora biti u SRID-u 4326"]} = errors_on(changeset)
    end

    test "prihvaća krajnje točke obale — Savudriju i Prevlaku" do
      assert {:ok, _} = Beaches.create_beach(valid_attrs(%{geom: point(13.4926, 45.4906)}))
      assert {:ok, _} = Beaches.create_beach(valid_attrs(%{geom: point(18.4380, 42.3960)}))
    end
  end

  describe "changeset validacija sadržaja" do
    test "odbija nepoznat ključ" do
      attrs = valid_attrs(%{amenities: %{"jacuzzi" => true}})

      assert {:error, changeset} = Beaches.create_beach(attrs)
      assert %{amenities: ["nepoznati sadržaji: jacuzzi"]} = errors_on(changeset)
    end

    test "odbija vrijednost koja nije true/false" do
      attrs = valid_attrs(%{amenities: %{"water" => "da"}})

      assert {:error, changeset} = Beaches.create_beach(attrs)
      assert %{amenities: ["vrijednosti moraju biti true/false"]} = errors_on(changeset)
    end
  end

  describe "baza" do
    test "odbija nepoznat dog_status i kad se zaobiđe changeset" do
      assert_raise Postgrex.Error, ~r/beaches_dog_status_check/, fn ->
        SQL.query!(
          Repo,
          """
          INSERT INTO beaches (osm_id, geom, surface, dog_status, dog_status_source,
                               amenities, inserted_at, updated_at)
          VALUES ('way/999', $1, 'sand', 'maybe', 'osm', '{}', now(), now())
          """,
          [point()]
        )
      end
    end

    test "geom ima GiST indeks" do
      %{rows: rows} =
        SQL.query!(
          Repo,
          "SELECT indexdef FROM pg_indexes WHERE tablename = 'beaches'",
          []
        )

      assert Enum.any?(rows, fn [definition] ->
               definition =~ "USING gist" and definition =~ "geom"
             end)
    end
  end
end
