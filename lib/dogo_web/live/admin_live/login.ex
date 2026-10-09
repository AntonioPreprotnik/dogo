defmodule DogoWeb.AdminLive.Login do
  @moduledoc """
  Prijava admina emailom i lozinkom.

  Forma se predaje `AdminSessionController`u (`phx-trigger-action`), jer
  sesiju može postaviti samo HTTP odgovor. Ista stranica služi i za ponovnu
  prijavu prije osjetljivih radnji (sudo), kad je email već poznat.
  """
  use DogoWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path={@current_path}>
      <div class="mx-auto max-w-sm space-y-4">
        <.header>
          {gettext("Administrator log in")}
          <:subtitle>
            <%= if @current_scope do %>
              {gettext("Log in again to change sensitive settings.")}
            <% else %>
              {gettext("Accounts are created by the operator; there is no sign-up.")}
            <% end %>
          </:subtitle>
        </.header>

        <.form
          :let={f}
          for={@form}
          id="login_form"
          action={~p"/admin/log-in"}
          phx-submit="submit"
          phx-trigger-action={@trigger_submit}
        >
          <.input
            readonly={!!@current_scope}
            field={f[:email]}
            type="email"
            label={gettext("Email")}
            autocomplete="username"
            spellcheck="false"
            required
            phx-mounted={JS.focus()}
          />
          <.input
            field={f[:password]}
            type="password"
            label={gettext("Password")}
            autocomplete="current-password"
            spellcheck="false"
            required
          />
          <.input field={f[:remember_me]} type="checkbox" label={gettext("Keep me logged in")} />
          <.button variant="primary" class="btn btn-primary w-full" phx-disable-with="…">
            {gettext("Log in")}
          </.button>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    email =
      Phoenix.Flash.get(socket.assigns.flash, :email) ||
        get_in(socket.assigns, [:current_scope, Access.key(:admin), Access.key(:email)])

    form = to_form(%{"email" => email}, as: "admin")

    {:ok,
     socket
     |> assign(:page_title, gettext("Administrator log in"))
     |> assign(form: form, trigger_submit: false)}
  end

  @impl true
  def handle_event("submit", _params, socket) do
    {:noreply, assign(socket, :trigger_submit, true)}
  end
end
