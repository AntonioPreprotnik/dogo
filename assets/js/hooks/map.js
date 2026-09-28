import maplibregl from "../../vendor/maplibre-gl.js"

// Karta se ne smije ponovno crtati na svaki LiveView render, pa kontejner nosi
// phx-update="ignore". Sva komunikacija ide iskljucivo kroz evente.
const BOUNDS_DEBOUNCE_MS = 300
const SOURCE_ID = "beaches"

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

      this.map.addLayer({
        id: "beaches-circles",
        type: "circle",
        source: SOURCE_ID,
        paint: {
          "circle-radius": 6,
          "circle-color": "#2563eb",
          "circle-stroke-width": 1.5,
          "circle-stroke-color": "#ffffff"
        }
      })

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
    if (this.map) this.map.remove()
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
