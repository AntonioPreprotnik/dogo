defmodule DogoWeb.AdminLive.Settings do
  @moduledoc """
  Promjena lozinke admina.

  Traži nedavnu prijavu (sudo), a nakon promjene briše sve sesije, pa se
  odjavljuju i drugi uređaji. Promjene emaila nema: bez maila u produkciji
  ne bi se mogla potvrditi.
  """
  use DogoWeb, :live_view

  on_mount {DogoWeb.AdminAuth, :require_sudo_mode}

  alias Dogo.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <div class="max-w-md">
        <.header>
          {gettext("Settings")}
          <:subtitle>{gettext("Change the password for %{email}.", email: @current_email)}</:subtitle>
        </.header>

        <.form
          for={@password_form}
          id="password_form"
          action={~p"/admin/update-password"}
          method="post"
          phx-change="validate_password"
          phx-submit="update_password"
          phx-trigger-action={@trigger_submit}
        >
          <input
            name={@password_form[:email].name}
            type="hidden"
            id="hidden_admin_email"
            value={@current_email}
          />
          <.input
            field={@password_form[:password]}
            type="password"
            label={gettext("New password")}
            autocomplete="new-password"
            spellcheck="false"
            required
          />
          <.input
            field={@password_form[:password_confirmation]}
            type="password"
            label={gettext("Confirm new password")}
            autocomplete="new-password"
            spellcheck="false"
          />
          <.button variant="primary" phx-disable-with="…">
            {gettext("Save password")}
          </.button>
        </.form>
      </div>
    </Layouts.admin>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    admin = socket.assigns.current_scope.admin
    password_changeset = Accounts.change_admin_password(admin, %{}, hash_password: false)

    {:ok,
     socket
     |> assign(:page_title, gettext("Settings"))
     |> assign(:current_email, admin.email)
     |> assign(:password_form, to_form(password_changeset))
     |> assign(:trigger_submit, false)}
  end

  @impl true
  def handle_event("validate_password", %{"admin" => admin_params}, socket) do
    password_form =
      socket.assigns.current_scope.admin
      |> Accounts.change_admin_password(admin_params, hash_password: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, password_form: password_form)}
  end

  def handle_event("update_password", %{"admin" => admin_params}, socket) do
    admin = socket.assigns.current_scope.admin

    case Accounts.change_admin_password(admin, admin_params, hash_password: false) do
      %{valid?: true} = changeset ->
        {:noreply, assign(socket, trigger_submit: true, password_form: to_form(changeset))}

      changeset ->
        {:noreply, assign(socket, password_form: to_form(changeset, action: :insert))}
    end
  end
end
