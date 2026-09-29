defmodule DogoWeb.ManifestController do
  @moduledoc """
  PWA manifest.

  Ide kroz kontroler, ne kao statička datoteka, jer naziv i opis moraju biti
  na jeziku koji je korisnik izabrao — a to se zna tek za vrijeme zahtjeva.
  """
  use DogoWeb, :controller

  def show(conn, _params) do
    conn
    |> put_resp_content_type("application/manifest+json")
    |> json(%{
      name: gettext("Dogo — dog-friendly beaches"),
      short_name: "Dogo",
      description: gettext("Find the nearest beaches where your dog is welcome."),
      lang: Gettext.get_locale(DogoWeb.Gettext),
      start_url: "/",
      scope: "/",
      display: "standalone",
      orientation: "any",
      background_color: "#ffffff",
      theme_color: "#0c4a6e",
      categories: ["travel", "navigation"],
      icons: [
        %{src: ~p"/icons/icon-192.png", sizes: "192x192", type: "image/png", purpose: "any"},
        %{src: ~p"/icons/icon-512.png", sizes: "512x512", type: "image/png", purpose: "any"},
        %{
          src: ~p"/icons/icon-maskable-512.png",
          sizes: "512x512",
          type: "image/png",
          purpose: "maskable"
        }
      ]
    })
  end
end
