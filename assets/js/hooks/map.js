import maplibregl from "../../vendor/maplibre-gl.js"

// Karta se ne smije ponovno crtati na svaki LiveView render, pa kontejner nosi
// phx-update="ignore". Sva komunikacija ide iskljucivo kroz evente.
const BOUNDS_DEBOUNCE_MS = 300
const GEOLOCATION_TIMEOUT_MS = 10000
const TILE_ERROR_GRACE_MS = 2500
const BOUNDS_FALLBACK_MS = 4000
const USER_ZOOM = 12
const SOURCE_ID = "beaches"
const CLUSTER_SOURCE_ID = "beach-clusters"
const LAYER_ID = "beaches-circles"
const CLUSTER_LAYERS = ["beaches-cluster", "server-cluster"]
const EMPTY = {type: "FeatureCollection", features: []}

const escapeHtml = (value) =>
  String(value).replace(/[&<>"']/g, (c) =>
    ({"&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;", "'": "&#39;"})[c]
  )

// W3C PositionError: 1 = PERMISSION_DENIED, 2 = POSITION_UNAVAILABLE, 3 = TIMEOUT.
// Prevodimo ih ovdje, da server ne mora znati nista o toj specifikaciji.
const geolocationReason = (error) =>
  ({1: "denied", 2: "unavailable", 3: "timeout"})[error.code] || "unknown"

export default {
  mounted() {
    const config = JSON.parse(this.el.dataset.config)

    this.map = new maplibregl.Map({
      container: this.el,
      style: config.styleUrl,
      center: [config.center.lon, config.center.lat],
      zoom: config.zoom,
      attributionControl: {compact: true}
    })

    this.map.addControl(new maplibregl.NavigationControl({showCompass: false}), "top-right")
    this.map.addControl(new maplibregl.ScaleControl({unit: "metric"}), "bottom-left")

    this.map.on("load", () => {
      // Ispod praga server salje pojedinacne plaze i MapLibre ih sam klasterira.
      this.map.addSource(SOURCE_ID, {
        type: "geojson",
        data: EMPTY,
        cluster: true,
        clusterMaxZoom: 13,
        clusterRadius: 48
      })

      // Iznad praga server salje vec agregirane celije. Klijent ih ne smije
      // sam klasterirati — broj u njima je vec konacan.
      this.map.addSource(CLUSTER_SOURCE_ID, {type: "geojson", data: EMPTY})

      // Boju odreduje sam MapLibre iz svojstva dog_status, pa se pri
      // osvjezavanju podataka salje samo GeoJSON, bez ponovnog stila.
      this.map.addLayer({
        id: LAYER_ID,
        type: "circle",
        source: SOURCE_ID,
        filter: ["!", ["has", "point_count"]],
        paint: {
          "circle-radius": ["interpolate", ["linear"], ["zoom"], 7, 4, 12, 7, 16, 10],
          "circle-color": ["match", ["get", "dog_status"], ...config.colors, config.fallbackColor],
          "circle-stroke-width": 1.5,
          "circle-stroke-color": "#ffffff"
        }
      })

      this.addClusterLayers("beaches-cluster", SOURCE_ID, ["has", "point_count"])
      this.addClusterLayers("server-cluster", CLUSTER_SOURCE_ID, ["has", "point_count"])

      this.bindPopup()
      this.bindClusterZoom()
      this.pushBounds()
    })

    // moveend pokriva i pomicanje i zoom. Debounce postoji jer korisnik na
    // mobitelu rijetko stane iz prve.
    this.map.on("moveend", () => this.scheduleBoundsPush())

    this.handleEvent("beaches", ({geojson}) => {
      this.setData(SOURCE_ID, geojson)
      this.setData(CLUSTER_SOURCE_ID, EMPTY)
    })

    this.handleEvent("clusters", ({geojson}) => {
      this.setData(CLUSTER_SOURCE_ID, geojson)
      this.setData(SOURCE_ID, EMPTY)
    })

    this.handleEvent("fly_to", ({lon, lat, zoom}) => {
      this.map.flyTo({center: [lon, lat], zoom: zoom || this.map.getZoom()})
    })

    this.watchTiles()

    // Lokaciju trazimo sami samo ako je korisnik vec jednom pristao — tada
    // nema dijaloga. Inace cekamo da klikne gumb: iskakanje dijaloga cim se
    // stranica otvori je losa praksa i korisnici ga refleksno odbiju.
    this.handleEvent("request_location", () => this.locateUser())
    this.locateIfAlreadyAllowed()

    // Ako stil ne uspije, MapLibre nikad ne emitira `load`, pa granice ne bi
    // nikad stigle na server i lista bi ostala prazna — bas u trenutku kad
    // korisniku poruka obecava da lista radi. Transform (sredina i zoom)
    // postoji i bez stila, pa se granice mogu poslati svejedno.
    this.boundsFallback = setTimeout(() => {
      if (!this.boundsPushed) this.pushBounds()
    }, BOUNDS_FALLBACK_MS)
  },

  destroyed() {
    clearTimeout(this.boundsTimer)
    clearTimeout(this.tileTimer)
    clearTimeout(this.boundsFallback)
    if (this.popup) this.popup.remove()
    if (this.userMarker) this.userMarker.remove()
    if (this.map) this.map.remove()
  },

  async locateIfAlreadyAllowed() {
    if (!navigator.geolocation) {
      this.pushEvent("geolocation_error", {reason: "unavailable"})
      return
    }

    // Permissions API ne postoji svugdje; bez njega ne znamo stanje, pa
    // pitamo korisnika umjesto da pretpostavljamo.
    if (!navigator.permissions) {
      this.pushEvent("geolocation_idle", {})
      return
    }

    try {
      const status = await navigator.permissions.query({name: "geolocation"})

      if (status.state === "granted") {
        this.locateUser()
      } else if (status.state === "denied") {
        this.pushEvent("geolocation_error", {reason: "denied"})
      } else {
        this.pushEvent("geolocation_idle", {})
      }
    } catch (_error) {
      this.pushEvent("geolocation_idle", {})
    }
  },

  locateUser() {
    if (!navigator.geolocation) {
      this.pushEvent("geolocation_error", {reason: "unavailable"})
      return
    }

    navigator.geolocation.getCurrentPosition(
      ({coords}) => this.onLocated(coords),
      (error) => this.pushEvent("geolocation_error", {reason: geolocationReason(error)}),
      {enableHighAccuracy: false, timeout: GEOLOCATION_TIMEOUT_MS, maximumAge: 60000}
    )
  },

  // MapLibre javlja greske i za pojedinacne ploce i za cijeli stil. Jedna
  // promasena ploca nije vrijedna poruke korisniku, pa cekamo da se karta
  // smiri (`idle`) i tek onda presudimo.
  watchTiles() {
    this.tileErrors = 0

    this.map.on("error", (event) => {
      if (event.sourceId === "beaches") return

      this.tileErrors += 1
      clearTimeout(this.tileTimer)
      this.tileTimer = setTimeout(() => this.reportTiles(), TILE_ERROR_GRACE_MS)
    })

    this.map.on("idle", () => {
      if (this.tileErrors > 0 || this.tilesReportedBroken) {
        clearTimeout(this.tileTimer)
        this.tileErrors = 0
        this.reportTiles()
      }
    })
  },

  reportTiles() {
    // `areTilesLoaded()` je presuda: ako su sve trazene ploce stigle, greske
    // su bile prolazne i korisnik o njima ne treba znati.
    const broken = !this.map.areTilesLoaded() || !this.map.isStyleLoaded()

    if (broken !== this.tilesReportedBroken) {
      this.tilesReportedBroken = broken
      this.pushEvent("map_tiles", {ok: !broken})
    }
  },

  onLocated({latitude, longitude}) {
    // Marker crtamo lokalno. Server ga ne mora vratiti, pa lokacija ne putuje
    // mrezom vise nego sto mora.
    this.showUserMarker(longitude, latitude)

    this.map.flyTo({center: [longitude, latitude], zoom: USER_ZOOM})

    // Ugnijezdeno pod "location" jer je taj kljuc u :filter_parameters, pa
    // LiveView logger ispise [FILTERED] umjesto koordinata.
    this.pushEvent("user_located", {location: {lat: latitude, lon: longitude}})
  },

  showUserMarker(lon, lat) {
    if (this.userMarker) {
      this.userMarker.setLngLat([lon, lat])
      return
    }

    const element = document.createElement("div")
    element.className = "user-marker"
    element.setAttribute("aria-label", "Tvoja lokacija")

    this.userMarker = new maplibregl.Marker({element})
      .setLngLat([lon, lat])
      .addTo(this.map)
  },

  setData(sourceId, geojson) {
    const source = this.map.getSource(sourceId)
    if (source) source.setData(geojson)
  },

  // Klaster je krug s brojem. Isti izgled za oba izvora, da korisnik ne vidi
  // razliku izmedu klijentskog i serverskog klasteriranja.
  addClusterLayers(id, sourceId, filter) {
    this.map.addLayer({
      id: id,
      type: "circle",
      source: sourceId,
      filter: filter,
      paint: {
        "circle-color": "#1e293b",
        "circle-opacity": 0.85,
        "circle-stroke-width": 2,
        "circle-stroke-color": "#ffffff",
        "circle-radius": [
          "step",
          ["get", "point_count"],
          14,
          10, 18,
          50, 22,
          200, 28
        ]
      }
    })

    this.map.addLayer({
      id: `${id}-count`,
      type: "symbol",
      source: sourceId,
      filter: filter,
      layout: {
        "text-field": ["get", "point_count_abbreviated"],
        "text-font": ["Noto Sans Bold"],
        "text-size": 12
      },
      paint: {"text-color": "#ffffff"}
    })
  },

  bindClusterZoom() {
    for (const layer of CLUSTER_LAYERS) {
      this.map.on("click", layer, (event) => {
        const feature = event.features[0]
        const center = feature.geometry.coordinates

        // Klijentski klaster zna tocan zoom na kojem se raspada. Serverski
        // ne postoji u MapLibreovom indeksu, pa mu samo priblizimo kartu.
        const source = this.map.getSource(SOURCE_ID)

        if (feature.properties.cluster_id !== undefined && source.getClusterExpansionZoom) {
          source
            .getClusterExpansionZoom(feature.properties.cluster_id)
            .then((zoom) => this.map.easeTo({center, zoom}))
            .catch(() => this.map.easeTo({center, zoom: this.map.getZoom() + 2}))
        } else {
          this.map.easeTo({center, zoom: this.map.getZoom() + 2})
        }
      })

      this.map.on("mouseenter", layer, () => {
        this.map.getCanvas().style.cursor = "pointer"
      })
      this.map.on("mouseleave", layer, () => {
        this.map.getCanvas().style.cursor = ""
      })
    }
  },

  bindPopup() {
    this.popup = new maplibregl.Popup({closeButton: true, closeOnClick: true, maxWidth: "260px"})

    this.map.on("click", LAYER_ID, (event) => {
      const feature = event.features[0]
      const [lon, lat] = feature.geometry.coordinates

      this.popup
        .setLngLat([lon, lat])
        .setHTML(this.popupHtml(feature.properties))
        .addTo(this.map)
    })

    // Bez ovoga korisnik ne zna da je tocka klikabilna.
    this.map.on("mouseenter", LAYER_ID, () => {
      this.map.getCanvas().style.cursor = "pointer"
    })
    this.map.on("mouseleave", LAYER_ID, () => {
      this.map.getCanvas().style.cursor = ""
    })
  },

  popupHtml(properties) {
    const name = escapeHtml(properties.name || "Plaža bez imena")
    const status = escapeHtml(properties.dog_status_label)
    const color = escapeHtml(properties.color)
    const distance = properties.distance_label
      ? `<p class="beach-popup__distance">${escapeHtml(properties.distance_label)}</p>`
      : ""

    return `
      <div class="beach-popup">
        <h3 class="beach-popup__name">${name}</h3>
        <p class="beach-popup__status"><span style="background:${color}"></span>${status}</p>
        ${distance}
        <a class="beach-popup__link" href="/beaches/${properties.id}"
           data-phx-link="redirect" data-phx-link-state="push">Detalji &rarr;</a>
      </div>
    `
  },

  scheduleBoundsPush() {
    clearTimeout(this.boundsTimer)
    this.boundsTimer = setTimeout(() => this.pushBounds(), BOUNDS_DEBOUNCE_MS)
  },

  pushBounds() {
    this.boundsPushed = true
    const bounds = this.map.getBounds()

    const center = this.map.getCenter()

    this.pushEvent("bounds_changed", {
      west: bounds.getWest(),
      south: bounds.getSouth(),
      east: bounds.getEast(),
      north: bounds.getNorth(),
      // Centar salje karta, ne racunamo ga iz granica: u Mercatorovoj
      // projekciji sredina po zemljopisnoj sirini nije sredina ekrana.
      center_lon: center.lng,
      center_lat: center.lat,
      // Sirina u pikselima: server po njoj racuna velicinu celije sazetka, pa
      // su klasteri jednako gusti na mobitelu i na desktopu.
      width_px: Math.round(this.el.clientWidth),
      zoom: this.map.getZoom()
    })
  }
}
