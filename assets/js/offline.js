// Zadnji rezultati za rad bez mreze (E6-S3).
//
// Server nakon svake promjene liste salje sazetak (DogoWeb.OfflineSnapshot)
// s vec prevedenim tekstovima. Ovdje ga samo spremamo u IndexedDB i, kad
// socket padne, ispisujemo. Nema logike ni prijevoda na klijentu.
//
// Sazetak ne sadrzi korisnikovu lokaciju — samo plaze.

const DB_NAME = "dogo"
const STORE = "snapshots"
const KEY = "last"

function openDb() {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, 1)
    request.onupgradeneeded = () => request.result.createObjectStore(STORE)
    request.onsuccess = () => resolve(request.result)
    request.onerror = () => reject(request.error)
  })
}

async function withStore(mode, fn) {
  const db = await openDb()

  return new Promise((resolve, reject) => {
    const tx = db.transaction(STORE, mode)
    const request = fn(tx.objectStore(STORE))
    tx.oncomplete = () => resolve(request.result)
    tx.onerror = () => reject(tx.error)
  })
}

const save = (snapshot) =>
  withStore("readwrite", (store) => store.put({...snapshot, savedAt: Date.now()}, KEY))

const load = () => withStore("readonly", (store) => store.get(KEY))

// Imena plaza dolaze iz OSM-a, dakle od bilo koga: sve ide kroz textContent,
// nikad kroz innerHTML.
function el(tag, className, text) {
  const node = document.createElement(tag)
  if (className) node.className = className
  if (text != null) node.textContent = text
  return node
}

function render(container, snapshot) {
  const {labels, beaches, savedAt} = snapshot
  const time = new Date(savedAt).toLocaleTimeString(document.documentElement.lang || undefined, {
    hour: "2-digit",
    minute: "2-digit",
  })

  const header = el("div", "sticky top-0 border-b border-base-300 bg-base-100 px-4 py-3")
  header.append(
    el("span", "inline-block rounded bg-amber-200 px-2 py-0.5 text-xs font-semibold text-amber-950", labels.offline),
    el("p", "mt-2 text-sm text-base-content/70", labels.saved_at.replace("%{time}", time)),
  )

  const list = el("ul", "divide-y divide-base-300")

  for (const beach of beaches) {
    const item = el("li", "flex items-start gap-3 px-4 py-3")
    const dot = el("span", "mt-1.5 size-2.5 shrink-0 rounded-full")
    dot.style.background = beach.color

    const text = el("span", "min-w-0 flex-1")
    text.append(
      el("span", "block truncate font-medium", beach.name),
      el("span", "block text-xs text-base-content/60", beach.details),
    )

    const side = el("span", "shrink-0 text-right")
    if (beach.distance) side.append(el("span", "block text-xs tabular-nums", beach.distance))

    if (typeof beach.navigate_url === "string" && beach.navigate_url.startsWith("https://")) {
      const link = el("a", "block text-xs font-medium underline", labels.navigate)
      link.href = beach.navigate_url
      link.target = "_blank"
      link.rel = "noopener"
      side.append(link)
    }

    item.append(dot, text, side)
    list.append(item)
  }

  container.replaceChildren(header, list)
}

export function setupOffline(liveSocket) {
  if (!("indexedDB" in window)) return

  window.addEventListener("phx:offline_snapshot", ({detail}) => {
    save(detail).catch((error) => console.warn("Sazetak nije spremljen:", error))
  })

  const show = async () => {
    const container = document.getElementById("offline-results")
    if (!container || !container.hidden) return

    try {
      const snapshot = await load()
      if (!snapshot || snapshot.beaches.length === 0) return

      render(container, snapshot)
      container.hidden = false
    } catch (error) {
      console.warn("Sazetak nije ucitan:", error)
    }
  }

  const hide = () => {
    const container = document.getElementById("offline-results")
    if (container) container.hidden = true
  }

  // onError se javlja kod svakog neuspjelog pokusaja spajanja, i kad je
  // stranica otvorena bez mreze (iz cachea service workera) i kad veza padne
  // usred rada. show je idempotentan, pa ponavljanje ne smeta.
  const socket = liveSocket.getSocket()
  socket.onError(show)
  socket.onOpen(hide)
}
