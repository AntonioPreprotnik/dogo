defmodule DogoWeb.Router do
  use DogoWeb, :router

  import DogoWeb.AdminAuth

  import Phoenix.LiveDashboard.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {DogoWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug DogoWeb.Locale
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Samo admin rute citaju sesiju admina; javni dio ne dira tablice admina.
  pipeline :admin do
    plug :fetch_current_scope_for_admin
  end

  scope "/", DogoWeb do
    pipe_through :browser

    live_session :default, on_mount: DogoWeb.Locale do
      live "/", BeachMapLive, :index
      live "/beaches/:id", BeachDetailLive, :show
    end

    post "/locale", LocaleController, :update
    get "/manifest.webmanifest", ManifestController, :show
  end

  scope "/", DogoWeb do
    pipe_through :api

    get "/health", HealthController, :index
  end

  # Admin (E8-S1, ADR 0010). Prijava je izvan zasticenog bloka; sve ostalo
  # trazi prijavljenog admina i kroz plug (HTTP) i kroz on_mount (websocket).
  scope "/admin", DogoWeb do
    pipe_through [:browser, :admin]

    live_session :admin_login,
      on_mount: [DogoWeb.Locale, {DogoWeb.AdminAuth, :mount_current_scope}] do
      live "/log-in", AdminLive.Login, :new
    end

    post "/log-in", AdminSessionController, :create
    delete "/log-out", AdminSessionController, :delete
  end

  scope "/admin", DogoWeb do
    pipe_through [:browser, :admin, :require_authenticated_admin]

    live_session :admin,
      on_mount: [DogoWeb.Locale, {DogoWeb.AdminAuth, :require_authenticated}] do
      live "/beaches", AdminLive.BeachIndex, :index
      live "/beaches/new", AdminLive.BeachForm, :new
      live "/beaches/:id/edit", AdminLive.BeachForm, :edit
      live "/imports", AdminLive.Imports, :index
      live "/settings", AdminLive.Settings, :edit
    end

    post "/update-password", AdminSessionController, :update_password
  end

  # LiveDashboard u produkciji, za prijavljenog admina.
  scope "/admin" do
    pipe_through [:browser, :admin, :require_authenticated_admin]

    live_dashboard "/dashboard",
      metrics: DogoWeb.Telemetry,
      ecto_repos: [Dogo.Repo],
      live_session_name: :admin_dashboard,
      on_mount: [{DogoWeb.AdminAuth, :require_authenticated}]
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:dogo, :dev_routes) do
    # U razvoju bez autentifikacije; produkcijska ruta je /admin/dashboard.
    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: DogoWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
