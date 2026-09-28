defmodule Dogo.Repo.Migrations.AddBeachesGeographyIndex do
  use Ecto.Migration

  # KNN operator `<->` nad `geometry` sortira po ravninskoj udaljenosti u
  # stupnjevima. Na 43. paraleli je stupanj zemljopisne duzine oko 27 % kraci
  # od stupnja sirine, pa takav poredak ne odgovara stvarnoj udaljenosti.
  #
  # Nad `geography` isti operator vraca metre po sferoidu. Da bi ga planer
  # mogao ubrzati, potreban je funkcijski GiST indeks nad castom.
  def change do
    execute(
      "CREATE INDEX beaches_geom_geography_index ON beaches USING gist ((geom::geography))",
      "DROP INDEX beaches_geom_geography_index"
    )
  end
end
