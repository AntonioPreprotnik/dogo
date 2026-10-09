defmodule DogoWeb.AdminLive.BeachForm do
  @moduledoc """
  Ručno dodavanje i ispravljanje plaže.

  Spremanje postavlja `edited_at`, pa uvoz plažu više ne mijenja (ADR 0011).
  Forma to kaže prije spremanja, jer je posljedica nevidljiva.
  """
  use DogoWeb, :live_view

  alias Dogo.Beaches
  alias Dogo.Beaches.Beach

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <.link
        navigate={~p"/admin/beaches"}
        class="inline-flex items-center gap-1 text-sm text-base-content/70"
      >
        <.icon name="hero-arrow-left" class="size-4" /> {gettext("All beaches")}
      </.link>

      <.header>
        {@page_title}
        <:subtitle :if={@live_action == :edit}>
          <span data-role="osm-id">{@beach.osm_id}</span>
          <.link navigate={~p"/beaches/#{@beach}"} class="ml-2 link text-xs">
            {gettext("Public page")}
          </.link>
        </:subtitle>
      </.header>

      <div
        :if={@live_action == :edit and is_nil(@beach.edited_at)}
        id="import-notice"
        class="rounded-lg border border-warning/40 bg-warning/10 p-3 text-sm"
      >
        {gettext(
          "This beach comes from the import. After you save, future imports will no longer change it."
        )}
      </div>

      <.form for={@form} id="beach-form" phx-change="validate" phx-submit="save" class="max-w-xl">
        <.input field={@form[:name]} type="text" label={gettext("Name")} />
        <.input field={@form[:municipality]} type="text" label={gettext("Municipality")} />

        <div class="grid grid-cols-2 gap-4">
          <.input field={@form[:lat]} type="number" step="any" label={gettext("Latitude")} required />
          <.input field={@form[:lon]} type="number" step="any" label={gettext("Longitude")} required />
        </div>
        <p
          :for={msg <- geom_errors(@form)}
          class="-mt-1 mb-2 text-sm text-error"
          data-role="geom-error"
        >
          {msg}
        </p>

        <div class="grid grid-cols-2 gap-4">
          <.input
            field={@form[:dog_status]}
            type="select"
            label={gettext("Dogs")}
            options={Enum.map(Beach.dog_statuses(), &{dog_status_label(&1), &1})}
          />
          <.input
            field={@form[:surface]}
            type="select"
            label={gettext("Surface")}
            options={Enum.map(Beach.surfaces(), &{surface_label(&1), &1})}
          />
        </div>

        <fieldset class="fieldset mb-2">
          <legend class="fieldset-legend">{gettext("Amenities")}</legend>
          <.input
            :for={key <- Beach.amenity_keys()}
            type="checkbox"
            id={"beach_amenities_#{key}"}
            name={"#{@form[:amenities].name}[#{key}]"}
            value={amenity_value(@form, key)}
            label={amenity_label(key)}
          />
        </fieldset>

        <.button variant="primary" phx-disable-with="…" id="save-beach">
          {gettext("Save")}
        </.button>
      </.form>
    </Layouts.admin>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    {:ok, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    beach = %Beach{}

    socket
    |> assign(:page_title, gettext("New beach"))
    |> assign(:beach, beach)
    |> assign(:form, to_form(Beaches.change_beach_as_admin(beach)))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    beach = Beaches.get_beach!(id)

    socket
    |> assign(:page_title, beach.name || gettext("Unnamed beach"))
    |> assign(:beach, beach)
    |> assign(:form, to_form(Beaches.change_beach_as_admin(beach)))
  end

  @impl true
  def handle_event("validate", %{"beach" => params}, socket) do
    changeset = Beaches.change_beach_as_admin(socket.assigns.beach, params)
    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"beach" => params}, socket) do
    save(socket, socket.assigns.live_action, params)
  end

  defp save(socket, :new, params) do
    socket.assigns.current_scope
    |> Beaches.create_beach_as_admin(params)
    |> after_save(socket, gettext("Beach created."))
  end

  defp save(socket, :edit, params) do
    socket.assigns.current_scope
    |> Beaches.update_beach_as_admin(socket.assigns.beach, params)
    |> after_save(socket, gettext("Beach saved."))
  end

  defp after_save({:ok, _beach}, socket, message) do
    {:noreply,
     socket
     |> put_flash(:info, message)
     |> push_navigate(to: ~p"/admin/beaches")}
  end

  defp after_save({:error, changeset}, socket, _message) do
    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  defp amenity_value(form, key) do
    case form[:amenities].value do
      %{} = amenities -> Map.get(amenities, key, false)
      _ -> false
    end
  end

  # Greška točke (npr. izvan hrvatske obale) je na `geom`, koji forma nema
  # kao polje, pa se ispisuje ispod koordinata.
  defp geom_errors(form), do: Enum.map(form[:geom].errors, &translate_error/1)
end
