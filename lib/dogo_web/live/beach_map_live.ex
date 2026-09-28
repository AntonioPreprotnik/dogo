defmodule DogoWeb.BeachMapLive do
  @moduledoc """
  Karta plaža.

  Podjela posla: karta živi u JS-u i LiveView je nikad ne re-renderira
  (`phx-update="ignore"`). Klijent javlja `bounds_changed`, server odgovara
  markerima kroz `push_event`. Tako se LiveView i MapLibre ne tuku oko DOM-a.
  """
  use DogoWeb, :live_view

  alias Dogo.Beaches
  alias DogoWeb.GeoJSON

  # Cijeli Jadran stane u ovaj pogled.
  @default_center %{lon: 16.5, lat: 43.7}
  @default_zoom 7

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Karta")
     |> assign(:visible_count, 0)
     |> assign(:truncated?, false)
     |> assign(:map_config, map_config())}
  end

  @impl true
  def handle_event("bounds_changed", params, socket) do
    bbox = {params["west"], params["south"], params["east"], params["north"]}

    {truncated?, beaches} =
      case Beaches.within_bbox(bbox) do
        {:ok, beaches} -> {false, beaches}
        {:too_many, beaches} -> {true, beaches}
      end

    {:noreply,
     socket
     |> assign(visible_count: length(beaches), truncated?: truncated?)
     |> push_event("beaches", %{geojson: GeoJSON.feature_collection(beaches)})}
  end

  defp map_config do
    Map.merge(GeoJSON.marker_color_match(), %{
      styleUrl: Application.get_env(:dogo, :map_style_url),
      center: @default_center,
      zoom: @default_zoom
    })
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="flex items-baseline justify-between gap-4">
        <h1 class="text-2xl font-semibold tracking-tight">Plaže za pse</h1>
        <p class="text-sm text-base-content/70">
          <span :if={@truncated?} class="font-medium text-warning">
            Previše plaža za ovaj zoom — prikazano prvih {@visible_count}.
          </span>
          <span :if={not @truncated?}>
            Vidljivo: {@visible_count}
          </span>
        </p>
      </div>

      <div
        id="beach-map"
        phx-hook="BeachMap"
        phx-update="ignore"
        data-config={Jason.encode!(@map_config)}
        class="h-[70vh] w-full overflow-hidden rounded-xl border border-base-300"
      >
      </div>
    </Layouts.app>
    """
  end
end
