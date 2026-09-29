defmodule DogoWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use DogoWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :current_path, :string, default: "/", doc: "za povratak nakon promjene jezika"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="border-b border-base-300 bg-base-100">
      <div class="mx-auto flex max-w-5xl items-center justify-between px-4 py-3 sm:px-6">
        <a href={~p"/"} class="flex items-center gap-2 text-lg font-semibold tracking-tight">
          <span aria-hidden="true">🐕</span> Dogo
        </a>
        <div class="flex items-center gap-3">
          <.language_picker current_path={assigns[:current_path] || "/"} />
          <.theme_toggle />
        </div>
      </div>
    </header>

    <main class="px-4 py-8 sm:px-6">
      <div class="mx-auto max-w-5xl space-y-6">
        {render_slot(@inner_block)}
      </div>
    </main>

    <.attribution_footer />

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Prebacivanje jezika.

  Obična forma, ne LiveView event: cookie se može postaviti samo u HTTP
  odgovoru. `return_to` vraća korisnika na istu stranicu.
  """
  attr :current_path, :string, default: "/"

  def language_picker(assigns) do
    assigns =
      assigns
      |> assign(:locales, DogoWeb.Locale.supported())
      |> assign(:locale, Gettext.get_locale(DogoWeb.Gettext))

    ~H"""
    <form action={~p"/locale"} method="post" class="flex items-center gap-1">
      <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
      <input type="hidden" name="return_to" value={@current_path} />
      <button
        :for={locale <- @locales}
        type="submit"
        name="locale"
        value={locale}
        data-role="locale-option"
        data-locale={locale}
        aria-current={locale == @locale && "true"}
        class={[
          "rounded px-1.5 py-0.5 text-xs font-medium uppercase",
          locale == @locale && "bg-base-content text-base-100",
          locale != @locale && "text-base-content/60 hover:bg-base-200"
        ]}
      >
        {locale}
      </button>
    </form>
    """
  end

  @doc """
  Podnožje s atribucijom izvora podataka i disclaimerom.

  Prikazuje se na svakoj stranici: licenca OpenStreetMapa (ODbL) to traži, a
  disclaimer je obavezan jer su atributi vezani uz pse dijelom generirani.
  """
  def attribution_footer(assigns) do
    ~H"""
    <footer class="mt-12 border-t border-base-300 bg-base-200/50">
      <div class="mx-auto max-w-5xl space-y-2 px-4 py-6 text-xs text-base-content/70 sm:px-6">
        <p>
          {gettext("Beach locations:")} <a
            href="https://www.openstreetmap.org/copyright"
            class="link"
            rel="noopener"
            target="_blank"
          >© OpenStreetMap contributors</a>, {gettext("ODbL licence.")}
        </p>
        <p data-role="disclaimer">
          {gettext(
            "The data is for demonstration. Dog-related attributes are partly generated and do not reflect real rules. Check local regulations before you travel."
          )}
        </p>
      </div>
    </footer>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
        aria-label={gettext("Follow system theme")}
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
        aria-label={gettext("Light theme")}
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
        aria-label={gettext("Dark theme")}
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
