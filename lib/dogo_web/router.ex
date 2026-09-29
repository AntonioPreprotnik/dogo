defmodule DogoWeb.Router do
  use DogoWeb, :router

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

  pipeline :dashboard_auth do
    plug DogoWeb.Plugs.DashboardAuth
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

  # LiveDashboard u produkciji, iza basic autha. Bez postavljenih
  # vjerodajnica ruta vraca 404 (DogoWeb.Plugs.DashboardAuth).
  scope "/admin" do
    pipe_through [:browser, :dashboard_auth]

    live_dashboard "/dashboard",
      metrics: DogoWeb.Telemetry,
      ecto_repos: [Dogo.Repo],
      live_session_name: :admin_dashboard
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
