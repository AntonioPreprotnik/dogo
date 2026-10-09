defmodule Dogo.Repo.Migrations.AddManualEditsToBeaches do
  use Ecto.Migration

  # Ručne izmjene iz admina uvoz ne smije pregaziti (ADR 0011). `edited_at`
  # je oznaka da je plaža ručno ispravljena, a `manual` novi izvor statusa.
  def up do
    alter table(:beaches) do
      add :edited_at, :utc_datetime
    end

    drop constraint(:beaches, :beaches_dog_status_source_check)

    create constraint(:beaches, :beaches_dog_status_source_check,
             check: "dog_status_source IN ('osm', 'generated', 'manual')"
           )
  end

  def down do
    execute "UPDATE beaches SET dog_status_source = 'generated' WHERE dog_status_source = 'manual'"

    drop constraint(:beaches, :beaches_dog_status_source_check)

    create constraint(:beaches, :beaches_dog_status_source_check,
             check: "dog_status_source IN ('osm', 'generated')"
           )

    alter table(:beaches) do
      remove :edited_at
    end
  end
end
