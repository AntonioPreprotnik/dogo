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
