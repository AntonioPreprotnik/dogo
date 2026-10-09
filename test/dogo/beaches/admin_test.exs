defmodule Dogo.Beaches.AdminTest do
  @moduledoc "E8-S1: ručno uređivanje plaža kroz kontekst."
  use Dogo.DataCase, async: true

  import Dogo.AccountsFixtures
  import Dogo.BeachesFixtures

  alias Dogo.Beaches
  alias Dogo.Geo.Island
  alias Dogo.Import.Islands, as: IslandImport
  alias Dogo.Import.Overpass.IslandElement

  setup do
    %{scope: admin_scope_fixture()}
  end

  defp form_params(overrides \\ %{}) do
    Map.merge(
      %{
        "name" => "Nova plaža",
        "municipality" => "Split",
        "lat" => "43.5041",
        "lon" => "16.4402",
        "dog_status" => "designated",
        "surface" => "pebble",
        "amenities" => %{"water" => "true", "shade" => "false"}
      },
      overrides
    )
  end

  # Kvadratni otok 0.1° x 0.1° s jugozapadnim kutom u (lon, lat).
  defp island(lon, lat) do
    corners = [{lon, lat}, {lon + 0.1, lat}, {lon + 0.1, lat + 0.1}, {lon, lat + 0.1}, {lon, lat}]
    lines = corners |> Enum.chunk_every(2, 1, :discard) |> Enum.map(&Enum.to_list/1)
    osm_id = osm_id("way/otok")

    IslandImport.store([%IslandElement{osm_id: osm_id, name: "Otok", lines: lines}])
    Repo.get_by!(Island, osm_id: osm_id)
  end

  describe "autorizacija" do
    test "bez prijavljenog admina funkcije ne rade" do
      beach = beach_fixture()
      # Gradi se dinamički, inače ga provjera tipova odbije već pri kompilaciji.
      no_admin = struct(Dogo.Accounts.Scope, admin: nil)

      assert_raise FunctionClauseError, fn -> Beaches.list_beaches_for_admin(no_admin) end

      assert_raise FunctionClauseError, fn ->
        Beaches.create_beach_as_admin(no_admin, form_params())
      end

      assert_raise FunctionClauseError, fn ->
        Beaches.update_beach_as_admin(no_admin, beach, %{})
      end

      assert_raise FunctionClauseError, fn -> Beaches.delete_beach(no_admin, beach) end
    end
  end

  describe "list_beaches_for_admin/2" do
    test "traži po imenu, općini i točnom osm_id-u", %{scope: scope} do
      bacvice = beach_fixture(name: "Bačvice", municipality: "Split")
      _zlatni = beach_fixture(name: "Zlatni rat", municipality: "Bol")

      assert [%{id: id}] = Beaches.list_beaches_for_admin(scope, query: "bačv").entries
      assert id == bacvice.id

      assert [%{id: ^id}] = Beaches.list_beaches_for_admin(scope, query: "SPLIT").entries
      assert [%{id: ^id}] = Beaches.list_beaches_for_admin(scope, query: bacvice.osm_id).entries
      assert %{total: 2} = Beaches.list_beaches_for_admin(scope, query: "  ")
    end

    test "znakovi % i _ se traže doslovno", %{scope: scope} do
      _ = beach_fixture(name: "Plaža")

      assert %{total: 0} = Beaches.list_beaches_for_admin(scope, query: "%")
      assert %{total: 0} = Beaches.list_beaches_for_admin(scope, query: "_")
    end

    test "dijeli rezultate na stranice i ograničava broj stranice", %{scope: scope} do
      for n <- 1..30, do: beach_fixture(name: "Plaža #{String.pad_leading("#{n}", 2, "0")}")

      first = Beaches.list_beaches_for_admin(scope, page: 1)
      second = Beaches.list_beaches_for_admin(scope, page: 2)

      assert %{total: 30, total_pages: 2, page: 1} = first
      assert length(first.entries) == 25
      assert [%{name: "Plaža 26"} | _] = second.entries
      assert %{page: 2} = Beaches.list_beaches_for_admin(scope, page: 99)
      assert %{page: 1} = Beaches.list_beaches_for_admin(scope, page: -3)
    end
  end

  describe "create_beach_as_admin/2" do
    test "sprema ručnu plažu s vlastitim osm_id-om i izvorom :manual", %{scope: scope} do
      assert {:ok, beach} = Beaches.create_beach_as_admin(scope, form_params())

      assert "manual/" <> _ = beach.osm_id
      assert beach.name == "Nova plaža"
      assert %Geo.Point{coordinates: {16.4402, 43.5041}, srid: 4326} = beach.geom
      assert beach.dog_status == :designated
      assert beach.dog_status_source == :manual
      assert beach.amenities == %{"water" => true, "shade" => false}
      assert beach.edited_at
      assert is_nil(beach.island_id)
    end

    test "status koji ostane zadani je i dalje :manual", %{scope: scope} do
      {:ok, beach} =
        Beaches.create_beach_as_admin(scope, form_params(%{"dog_status" => "unknown"}))

      assert beach.dog_status_source == :manual
    end

    test "odbija točku izvan hrvatske obale i neispravne koordinate", %{scope: scope} do
      assert {:error, changeset} =
               Beaches.create_beach_as_admin(
                 scope,
                 form_params(%{"lat" => "48.2", "lon" => "16.37"})
               )

      assert %{geom: [_]} = errors_on(changeset)

      assert {:error, changeset} =
               Beaches.create_beach_as_admin(scope, form_params(%{"lat" => "abc", "lon" => ""}))

      assert %{lat: ["is invalid"], lon: ["can't be blank"]} = errors_on(changeset)
    end

    test "odbija nepoznat sadržaj", %{scope: scope} do
      assert {:error, changeset} =
               Beaches.create_beach_as_admin(
                 scope,
                 form_params(%{"amenities" => %{"bar" => "true"}})
               )

      assert %{amenities: [_]} = errors_on(changeset)
    end

    test "plaža na otoku dobiva otok", %{scope: scope} do
      otok = island(16.0, 43.0)

      {:ok, beach} =
        Beaches.create_beach_as_admin(scope, form_params(%{"lat" => "43.05", "lon" => "16.05"}))

      assert beach.island_id == otok.id
    end
  end

  describe "update_beach_as_admin/3" do
    test "postavlja edited_at, a promjena statusa mijenja izvor u :manual", %{scope: scope} do
      beach = beach_fixture(dog_status: :allowed, dog_status_source: :osm)

      {:ok, renamed} = Beaches.update_beach_as_admin(scope, beach, %{"name" => "Novo ime"})
      assert renamed.edited_at
      assert renamed.dog_status_source == :osm

      {:ok, updated} =
        Beaches.update_beach_as_admin(scope, renamed, %{"dog_status" => "not_allowed"})

      assert updated.dog_status == :not_allowed
      assert updated.dog_status_source == :manual
    end

    test "spremanje bez promjena ne označava plažu kao ispravljenu", %{scope: scope} do
      beach = beach_fixture()

      {:ok, same} =
        Beaches.update_beach_as_admin(scope, beach, %{
          "name" => beach.name,
          "lat" => "43.5041",
          "lon" => "16.4402"
        })

      assert is_nil(same.edited_at)
    end

    test "prazno ime postaje nil", %{scope: scope} do
      beach = beach_fixture(name: "Bačvice")

      {:ok, updated} = Beaches.update_beach_as_admin(scope, beach, %{"name" => "  "})
      assert is_nil(updated.name)
    end

    test "pomicanje plaže na otok i natrag mijenja otok", %{scope: scope} do
      otok = island(16.0, 43.0)
      beach = beach_fixture()

      {:ok, moved} =
        Beaches.update_beach_as_admin(scope, beach, %{"lat" => "43.05", "lon" => "16.05"})

      assert moved.island_id == otok.id

      {:ok, back} =
        Beaches.update_beach_as_admin(scope, moved, %{"lat" => "43.5041", "lon" => "16.4402"})

      assert is_nil(back.island_id)
    end

    test "ne mijenja osm_id ni poligon", %{scope: scope} do
      beach = beach_fixture()

      {:ok, updated} =
        Beaches.update_beach_as_admin(scope, beach, %{"osm_id" => "way/hack", "area" => nil})

      assert updated.osm_id == beach.osm_id
    end
  end

  describe "delete_beach/2" do
    test "briše plažu", %{scope: scope} do
      beach = beach_fixture()

      assert {:ok, _} = Beaches.delete_beach(scope, beach)
      assert_raise Ecto.NoResultsError, fn -> Beaches.get_beach!(beach.id) end
    end
  end

  test "change_beach_as_admin/1 popunjava koordinate iz geom" do
    changeset = Beaches.change_beach_as_admin(beach_fixture())

    assert Ecto.Changeset.get_field(changeset, :lat) == 43.5041
    assert Ecto.Changeset.get_field(changeset, :lon) == 16.4402
  end
end
