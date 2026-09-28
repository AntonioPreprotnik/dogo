import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :dogo, Dogo.Repo,
  username: System.get_env("PGUSER", "postgres"),
  password: System.get_env("PGPASSWORD", "postgres"),
  hostname: System.get_env("PGHOST", "localhost"),
  port: String.to_integer(System.get_env("PGPORT", "5432")),
  database: "dogo_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :dogo, DogoWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "Urb04cZWL8q5c5SUC+BY7CdauBxIT/50jBiASqhQILt1RlY39Z1tXnFYkRY3X0/e",
  server: false

# Oban ne pokrece poslove u testovima; provjeravamo enqueue i perform/1.
config :dogo, Oban, testing: :manual

# Overpass klijent je mockiran Moxom.
config :dogo, :overpass_client, Dogo.OverpassMock

# Geokoder je mockiran Moxom; testovi Nominatim klijenta idu kroz Req.Test.
config :dogo, :geocoder, Dogo.GeocoderMock

config :dogo, :nominatim_req_options,
  plug: {Req.Test, Dogo.Geo.Geocoder.Nominatim},
  retry: false

# Bez cekanja od sekunde po upitu; sam mehanizam se testira izravno.
config :dogo, :nominatim_rate_limiter, interval_ms: 0

# Rutiranje je mockirano Moxom; testovi OSRM klijenta idu kroz Req.Test.
config :dogo, :routing_client, Dogo.RoutingMock

config :dogo, :osrm_req_options, plug: {Req.Test, Dogo.Geo.Routing.OSRM}, retry: false

# Overpass: sav promet ide kroz Req.Test plug, pa testovi nikad ne diraju
# mrežu. Backoff je nula da retry testovi ne traju sekundama.
config :dogo, :overpass_req_options,
  plug: {Req.Test, Dogo.Import.Overpass.HTTP},
  retry_delay: 0,
  max_retries: 3

# In test we don't send emails
config :dogo, Dogo.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
