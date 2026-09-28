defmodule DogoWeb.Locale do
  @moduledoc """
  Odabir jezika.

  Redoslijed: **cookie** (korisnik je izabrao), pa `Accept-Language`
  (preglednik), pa zadani jezik. Ručni izbor je najjači jer je jedini izravan.

  Isti modul služi i običnim zahtjevima (kroz `plug`) i LiveViewima (kroz
  `on_mount`), da se pravilo ne piše dvaput.
  """

  import Plug.Conn

  @cookie "dogo_locale"
  # Godina: izbor jezika nema razloga isteći.
  @max_age 365 * 24 * 60 * 60

  @doc "Ime cookieja u kojem se pamti jezik."
  def cookie, do: @cookie

  @doc "Podržani jezici."
  def supported, do: Gettext.known_locales(DogoWeb.Gettext)

  @doc "Zadani jezik."
  def default, do: Gettext.get_locale(DogoWeb.Gettext)

  @doc """
  Plug: postavlja jezik za zahtjev i pamti ga u sesiji, odakle ga LiveView
  preuzima pri spajanju.
  """
  def init(opts), do: opts

  def call(conn, _opts) do
    conn = fetch_cookies(conn)
    locale = pick([conn.cookies[@cookie], accept_language(conn)])

    Gettext.put_locale(DogoWeb.Gettext, locale)

    conn
    |> put_session(:locale, locale)
    |> assign(:locale, locale)
  end

  @doc """
  `on_mount` hook: LiveView proces je zaseban od plug procesa, pa jezik mora
  postaviti i sam.
  """
  def on_mount(:default, _params, session, socket) do
    Gettext.put_locale(DogoWeb.Gettext, pick([session["locale"]]))

    # Prebacivanje jezika mora vratiti korisnika na istu stranicu, pa layout
    # treba znati gdje je. Hook je ovdje da se ne pise u svakom LiveViewu.
    {:cont,
     Phoenix.LiveView.attach_hook(socket, :current_path, :handle_params, &put_current_path/3)}
  end

  defp put_current_path(_params, uri, socket) do
    path = URI.parse(uri) |> Map.get(:path) || "/"

    {:cont, Phoenix.Component.assign(socket, :current_path, path)}
  end

  @doc """
  Sprema izbor u cookie. Vraća `conn`.
  """
  def put_cookie(conn, locale) do
    if supported?(locale) do
      put_resp_cookie(conn, @cookie, locale, max_age: @max_age, same_site: "Lax")
    else
      conn
    end
  end

  @doc "Prvi podržani jezik iz popisa, ili zadani."
  def pick(candidates) do
    candidates
    |> List.flatten()
    |> Enum.find(&supported?/1)
    |> Kernel.||(default())
  end

  @doc """
  Jezici iz `Accept-Language`, poredani po kvaliteti.

      "de-AT,de;q=0.9,en;q=0.8" -> ["de", "de", "en"]
  """
  def accept_language(conn) do
    conn
    |> get_req_header("accept-language")
    |> List.first()
    |> parse_accept_language()
  end

  defp parse_accept_language(nil), do: []

  defp parse_accept_language(header) do
    header
    |> String.split(",")
    |> Enum.map(&parse_language/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(fn {_language, quality} -> quality end, :desc)
    |> Enum.map(fn {language, _quality} -> language end)
  end

  defp parse_language(part) do
    case String.split(part, ";") do
      [language] -> {base(language), 1.0}
      [language, quality] -> {base(language), parse_quality(quality)}
      _ -> nil
    end
  end

  # "de-AT" i "de" su isti jezik za našu svrhu.
  defp base(language), do: language |> String.trim() |> String.split("-") |> hd()

  defp parse_quality("q=" <> value) do
    case Float.parse(value) do
      {quality, _rest} -> quality
      :error -> 0.0
    end
  end

  defp parse_quality(_other), do: 0.0

  defp supported?(nil), do: false
  defp supported?(locale), do: locale in supported()
end
