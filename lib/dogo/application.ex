defmodule Dogo.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      DogoWeb.Telemetry,
      Dogo.Repo,
      {DNSCluster, query: Application.get_env(:dogo, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Dogo.PubSub},
      {Oban, Application.fetch_env!(:dogo, Oban)},
      Dogo.Geo.PlaceCache,
      Dogo.Geo.RouteCache,
      {Dogo.Geo.RateLimiter, Application.get_env(:dogo, :nominatim_rate_limiter, [])},
      # Start a worker by calling: Dogo.Worker.start_link(arg)
      # {Dogo.Worker, arg},
      # Start to serve requests, typically the last entry
      DogoWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Dogo.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    DogoWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
