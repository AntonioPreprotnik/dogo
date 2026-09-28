import maplibregl from "../../vendor/maplibre-gl.js"

// Mala karta na detalju plaze: jedna tocka, bez slanja bounds_changed.
// Namjerno nije interaktivna — sluzi za orijentaciju, ne za istrazivanje.
export default {
  mounted() {
    const {styleUrl, lon, lat, zoom, color} = JSON.parse(this.el.dataset.config)

    this.map = new maplibregl.Map({
      container: this.el,
      style: styleUrl,
      center: [lon, lat],
      zoom: zoom,
      attributionControl: {compact: true},
      interactive: false
    })

    this.map.on("load", () => {
      this.map.addSource("beach", {
        type: "geojson",
        data: {type: "Point", coordinates: [lon, lat]}
      })

      this.map.addLayer({
        id: "beach-point",
        type: "circle",
        source: "beach",
        paint: {
          "circle-radius": 9,
          "circle-color": color,
          "circle-stroke-width": 2,
          "circle-stroke-color": "#ffffff"
        }
      })
    })
  },

  destroyed() {
    if (this.map) this.map.remove()
  }
}
