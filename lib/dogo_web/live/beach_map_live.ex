defmodule DogoWeb.BeachMapLive do
  @moduledoc """
  Karta plaža s listom rezultata i filterima.

  Podjela posla: karta živi u JS-u i LiveView je nikad ne re-renderira
  (`phx-update="ignore"`). Klijent javlja `bounds_changed`, server odgovara
  markerima kroz `push_event` i listom kroz render.

  Cijelo stanje pretrage — filteri i pozicija karte — živi u query stringu.
  `handle_params/3` je jedini put kojim filteri ulaze u socket, pa je svaki
  prikaz djeljiv linkom i preživi osvježavanje.

  Korisnikova lokacija je iznimka: ona **ne ide u URL**, ne sprema se u bazu i
  ne smije završiti u logovima. Živi samo u assignima ovog procesa, dok traje
  sesija. Vidi `handle_event("user_located", ...)`.
  """
  use DogoWeb, :live_view

  alias Dogo.Beaches
  alias Dogo.Geo.Geocoder
  alias Dogo.Geo.Islands
  alias Dogo.Geo.Routing
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

  # Mjesto je šire od plaže, pa se na njega gleda iz veće visine.
  @place_zoom 12

  # Za koliko plaža se traži vrijeme vožnje. Servis je besplatan demo, a i
  # korisnik ionako gleda vrh liste.
  @driving_limit 10

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Map"))
     |> assign(:beaches, [])
     |> assign(:visible_count, 0)
     |> assign(:clustered?, false)
     |> assign(:selected_id, nil)
     |> assign(:bbox, nil)
     |> assign(:center, nil)
     |> assign(:zoom, nil)
     |> assign(:user_location, nil)
     |> assign(:user_island, nil)
     |> assign(:geolocation, :pending)
     |> assign(:place_query, "")
     |> assign(:places, [])
     |> assign(:place_search, :idle)
     |> assign(:tiles_ok?, true)
     |> assign(:map_width_px, nil)
     |> assign(:driving, %{})
     |> assign(:driving_for, [])}
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
      |> assign(:map_width_px, params["width_px"])
      |> refresh()

    {:noreply, maybe_push_position(socket)}
  end

  # Koordinate stizu ugnijezdene pod "location", jer je taj kljuc u
  # :filter_parameters — LiveView logger ispise [FILTERED] umjesto brojeva.
  def handle_event("user_located", %{"location" => %{"lat" => lat, "lon" => lon}}, socket)
      when is_number(lat) and is_number(lon) do
    location = %Geo.Point{coordinates: {lon, lat}, srid: 4326}

    # Otok korisnika se racuna jednom, ne po plazi. Upit nosi njegove
    # koordinate, pa ide bez Ecto loga (E4-S1).
    {:noreply,
     socket
     |> assign(:user_location, location)
     |> assign(:user_island, Islands.at(location, log: false))
     |> assign(:geolocation, :located)
     |> refresh()}
  end

  def handle_event("user_located", _params, socket) do
    {:noreply, assign(socket, :geolocation, :error)}
  end

  # Preglednik jos nije nista rekao: nudimo gumb umjesto da sami otvorimo
  # dijalog za dopustenje.
  def handle_event("geolocation_idle", _params, socket) do
    {:noreply, assign(socket, :geolocation, :idle)}
  end

  def handle_event("request_location", _params, socket) do
    {:noreply,
     socket
     |> assign(:geolocation, :requesting)
     |> push_event("request_location", %{})}
  end

  def handle_event("geolocation_error", %{"reason" => reason}, socket) do
    {:noreply, assign(socket, :geolocation, geolocation_reason(reason))}
  end

  def handle_event("map_tiles", %{"ok" => ok?}, socket) do
    {:noreply, assign(socket, :tiles_ok?, ok? == true)}
  end

  def handle_event("search_place", %{"q" => query}, socket) do
    socket = assign(socket, :place_query, query)

    if String.length(String.trim(query)) < 3 do
      {:noreply, socket |> assign(:places, []) |> assign(:place_search, :idle)}
    else
      # Pretraga ide asinkrono: Nominatim je udaljen servis i jos ga usporava
      # ogranicenje od jednog zahtjeva u sekundi. LiveView ne smije stajati.
      {:noreply,
       socket
       |> assign(:place_search, :searching)
       |> start_async(:search_place, fn -> Geocoder.search(query) end)}
    end
  end

  def handle_event("select_place", %{"lat" => lat, "lon" => lon}, socket) do
    with {latitude, _} <- Float.parse(lat),
         {longitude, _} <- Float.parse(lon) do
      {:noreply,
       socket
       |> assign(:places, [])
       |> assign(:place_query, "")
       |> assign(:place_search, :idle)
       |> push_event("fly_to", %{lon: longitude, lat: latitude, zoom: @place_zoom})}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("filter", params, socket) do
    {:noreply, patch_to(socket, BeachFilters.from_form(params, socket.assigns.filters))}
  end

  def handle_event("clear_filters", _params, socket) do
    {:noreply, patch_to(socket, BeachFilters.clear(socket.assigns.filters))}
  end

  def handle_event("sort", params, socket) do
    {:noreply, patch_to(socket, BeachFilters.with_sort(socket.assigns.filters, params["sort"]))}
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

  # Vrijeme voznje stize naknadno. Lista je vec na ekranu sa zracnom
  # udaljenoscu; ovo je dodatak, ne uvjet.
  def handle_async(:driving, {:ok, {ids, {:ok, legs}}}, socket) do
    if ids == socket.assigns.driving_for do
      {:noreply, assign(socket, :driving, Map.new(Enum.zip(ids, legs)))}
    else
      # Korisnik je u meduvremenu pomaknuo kartu; ovaj odgovor vise ne opisuje
      # ono sto je na ekranu.
      {:noreply, socket}
    end
  end

  def handle_async(:driving, {:ok, {_ids, {:error, _reason}}}, socket) do
    {:noreply, assign(socket, :driving, %{})}
  end

  def handle_async(:driving, {:exit, _reason}, socket) do
    {:noreply, assign(socket, :driving, %{})}
  end

  @impl true
  def handle_async(:search_place, {:ok, {:ok, places}}, socket) do
    {:noreply,
     socket
     |> assign(:places, places)
     |> assign(:place_search, if(places == [], do: :empty, else: :idle))}
  end

  def handle_async(:search_place, {:ok, {:error, _reason}}, socket) do
    {:noreply, socket |> assign(:places, []) |> assign(:place_search, :error)}
  end

  def handle_async(:search_place, {:exit, _reason}, socket) do
    {:noreply, socket |> assign(:places, []) |> assign(:place_search, :error)}
  end

  # Upit se vrti tek kad karta javi svoje granice. Do tada nemamo sto pitati.
  defp refresh(%{assigns: %{bbox: nil}} = socket), do: socket

  defp refresh(socket) do
    %{bbox: bbox, filters: filters} = socket.assigns
    {reference, log?} = reference_point(socket)
    origin = origin_island(socket, reference, log?)

    opts =
      filters
      |> BeachFilters.to_opts()
      |> Keyword.put(:near, reference)
      |> Keyword.put(:log, log?)
      |> Keyword.put(:width_px, socket.assigns.map_width_px)
      |> maybe_only_reachable(filters, origin)

    case Beaches.within_bbox(bbox, opts) do
      {:ok, beaches} ->
        socket
        |> assign(
          beaches:
            beaches
            |> Enum.take(@list_limit)
            |> Beaches.mark_across_sea(origin),
          visible_count: length(beaches),
          clustered?: false
        )
        |> push_event("beaches", %{geojson: GeoJSON.feature_collection(beaches)})
        |> request_driving(reference)

      # Previse plaza da bi se svaka poslala: cijeli Jadran je oko 900 KB
      # GeoJSON-a po pomaku. Umjesto odrezanog skupa saljemo sazetak po mrezi,
      # pa su brojevi u klasterima tocni. Lista i dalje pokazuje najblize.
      {:too_many, nearest} ->
        clusters = Beaches.cluster_in_bbox(bbox, opts)

        socket
        |> assign(
          beaches:
            nearest
            |> Enum.take(@list_limit)
            |> Beaches.mark_across_sea(origin),
          visible_count: Enum.sum_by(clusters, & &1.count),
          clustered?: true
        )
        |> push_event("clusters", %{geojson: GeoJSON.cluster_collection(clusters)})
        |> request_driving(reference)
    end
  end

  # Dok je sredina karte prakticki korisnikova lokacija, pozicija se ne upisuje
  # u URL — inace bi automatsko centriranje na geolokaciju stavilo njegove
  # koordinate u adresnu traku i u povijest preglednika.
  #
  # Pravilo je namjerno na serveru i vezano uz *stanje*, ne uz *dogadaj*. Prva
  # verzija je oznacavala programski pomak zastavicom u hooku, ali `flyTo`
  # emitira jos jedan `moveend` nakon animacije, pa je drugi event ipak
  # upisivao lokaciju. Provjera stanja je imuna na takav redoslijed.
  #
  # `replace: true`: link ostaje djeljiv, a povijest preglednika se ne puni
  # svakim pomakom karte.
  defp maybe_push_position(socket) do
    if at_user_location?(socket.assigns.center, socket.assigns.user_location) do
      socket
    else
      push_patch(socket, to: url_for(socket, socket.assigns.filters), replace: true)
    end
  end

  # 0.002 stupnja je oko 200 m. Pokriva zaokruzivanje i sitno smirivanje
  # animacije, a cim korisnik stvarno odmakne kartu, URL opet prati pogled.
  defp at_user_location?(%Geo.Point{coordinates: {lon, lat}}, %Geo.Point{
         coordinates: {ulon, ulat}
       }) do
    abs(lon - ulon) < 0.002 and abs(lat - ulat) < 0.002
  end

  defp at_user_location?(_center, _user_location), do: false

  # Polaziste za sve sto ovisi o "gdje sam": korisnik kad ga znamo, inace
  # sredina karte. Isto polaziste od kojeg se mjere udaljenosti — inace bi
  # lista tvrdila da je plaza 3 km daleko, a oznaka da je preko mora u odnosu
  # na neko trece mjesto.
  #
  # Pretpostaviti kopno bilo bi krivo za korisnika koji je vec na otoku: njemu
  # je bez trajekta dostupan bas taj otok.
  defp origin_island(%{assigns: %{user_island: %{} = island}}, _reference, _log?), do: island
  defp origin_island(_socket, nil, _log?), do: nil
  defp origin_island(_socket, reference, log?), do: Islands.at(reference, log: log?)

  defp maybe_only_reachable(opts, %{without_ferry: true}, origin) do
    Keyword.put(opts, :reachable_from, origin)
  end

  defp maybe_only_reachable(opts, _filters, _origin), do: opts

  # Kad znamo gdje je korisnik, udaljenosti se mjere od njega — to je i jedini
  # broj koji ga zanima. Tada se Ecto log gasi, jer bi inace ispisao njegove
  # koordinate kao parametre upita.
  defp reference_point(%{assigns: %{user_location: %Geo.Point{} = location}}),
    do: {location, false}

  defp reference_point(%{assigns: %{center: center}}), do: {center, true}

  # OSRM se pita samo kad se vrh liste stvarno promijenio. Bez toga bi svaki
  # pomak karte bio novi zahtjev prema besplatnom servisu, a cesto s istim
  # odgovorom.
  defp request_driving(socket, nil), do: socket

  defp request_driving(socket, origin) do
    top = Enum.take(socket.assigns.beaches, @driving_limit)
    ids = Enum.map(top, & &1.id)

    cond do
      ids == [] ->
        assign(socket, driving: %{}, driving_for: [])

      ids == socket.assigns.driving_for ->
        socket

      true ->
        points = Enum.map(top, & &1.geom)

        socket
        |> assign(:driving_for, ids)
        |> start_async(:driving, fn -> {ids, safe_table(origin, points)} end)
    end
  end

  # Redoslijed za prikaz. `@beaches` ostaje poredan po zracnoj udaljenosti,
  # jer o tom poretku ovisi za kojih se deset plaza trazi vrijeme voznje —
  # da se preslaze i stanje, drugi zahtjev bi isao za druge plaze.
  #
  # Po vremenu voznje: prvo plaze s poznatim vremenom, od najbrze; zatim
  # ostale, po zracnoj udaljenosti. Plaza bez rute ne smije iskociti na vrh
  # samo zato sto nema broja.
  defp ordered(beaches, _driving, :distance), do: beaches

  defp ordered(beaches, driving, :driving) do
    {timed, rest} = Enum.split_with(beaches, &driving[&1.id])

    Enum.sort_by(timed, &driving[&1.id].duration_s) ++ rest
  end

  # Iznimka u rutiranju se hvata ovdje, a ne prepusta Tasku. Pad zadatka ispise
  # poruku iznimke u log, a ona moze sadrzavati koordinate polazista — dakle
  # korisnikovu lokaciju (E4-S1). Uz to je ovo neobavezna informacija; njezin
  # pad ne treba izgledati kao incident.
  defp safe_table(origin, points) do
    Routing.table(origin, points)
  rescue
    exception -> {:error, exception.__struct__}
  catch
    kind, _reason -> {:error, kind}
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
    <Layouts.app flash={@flash} current_path={@current_path}>
      <div class="flex items-baseline justify-between gap-4">
        <h1 class="text-2xl font-semibold tracking-tight">{gettext("Dog-friendly beaches")}</h1>
        <p class="text-sm text-base-content/70">
          <span :if={@clustered?}>
            {gettext("Visible: %{count} — grouped, zoom in for individual beaches",
              count: @visible_count
            )}
          </span>
          <span :if={not @clustered?}>{gettext("Visible: %{count}", count: @visible_count)}</span>
        </p>
      </div>

      <form phx-change="filter" class="flex flex-wrap items-center gap-x-6 gap-y-3 text-sm">
        <fieldset class="flex flex-wrap items-center gap-2">
          <legend class="sr-only">{gettext("Dog status")}</legend>
          <.filter_chip
            :for={status <- [:designated, :allowed]}
            name={"dog[#{status}]"}
            checked={status in @filters.dog_status}
            label={dog_status_label(status)}
          />
        </fieldset>

        <fieldset class="flex flex-wrap items-center gap-2">
          <legend class="sr-only">{gettext("Surface")}</legend>
          <.filter_chip
            :for={surface <- [:sand, :pebble, :rock]}
            name={"surface[#{surface}]"}
            checked={surface in @filters.surface}
            label={surface_label(surface)}
          />
        </fieldset>

        <fieldset class="flex flex-wrap items-center gap-2">
          <legend class="sr-only">{gettext("Amenities")}</legend>
          <.filter_chip
            :for={amenity <- BeachFilters.amenity_filters()}
            name={"amenities[#{amenity}]"}
            checked={amenity in @filters.amenities}
            label={amenity_label(amenity)}
          />
        </fieldset>

        <.filter_chip
          name="ferry"
          checked={@filters.without_ferry}
          label={gettext("No ferry")}
        />

        <label class="flex items-center gap-2">
          <span class="text-base-content/70">{gettext("Radius")}</span>
          <select name="radius" class="rounded-lg border border-base-300 bg-base-100 px-2 py-1">
            <option value="" selected={is_nil(@filters.radius_m)}>{gettext("no limit")}</option>
            <option
              :for={radius <- Beaches.radii_m()}
              value={radius}
              selected={@filters.radius_m == radius}
            >
              {gettext("%{count} km", count: div(radius, 1000))}
            </option>
          </select>
        </label>

        <button
          :if={BeachFilters.active?(@filters)}
          type="button"
          phx-click="clear_filters"
          class="text-base-content/60 underline"
        >
          {gettext("Clear filters")}
        </button>
      </form>

      <p
        :if={not @tiles_ok?}
        data-role="tiles-notice"
        role="status"
        class="rounded-lg border border-warning/40 bg-warning/10 px-3 py-2 text-sm"
      >
        {gettext("The background map is not loading. The beach list and distances still work.")}
      </p>

      <p :if={@geolocation in [:idle, :requesting]} class="flex items-center gap-3 text-sm">
        <button
          type="button"
          phx-click="request_location"
          disabled={@geolocation == :requesting}
          data-role="request-location"
          class="inline-flex items-center gap-2 rounded-lg border border-base-300 px-3 py-1.5 font-medium hover:bg-base-200 disabled:opacity-60"
        >
          <.icon name="hero-map-pin" class="size-4" />
          {if @geolocation == :requesting,
            do: gettext("Waiting for location…"),
            else: gettext("Use my location")}
        </button>
        <span class="text-base-content/60">
          {gettext("Until then we measure from the map centre.")}
        </span>
      </p>

      <div
        :if={@geolocation in [:denied, :unavailable, :timeout, :unknown]}
        data-role="place-fallback"
        class="space-y-2 rounded-lg border border-base-300 bg-base-200/60 px-3 py-3"
      >
        <p data-role="geolocation-notice" class="text-sm text-base-content/70">
          {geolocation_message(@geolocation)}
        </p>

        <form phx-change="search_place" phx-submit="search_place" class="relative">
          <label for="place-query" class="sr-only">{gettext("Search for a place")}</label>
          <input
            id="place-query"
            type="text"
            name="q"
            value={@place_query}
            autocomplete="off"
            placeholder={gettext("Type a place, e.g. Split")}
            phx-debounce="400"
            class="w-full rounded-lg border border-base-300 bg-base-100 px-3 py-2 text-sm"
          />

          <p :if={@place_search == :searching} class="mt-1 text-xs text-base-content/60">
            {gettext("Searching…")}
          </p>
          <p :if={@place_search == :empty} class="mt-1 text-xs text-base-content/60">
            {gettext("No place with that name in Croatia.")}
          </p>
          <p :if={@place_search == :error} class="mt-1 text-xs text-warning">
            {gettext("Place search is not working right now. Move the map manually.")}
          </p>

          <ul
            :if={@places != []}
            class="mt-2 divide-y divide-base-300 overflow-hidden rounded-lg border border-base-300 bg-base-100"
          >
            <li :for={place <- @places}>
              <button
                type="button"
                phx-click="select_place"
                phx-value-lat={place_lat(place)}
                phx-value-lon={place_lon(place)}
                data-role="place-result"
                class="block w-full px-3 py-2 text-left text-sm hover:bg-base-200"
              >
                <span class="font-medium">{place.name}</span>
                <span :if={place.description} class="block text-xs text-base-content/60">
                  {place.description}
                </span>
              </button>
            </li>
          </ul>
        </form>
      </div>

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
            <div class="flex items-center justify-between gap-2">
              <h2 class="text-xs font-semibold uppercase tracking-wide text-base-content/60">
                {if @user_location,
                  do: gettext("Closest to you"),
                  else: gettext("Closest to map centre")}
              </h2>
              <form phx-change="sort" data-role="sort">
                <label class="flex items-center gap-1 text-xs text-base-content/60">
                  <span>{gettext("Sort")}</span>
                  <select
                    name="sort"
                    class="rounded border border-base-300 bg-base-100 px-1 py-0.5 text-base-content"
                  >
                    <option value="distance" selected={@filters.sort == :distance}>
                      {gettext("Straight-line distance")}
                    </option>
                    <option value="driving" selected={@filters.sort == :driving}>
                      {gettext("Driving time")}
                    </option>
                  </select>
                </label>
              </form>
            </div>
            <p
              :if={@filters.sort == :driving and @beaches != [] and @driving == %{}}
              data-role="sort-fallback"
              class="mt-1 text-xs text-base-content/60"
            >
              {gettext("Driving time is not available yet; sorted by straight-line distance.")}
            </p>
          </div>

          <p :if={@beaches == []} class="px-4 py-6 text-sm text-base-content/60">
            {empty_message(@filters)}
          </p>

          <ul class="divide-y divide-base-300">
            <li :for={beach <- ordered(@beaches, @driving, @filters.sort)}>
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
                    {beach.name || gettext("Unnamed beach")}
                  </span>
                  <%!-- Vecina plaza u OSM-u nema ime, pa bi lista bez podloge
                        bila dvadeset identicnih redaka. --%>
                  <span class="block text-xs text-base-content/60">
                    {dog_status_label(beach.dog_status)} · {surface_label(beach.surface)}
                  </span>
                  <span
                    :if={beach.across_sea}
                    data-role="across-sea"
                    class="mt-1 inline-flex items-center gap-1 rounded bg-sky-100 px-1.5 py-0.5 text-[11px] font-medium text-sky-900"
                  >
                    <.icon name="hero-arrows-right-left" class="size-3" /> {gettext("across the sea")}
                  </span>
                </span>
                <span class="shrink-0 text-right">
                  <span
                    :if={@driving[beach.id]}
                    data-role="driving"
                    class="block text-xs font-medium tabular-nums"
                  >
                    {format_duration(@driving[beach.id].duration_s)}
                  </span>
                  <span
                    :if={beach.distance_m}
                    data-role="distance"
                    class="block text-xs tabular-nums text-base-content/60"
                    title={
                      if @driving[beach.id],
                        do: gettext("Straight-line distance"),
                        else: gettext("Straight-line distance; driving time unavailable")
                    }
                  >
                    {if @driving[beach.id], do: "", else: "≈ "}{format_distance(beach.distance_m)}
                  </span>
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
              {gettext("Open details of the selected beach")}
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

  defp geolocation_reason("denied"), do: :denied
  defp geolocation_reason("unavailable"), do: :unavailable
  defp geolocation_reason("timeout"), do: :timeout
  defp geolocation_reason(_other), do: :unknown

  defp place_lat(%{point: %Geo.Point{coordinates: {_lon, lat}}}), do: to_string(lat)
  defp place_lon(%{point: %Geo.Point{coordinates: {lon, _lat}}}), do: to_string(lon)

  defp geolocation_message(:denied),
    do:
      gettext(
        "Without your location we measure from the map centre. Type a place or move the map."
      )

  defp geolocation_message(:unavailable),
    do: gettext("This browser does not offer location. Type a place or move the map.")

  defp geolocation_message(:timeout),
    do:
      gettext(
        "Your location did not arrive in time. Indoors, GPS often stays quiet — type a place or move the map."
      )

  defp geolocation_message(:unknown),
    do: gettext("Your location could not be retrieved. Type a place or move the map.")

  defp geolocation_message(_), do: nil

  defp empty_message(filters) do
    if BeachFilters.active?(filters) do
      gettext("No beach in this part of the map matches the filters.")
    else
      gettext("No beaches in this part of the map. Move or zoom out.")
    end
  end
end
