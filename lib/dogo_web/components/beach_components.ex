defmodule DogoWeb.BeachComponents do
  @moduledoc """
  Komponente specifične za prikaz plaža.

  Natpisi su **funkcije, ne module atributi**: atribut se evaluira pri
  kompilaciji, pa bi prijevod ostao zamrznut na jeziku koji je bio aktivan u
  tom trenutku. Gettext mora biti pozvan za vrijeme zahtjeva.
  """
  use Phoenix.Component
  use Gettext, backend: DogoWeb.Gettext

  import DogoWeb.CoreComponents, only: [icon: 1]

  @classes %{
    designated: "bg-emerald-100 text-emerald-900",
    allowed: "bg-lime-100 text-lime-900",
    not_allowed: "bg-rose-100 text-rose-900",
    unknown: "bg-base-300 text-base-content"
  }

  @amenity_icons %{
    "dog_shower" => "hero-sparkles",
    "shade" => "hero-sun",
    "water" => "hero-beaker",
    "bins" => "hero-trash",
    "parking" => "hero-truck"
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
  def dog_status_label(:designated), do: gettext("Dog beach")
  def dog_status_label(:allowed), do: gettext("Dogs allowed")
  def dog_status_label(:not_allowed), do: gettext("Dogs not allowed")
  def dog_status_label(_unknown), do: gettext("Unknown")

  @doc "Ljudski čitljiv naziv podloge."
  def surface_label(:pebble), do: gettext("Pebble")
  def surface_label(:sand), do: gettext("Sand")
  def surface_label(:rock), do: gettext("Rock")
  def surface_label(:concrete), do: gettext("Concrete")
  def surface_label(:mixed), do: gettext("Mixed")
  def surface_label(_unknown), do: gettext("Unknown")

  @doc "Ljudski čitljiv naziv sadržaja."
  def amenity_label(amenity) when is_atom(amenity), do: amenity |> to_string() |> amenity_label()
  def amenity_label("dog_shower"), do: gettext("Dog shower")
  def amenity_label("shade"), do: gettext("Shade")
  def amenity_label("water"), do: gettext("Drinking water")
  def amenity_label("bins"), do: gettext("Bins")
  def amenity_label("parking"), do: gettext("Parking")

  @doc """
  Oznaka statusa za pse, obojana prema statusu.
  """
  attr :status, :atom, required: true

  def dog_status(assigns) do
    assigns =
      assign(assigns,
        label: dog_status_label(assigns.status),
        class: @classes[assigns.status]
      )

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
    assigns =
      assign(assigns,
        label: if(assigns.source == :osm, do: gettext("from OSM"), else: gettext("generated")),
        title:
          if(assigns.source == :osm,
            do: gettext("This value comes from OpenStreetMap."),
            else: gettext("This value was generated for the demo.")
          )
      )

    ~H"""
    <span
      data-role="dog-status-source"
      data-source={@source}
      class="inline-flex items-center gap-1 text-xs text-base-content/70"
      title={@title}
    >
      <.icon
        name={if @source == :osm, do: "hero-check-badge", else: "hero-beaker"}
        class="size-3.5"
      />
      {@label}
    </span>
    """
  end

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
        <.icon :if={present?} name="hero-check" class="ml-auto size-4 shrink-0 text-emerald-600" />
      </li>
    </ul>
    """
  end

  defp amenity_items(amenities) do
    for {key, icon} <- Enum.sort(@amenity_icons) do
      {key, amenity_label(key), icon, Map.get(amenities, key, false) == true}
    end
  end

  @doc """
  Trajanje vožnje u ljudskom obliku: minute do sat vremena, inače sati.
  """
  def format_duration(nil), do: nil

  def format_duration(seconds) when seconds < 3_600 do
    gettext("%{count} min", count: max(round(seconds / 60), 1))
  end

  def format_duration(seconds) do
    hours = div(round(seconds), 3_600)
    minutes = div(rem(round(seconds), 3_600), 60)

    if minutes == 0,
      do: gettext("%{count} h", count: hours),
      else: gettext("%{hours} h %{minutes} min", hours: hours, minutes: minutes)
  end

  @doc """
  Udaljenost u ljudskom obliku: metri ispod kilometra, inače kilometri.
  """
  def format_distance(nil), do: nil

  def format_distance(metres) when metres < 1_000 do
    gettext("%{count} m", count: round(metres))
  end

  def format_distance(metres) do
    gettext("%{count} km", count: :erlang.float_to_binary(metres / 1_000, decimals: 1))
  end

  @doc """
  Link za navigaciju do koordinata.

  Google Maps radi svugdje, Apple Maps je ugodniji na iOS-u. Oba primaju
  koordinate izravno, pa ne ovisimo o tome je li plaža uopće u njihovoj bazi.
  """
  def google_maps_url(lat, lon),
    do: "https://www.google.com/maps/dir/?api=1&destination=#{lat},#{lon}"

  def apple_maps_url(lat, lon), do: "https://maps.apple.com/?daddr=#{lat},#{lon}"
end
