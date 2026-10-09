defmodule DogoWeb.AdminLive.BeachIndex do
  @moduledoc """
  Admin popis plaža: pretraga, stranice, brisanje.

  Pretraga i stranica su u URL-u, pa se popis može osvježiti ili podijeliti
  bez gubitka stanja (isto načelo kao filteri na karti, E3-S6).
  """
  use DogoWeb, :live_view

  alias Dogo.Beaches

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <.header>
        {gettext("Beaches")}
        <:subtitle>
          {ngettext("%{count} beach", "%{count} beaches", @total)}
        </:subtitle>
        <:actions>
          <.button variant="primary" navigate={~p"/admin/beaches/new"} id="new-beach">
            <.icon name="hero-plus" class="size-4" /> {gettext("New beach")}
          </.button>
        </:actions>
      </.header>

      <.form for={@search_form} id="beach-search" phx-change="search" phx-submit="search">
        <.input
          field={@search_form[:q]}
          type="search"
          placeholder={gettext("Name, municipality or OSM ID")}
          phx-debounce="300"
          autocomplete="off"
        />
      </.form>

      <div class="overflow-x-auto">
        <.table id="beaches" rows={@streams.beaches}>
          <:col :let={{_id, beach}} label={gettext("Name")}>
            <div class="font-medium">{beach.name || gettext("Unnamed beach")}</div>
            <div class="text-xs text-base-content/60">{beach.osm_id}</div>
          </:col>
          <:col :let={{_id, beach}} label={gettext("Municipality")}>
            {beach.municipality}
          </:col>
          <:col :let={{_id, beach}} label={gettext("Dogs")}>
            <div class="flex flex-col gap-1">
              <.dog_status status={beach.dog_status} />
              <.dog_status_source source={beach.dog_status_source} />
            </div>
          </:col>
          <:col :let={{_id, beach}} label={gettext("Edited")}>
            <span :if={beach.edited_at} data-role="edited-at" class="text-xs">
              {Calendar.strftime(beach.edited_at, "%Y-%m-%d")}
            </span>
          </:col>
          <:action :let={{_id, beach}}>
            <.link navigate={~p"/admin/beaches/#{beach}/edit"} id={"edit-beach-#{beach.id}"}>
              {gettext("Edit")}
            </.link>
          </:action>
          <:action :let={{id, beach}}>
            <.link
              phx-click={JS.push("delete", value: %{id: beach.id}) |> hide("##{id}")}
              data-confirm={delete_confirmation(beach)}
              id={"delete-beach-#{beach.id}"}
              class="text-error"
            >
              {gettext("Delete")}
            </.link>
          </:action>
        </.table>
      </div>

      <p :if={@total == 0} id="no-beaches" class="text-sm text-base-content/70">
        {gettext("No beaches match the search.")}
      </p>

      <nav :if={@total_pages > 1} class="flex items-center justify-between text-sm" id="pagination">
        <.link
          :if={@page > 1}
          patch={page_path(@query, @page - 1)}
          class="btn btn-sm"
          id="previous-page"
        >
          ← {gettext("Previous")}
        </.link>
        <span class="text-base-content/70">
          {gettext("Page %{page} of %{total}", page: @page, total: @total_pages)}
        </span>
        <.link
          :if={@page < @total_pages}
          patch={page_path(@query, @page + 1)}
          class="btn btn-sm"
          id="next-page"
        >
          {gettext("Next")} →
        </.link>
      </nav>
    </Layouts.admin>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, gettext("Beaches"))}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    query = params["q"] || ""
    page = parse_page(params["page"])

    {:noreply, socket |> assign(:query, query) |> load(page)}
  end

  @impl true
  def handle_event("search", %{"q" => query}, socket) do
    {:noreply, push_patch(socket, to: page_path(query, 1))}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    beach = Beaches.get_beach!(id)
    {:ok, _} = Beaches.delete_beach(socket.assigns.current_scope, beach)

    {:noreply,
     socket
     |> put_flash(:info, gettext("Beach deleted."))
     |> load(socket.assigns.page)}
  end

  defp load(socket, page) do
    result =
      Beaches.list_beaches_for_admin(socket.assigns.current_scope,
        query: socket.assigns.query,
        page: page
      )

    socket
    |> assign(:search_form, to_form(%{"q" => socket.assigns.query}))
    |> assign(:page, result.page)
    |> assign(:total_pages, result.total_pages)
    |> assign(:total, result.total)
    |> stream(:beaches, result.entries, reset: true)
  end

  defp page_path(query, page) do
    params = Enum.reject([q: query, page: page], fn {_k, v} -> v in ["", nil, 1] end)
    ~p"/admin/beaches?#{params}"
  end

  defp parse_page(value) when is_binary(value) do
    case Integer.parse(value) do
      {page, ""} when page > 0 -> page
      _ -> 1
    end
  end

  defp parse_page(_value), do: 1

  # Plaža iz OSM-a se vraća pri sljedećem uvozu (vidi Beaches.delete_beach/2),
  # pa admin to mora znati prije nego potvrdi.
  defp delete_confirmation(%{osm_id: "manual/" <> _}), do: gettext("Delete this beach?")

  defp delete_confirmation(_beach) do
    gettext(
      "Delete this beach? It comes from OpenStreetMap and will return with the next import."
    )
  end
end
