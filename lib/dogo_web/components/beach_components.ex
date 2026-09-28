defmodule DogoWeb.BeachComponents do
  @moduledoc """
  Komponente specifične za prikaz plaža.
  """
  use Phoenix.Component

  import DogoWeb.CoreComponents, only: [icon: 1]

  @labels %{
    designated: "Plaža za pse",
    allowed: "Psi dozvoljeni",
    not_allowed: "Psi nisu dozvoljeni",
    unknown: "Nepoznato"
  }

  @classes %{
    designated: "bg-emerald-100 text-emerald-900",
    allowed: "bg-lime-100 text-lime-900",
    not_allowed: "bg-rose-100 text-rose-900",
    unknown: "bg-base-300 text-base-content"
  }

  @surface_labels %{
    pebble: "Šljunak",
    sand: "Pijesak",
    rock: "Stijene",
    concrete: "Beton",
    mixed: "Miješano",
    unknown: "Nepoznato"
  }

  @amenity_labels %{
    "dog_shower" => {"Tuš za pse", "hero-sparkles"},
    "shade" => {"Hlad", "hero-sun"},
    "water" => {"Pitka voda", "hero-beaker"},
    "bins" => {"Kante za smeće", "hero-trash"},
    "parking" => {"Parking", "hero-truck"}
  }

  @doc "Boja markera po statusu, u formatu koji MapLibre razumije."
  def marker_colors do
    %{
      designated: "#059669",
      allowed: "#65a30d",
      not_allowed: "#e11d48",
      unknown: "#94a3b8"
    }
  end

  @doc "Ljudski čitljiv naziv statusa za pse."
  def dog_status_label(status), do: @labels[status]

  @doc "Ljudski čitljiv naziv podloge."
  def surface_label(surface), do: @surface_labels[surface]

  @doc """
  Popis sadržaja plaže s oznakom postoji/ne postoji.

  Nepoznat sadržaj se prikazuje kao "nema", a ne izostavlja — korisniku je
  korisnije vidjeti da smo provjerili nego da šutimo.
  """
  attr :amenities, :map, required: true

  def amenities(assigns) do
    assigns = assign(assigns, :items, amenity_items(assigns.amenities))

    ~H"""
    <ul class="grid grid-cols-2 gap-2 sm:grid-cols-3">
      <li
        :for={{key, label, icon, present?} <- @items}
        data-amenity={key}
        data-present={to_string(present?)}
        class={[
          "flex items-center gap-2 rounded-lg border px-3 py-2 text-sm",
          present? && "border-base-300",
          !present? && "border-dashed border-base-300 text-base-content/40"
        ]}
      >
        <.icon name={icon} class="size-4 shrink-0" />
        <span>{label}</span>
        <.icon
          :if={present?}
          name="hero-check"
          class="ml-auto size-4 shrink-0 text-emerald-600"
        />
      </li>
    </ul>
    """
  end

  defp amenity_items(amenities) do
    for {key, {label, icon}} <- Enum.sort(@amenity_labels) do
      {key, label, icon, Map.get(amenities, key, false) == true}
    end
  end

  @doc """
  Udaljenost u ljudskom obliku: metri ispod kilometra, inače kilometri.
  """
  def format_distance(nil), do: nil
  def format_distance(metres) when metres < 1_000, do: "#{round(metres)} m"

  def format_distance(metres) do
    :erlang.float_to_binary(metres / 1_000, decimals: 1) <> " km"
  end

  @doc """
  Oznaka statusa za pse, obojana prema statusu.
  """
  attr :status, :atom, required: true

  def dog_status(assigns) do
    assigns = assign(assigns, label: @labels[assigns.status], class: @classes[assigns.status])

    ~H"""
    <span class={["inline-flex rounded-full px-2 py-0.5 text-xs font-medium", @class]}>
      {@label}
    </span>
    """
  end

  @doc """
  Odakle dolazi status za pse: iz OSM-a ili je generiran.

  Bez ove oznake demo podatak izgleda kao provjereno pravilo, što je upravo
  ono što disclaimer pokušava spriječiti.
  """
  attr :source, :atom, required: true, values: [:osm, :generated]

  def dog_status_source(assigns) do
    ~H"""
    <span
      data-role="dog-status-source"
      data-source={@source}
      class="inline-flex items-center gap-1 text-xs text-base-content/70"
      title={
        if @source == :osm,
          do: "Podatak dolazi iz OpenStreetMapa.",
          else: "Podatak je generiran za potrebe demonstracije."
      }
    >
      <.icon
        name={if @source == :osm, do: "hero-check-badge", else: "hero-beaker"}
        class="size-3.5"
      />
      {if @source == :osm, do: "iz OSM-a", else: "generirano"}
    </span>
    """
  end
end
