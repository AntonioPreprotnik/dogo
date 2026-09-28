defmodule DogoWeb.BeachDetailLive do
  @moduledoc """
  Detalj jedne plaže: status za pse s izvorom, podloga, sadržaji, mini karta i
  gumbi za navigaciju.
  """
  use DogoWeb, :live_view

  alias Dogo.Beaches

  @mini_map_zoom 13

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    beach = Beaches.get_beach!(id)
    %Geo.Point{coordinates: {lon, lat}} = beach.geom

    {:ok,
     socket
     |> assign(:page_title, beach.name || gettext("Beach"))
     |> assign(:beach, beach)
     |> assign(:lon, lon)
     |> assign(:lat, lat)
     |> assign(:map_config, mini_map_config(beach, lon, lat))}
  end

  defp mini_map_config(beach, lon, lat) do
    %{
      styleUrl: Application.get_env(:dogo, :map_style_url),
      lon: lon,
      lat: lat,
      zoom: @mini_map_zoom,
      color: Map.fetch!(marker_colors(), beach.dog_status)
    }
  end

  # Google Maps radi svugdje, Apple Maps je ugodniji na iOS-u. Oba primaju
  # koordinate izravno, pa ne ovisimo o tome je li plaža uopće u njihovoj bazi.
  defp google_maps_url(lat, lon),
    do: "https://www.google.com/maps/dir/?api=1&destination=#{lat},#{lon}"

  defp apple_maps_url(lat, lon), do: "https://maps.apple.com/?daddr=#{lat},#{lon}"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path={@current_path}>
      <.link navigate={~p"/"} class="inline-flex items-center gap-1 text-sm text-base-content/70">
        <.icon name="hero-arrow-left" class="size-4" /> {gettext("Back to map")}
      </.link>

      <header class="space-y-2">
        <h1 class="text-2xl font-semibold tracking-tight">
          {@beach.name || gettext("Unnamed beach")}
        </h1>
        <p :if={@beach.municipality} class="text-sm text-base-content/70">
          {@beach.municipality}
        </p>
        <div class="flex flex-wrap items-center gap-2">
          <.dog_status status={@beach.dog_status} />
          <.dog_status_source source={@beach.dog_status_source} />
        </div>
      </header>

      <dl class="grid grid-cols-2 gap-4 rounded-xl border border-base-300 p-4 sm:grid-cols-3">
        <div>
          <dt class="text-xs uppercase tracking-wide text-base-content/60">{gettext("Surface")}</dt>
          <dd class="mt-0.5 font-medium" data-role="surface">{surface_label(@beach.surface)}</dd>
        </div>
        <div>
          <dt class="text-xs uppercase tracking-wide text-base-content/60">
            {gettext("Coordinates")}
          </dt>
          <dd class="mt-0.5 font-mono text-sm">
            {:erlang.float_to_binary(@lat, decimals: 4)}, {:erlang.float_to_binary(@lon,
              decimals: 4
            )}
          </dd>
        </div>
        <div>
          <dt class="text-xs uppercase tracking-wide text-base-content/60">{gettext("Source")}</dt>
          <dd class="mt-0.5 font-mono text-sm">{@beach.osm_id}</dd>
        </div>
      </dl>

      <section class="space-y-2">
        <h2 class="text-sm font-semibold uppercase tracking-wide text-base-content/60">
          {gettext("Amenities")}
        </h2>
        <.amenities amenities={@beach.amenities} />
      </section>

      <div
        id="beach-mini-map"
        phx-hook="BeachMiniMap"
        phx-update="ignore"
        data-config={Jason.encode!(@map_config)}
        class="h-64 w-full overflow-hidden rounded-xl border border-base-300"
      >
      </div>

      <div class="flex flex-wrap gap-2">
        <a
          href={google_maps_url(@lat, @lon)}
          target="_blank"
          rel="noopener"
          data-role="navigate-google"
          class="inline-flex items-center gap-2 rounded-lg bg-base-content px-4 py-2 text-sm font-medium text-base-100"
        >
          <.icon name="hero-map-pin" class="size-4" /> {gettext("Navigate")}
        </a>
        <a
          href={apple_maps_url(@lat, @lon)}
          target="_blank"
          rel="noopener"
          data-role="navigate-apple"
          class="inline-flex items-center gap-2 rounded-lg border border-base-300 px-4 py-2 text-sm font-medium"
        >
          Apple Maps
        </a>
      </div>
    </Layouts.app>
    """
  end
end
