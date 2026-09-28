import maplibregl from "../../vendor/maplibre-gl.js"

// Karta se ne smije ponovno crtati na svaki LiveView render, pa kontejner nosi
// phx-update="ignore". Sva komunikacija ide iskljucivo kroz evente.
const BOUNDS_DEBOUNCE_MS = 300
const SOURCE_ID = "beaches"
const LAYER_ID = "beaches-circles"

const escapeHtml = (value) =>
  String(value).replace(/[&<>"']/g, (c) =>
    ({"&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;", "'": "&#39;"})[c]
  )

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
      this.map.addSource(SOURCE_ID, {
        type: "geojson",
        data: {type: "FeatureCollection", features: []}
      })

      // Boju odreduje sam MapLibre iz svojstva dog_status, pa se pri
      // osvjezavanju podataka salje samo GeoJSON, bez ponovnog stila.
      this.map.addLayer({
        id: LAYER_ID,
        type: "circle",
        source: SOURCE_ID,
        paint: {
          "circle-radius": ["interpolate", ["linear"], ["zoom"], 7, 4, 12, 7, 16, 10],
          "circle-color": ["match", ["get", "dog_status"], ...config.colors, config.fallbackColor],
          "circle-stroke-width": 1.5,
          "circle-stroke-color": "#ffffff"
        }
      })

      this.bindPopup()
      this.pushBounds()
    })

    // moveend pokriva i pomicanje i zoom. Debounce postoji jer korisnik na
    // mobitelu rijetko stane iz prve.
    this.map.on("moveend", () => this.scheduleBoundsPush())

    this.handleEvent("beaches", ({geojson}) => {
      const source = this.map.getSource(SOURCE_ID)
      if (source) source.setData(geojson)
    })

    this.handleEvent("fly_to", ({lon, lat, zoom}) => {
      this.map.flyTo({center: [lon, lat], zoom: zoom || this.map.getZoom()})
    })
  },

  destroyed() {
    clearTimeout(this.boundsTimer)
    if (this.popup) this.popup.remove()
    if (this.map) this.map.remove()
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
    const bounds = this.map.getBounds()

    this.pushEvent("bounds_changed", {
      west: bounds.getWest(),
      south: bounds.getSouth(),
      east: bounds.getEast(),
      north: bounds.getNorth(),
      zoom: this.map.getZoom()
    })
  }
}
