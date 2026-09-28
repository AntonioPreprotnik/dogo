defmodule DogoWeb.BeachMapLive do
  @moduledoc """
  Karta plaža s listom rezultata i filterima.

  Podjela posla: karta živi u JS-u i LiveView je nikad ne re-renderira
  (`phx-update="ignore"`). Klijent javlja `bounds_changed`, server odgovara
  markerima kroz `push_event` i listom kroz render.

  Cijelo stanje pretrage — filteri i pozicija karte — živi u query stringu.
  `handle_params/3` je jedini put kojim filteri ulaze u socket, pa je svaki
  prikaz djeljiv linkom i preživi osvježavanje.
  """
  use DogoWeb, :live_view

  alias Dogo.Beaches
  alias DogoWeb.BeachFilters
  alias DogoWeb.GeoJSON

  # Cijeli Jadran stane u ovaj pogled.
  @default_center %{lon: 16.5, lat: 43.7}
  @default_zoom 7

  # Koliko plaža ide u listu. Karta ih prikazuje do `Beaches.bbox_limit/0`,
  # ali lista koju treba skrolati prstom ima drugu granicu korisnosti.
  @list_limit 20

  # Zoom na koji karta odleti kad korisnik odabere plažu iz liste.
  @focus_zoom 14

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Karta")
     |> assign(:beaches, [])
     |> assign(:visible_count, 0)
     |> assign(:truncated?, false)
     |> assign(:selected_id, nil)
     |> assign(:bbox, nil)
     |> assign(:center, nil)
     |> assign(:zoom, nil)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = BeachFilters.parse(params)

    socket =
      socket
      |> assign(:filters, filters)
      |> assign_new(:map_config, fn -> map_config(params) end)

    {:noreply, refresh(socket)}
  end

  @impl true
  def handle_event("bounds_changed", params, socket) do
    bbox = {params["west"], params["south"], params["east"], params["north"]}

    socket =
      socket
      |> assign(:bbox, bbox)
      |> assign(:center, center_from(params, bbox))
      |> assign(:zoom, params["zoom"])
      |> refresh()

    # `replace: true`: link ostaje djeljiv, a povijest preglednika se ne puni
    # svakim pomakom karte.
    {:noreply, push_patch(socket, to: url_for(socket, socket.assigns.filters), replace: true)}
  end

  def handle_event("filter", params, socket) do
    {:noreply, patch_to(socket, BeachFilters.from_form(params))}
  end

  def handle_event("clear_filters", _params, socket) do
    {:noreply, patch_to(socket, BeachFilters.clear())}
  end

  def handle_event("select_beach", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.beaches, &(to_string(&1.id) == id)) do
      nil ->
        {:noreply, socket}

      %{geom: %Geo.Point{coordinates: {lon, lat}}} = beach ->
        {:noreply,
         socket
         |> assign(:selected_id, beach.id)
         |> push_event("fly_to", %{lon: lon, lat: lat, zoom: @focus_zoom})}
    end
  end

  # Upit se vrti tek kad karta javi svoje granice. Do tada nemamo sto pitati.
  defp refresh(%{assigns: %{bbox: nil}} = socket), do: socket

  defp refresh(socket) do
    %{bbox: bbox, center: center, filters: filters} = socket.assigns

    opts = Keyword.put(BeachFilters.to_opts(filters), :near, center)

    {truncated?, beaches} =
      case Beaches.within_bbox(bbox, opts) do
        {:ok, beaches} -> {false, beaches}
        {:too_many, beaches} -> {true, beaches}
      end

    socket
    |> assign(
      beaches: Enum.take(beaches, @list_limit),
      visible_count: length(beaches),
      truncated?: truncated?
    )
    |> push_event("beaches", %{geojson: GeoJSON.feature_collection(beaches)})
  end

  defp patch_to(socket, filters) do
    push_patch(socket, to: url_for(socket, filters))
  end

  # Jedno mjesto koje gradi URL, i za promjenu filtera i za pomak karte.
  # Kad je pozicija bila u dvije funkcije, promjena filtera je ispustila zoom i
  # isti link je u novoj kartici otvarao drugi pogled.
  defp url_for(socket, filters) do
    query = Map.merge(BeachFilters.to_params(filters), position_params(socket))

    ~p"/?#{query}"
  end

  defp position_params(%{assigns: %{center: %Geo.Point{coordinates: {lon, lat}}, zoom: zoom}}) do
    %{
      "lat" => round_coordinate(lat),
      "lon" => round_coordinate(lon),
      "zoom" => round_zoom(zoom)
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp position_params(_socket), do: %{}

  # Pet decimala je oko metar. Vise od toga samo produljuje link.
  defp round_coordinate(value) when is_number(value), do: Float.round(value / 1, 5)
  defp round_coordinate(_), do: nil

  defp round_zoom(value) when is_number(value), do: Float.round(value / 1, 2)
  defp round_zoom(_), do: nil

  # Centar normalno salje karta. Ako ga nema (stariji klijent, ili event
  # sastavljen rucno), sredina pravokutnika je dovoljno dobra zamjena — bolje
  # nego srusiti LiveView na nil koordinatama.
  defp center_from(%{"center_lon" => lon, "center_lat" => lat}, _bbox)
       when is_number(lon) and is_number(lat) do
    %Geo.Point{coordinates: {lon, lat}, srid: 4326}
  end

  defp center_from(_params, {west, south, east, north}) do
    %Geo.Point{coordinates: {(west + east) / 2, (south + north) / 2}, srid: 4326}
  end

  defp map_config(params) do
    Map.merge(GeoJSON.marker_color_match(), %{
      styleUrl: Application.get_env(:dogo, :map_style_url),
      center: %{
        lon: coordinate(params["lon"], @default_center.lon),
        lat: coordinate(params["lat"], @default_center.lat)
      },
      zoom: coordinate(params["zoom"], @default_zoom)
    })
  end

  defp coordinate(value, default) when is_binary(value) do
    case Float.parse(value) do
      {number, _rest} -> number
      :error -> default
    end
  end

  defp coordinate(_value, default), do: default

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
          <span :if={not @truncated?}>Vidljivo: {@visible_count}</span>
        </p>
      </div>

      <form phx-change="filter" class="flex flex-wrap items-center gap-x-6 gap-y-3 text-sm">
        <fieldset class="flex flex-wrap items-center gap-2">
          <legend class="sr-only">Status za pse</legend>
          <.filter_chip
            :for={status <- [:designated, :allowed]}
            name={"dog[#{status}]"}
            checked={status in @filters.dog_status}
            label={dog_status_label(status)}
          />
        </fieldset>

        <fieldset class="flex flex-wrap items-center gap-2">
          <legend class="sr-only">Podloga</legend>
          <.filter_chip
            :for={surface <- [:sand, :pebble, :rock]}
            name={"surface[#{surface}]"}
            checked={surface in @filters.surface}
            label={surface_label(surface)}
          />
        </fieldset>

        <fieldset class="flex flex-wrap items-center gap-2">
          <legend class="sr-only">Sadržaji</legend>
          <.filter_chip
            :for={amenity <- BeachFilters.amenity_filters()}
            name={"amenities[#{amenity}]"}
            checked={amenity in @filters.amenities}
            label={amenity_label(amenity)}
          />
        </fieldset>

        <label class="flex items-center gap-2">
          <span class="text-base-content/70">Radijus</span>
          <select name="radius" class="rounded-lg border border-base-300 bg-base-100 px-2 py-1">
            <option value="" selected={is_nil(@filters.radius_m)}>bez ograničenja</option>
            <option
              :for={radius <- Beaches.radii_m()}
              value={radius}
              selected={@filters.radius_m == radius}
            >
              {div(radius, 1000)} km
            </option>
          </select>
        </label>

        <button
          :if={BeachFilters.active?(@filters)}
          type="button"
          phx-click="clear_filters"
          class="text-base-content/60 underline"
        >
          Očisti filtere
        </button>
      </form>

      <div class="relative lg:grid lg:grid-cols-[1fr_20rem] lg:gap-4">
        <div
          id="beach-map"
          phx-hook="BeachMap"
          phx-update="ignore"
          data-config={Jason.encode!(@map_config)}
          class="h-[70vh] w-full overflow-hidden rounded-xl border border-base-300"
        >
        </div>

        <%!-- Na mobitelu panel pliva iznad karte (bottom sheet), na desktopu
              stoji sa strane. Isti DOM, samo druge klase. --%>
        <aside
          id="beach-list"
          class={
            [
              # Na mobitelu je visina fiksna, ne max-h: bottom sheet koji skace s
              # brojem rezultata je nemiran, a fiksna visina daje karti stabilnu
              # zonu u koju se sklanjaju njezine kontrole (vidi app.css).
              "absolute inset-x-0 bottom-0 z-10 h-[45%] overflow-y-auto",
              "rounded-t-2xl border border-base-300 bg-base-100 shadow-[0_-8px_24px_-12px_rgba(0,0,0,0.25)]",
              "lg:static lg:z-auto lg:h-auto lg:max-h-[70vh] lg:rounded-xl lg:shadow-none"
            ]
          }
        >
          <div class="sticky top-0 border-b border-base-300 bg-base-100 px-4 py-2">
            <div class="mx-auto mb-2 h-1 w-10 rounded-full bg-base-300 lg:hidden"></div>
            <h2 class="text-xs font-semibold uppercase tracking-wide text-base-content/60">
              Najbliže sredini karte
            </h2>
          </div>

          <p :if={@beaches == []} class="px-4 py-6 text-sm text-base-content/60">
            {empty_message(@filters)}
          </p>

          <ul class="divide-y divide-base-300">
            <li :for={beach <- @beaches}>
              <button
                type="button"
                phx-click="select_beach"
                phx-value-id={beach.id}
                data-role="beach-list-item"
                data-beach-id={beach.id}
                aria-current={@selected_id == beach.id && "true"}
                class={[
                  "flex w-full items-start gap-3 px-4 py-3 text-left hover:bg-base-200",
                  @selected_id == beach.id && "bg-base-200"
                ]}
              >
                <span
                  class="mt-1.5 size-2.5 shrink-0 rounded-full"
                  style={"background: #{Map.fetch!(marker_colors(), beach.dog_status)}"}
                >
                </span>
                <span class="min-w-0 flex-1">
                  <span class="block truncate font-medium">
                    {beach.name || "Plaža bez imena"}
                  </span>
                  <%!-- Vecina plaza u OSM-u nema ime, pa bi lista bez podloge
                        bila dvadeset identicnih redaka. --%>
                  <span class="block text-xs text-base-content/60">
                    {dog_status_label(beach.dog_status)} · {surface_label(beach.surface)}
                  </span>
                </span>
                <span
                  :if={beach.distance_m}
                  data-role="distance"
                  class="shrink-0 text-xs tabular-nums text-base-content/60"
                >
                  {format_distance(beach.distance_m)}
                </span>
              </button>
            </li>
          </ul>

          <div :if={@beaches != []} class="border-t border-base-300 px-4 py-2">
            <.link
              :if={@selected_id}
              navigate={~p"/beaches/#{@selected_id}"}
              class="text-sm font-medium underline"
            >
              Otvori detalje odabrane plaže
            </.link>
          </div>
        </aside>
      </div>
    </Layouts.app>
    """
  end

  attr :name, :string, required: true
  attr :checked, :boolean, required: true
  attr :label, :string, required: true

  defp filter_chip(assigns) do
    ~H"""
    <label class={[
      "cursor-pointer rounded-full border px-3 py-1 transition-colors",
      @checked && "border-base-content bg-base-content text-base-100",
      !@checked && "border-base-300 hover:bg-base-200"
    ]}>
      <input type="hidden" name={@name} value="false" />
      <input type="checkbox" name={@name} value="true" checked={@checked} class="sr-only" />
      {@label}
    </label>
    """
  end

  defp empty_message(filters) do
    if BeachFilters.active?(filters) do
      "Nijedna plaža u ovom dijelu karte ne odgovara filterima."
    else
      "Nema plaža u ovom dijelu karte. Pomakni ili odzumiraj kartu."
    end
  end
end
