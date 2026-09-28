# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :dogo,
  ecto_repos: [Dogo.Repo],
  generators: [timestamp_type: :utc_datetime]

# PostGIS: teach Postgrex to encode/decode geometry columns as Geo structs.
config :dogo, Dogo.Repo, types: Dogo.PostgrexTypes

# Oban: uvoz plaza je jedini posao zasad, i namjerno ide u jednom radniku
# kako se ne bi paralelno gadao Overpass.
config :dogo, Oban,
  repo: Dogo.Repo,
  queues: [imports: 1],
  plugins: [{Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7}]

# Korisnikova lokacija ne smije zavrsiti u logovima (E4-S1). LiveView logger
# propusta parametre kroz Phoenix.Logger.filter_values/1, pa je dovoljno da
# hook salje koordinate ugnijezdene pod kljucem "location".
config :phoenix, :filter_parameters, ["password", "location"]

# Jezici. Zadani je hrvatski, jer je publika prvenstveno domaca i turisti u
# Hrvatskoj; njemacki je tu jer je najveci dio gostiju na Jadranu iz njemackog
# govornog podrucja.
#
# msgid-evi su na engleskom, ne na hrvatskom: to je konvencija u Gettextu i
# cini kod citljivim recenzentu koji ne govori hrvatski. Posljedica je da
# engleski ne treba prijevode — msgid *jest* engleski tekst.
config :dogo, DogoWeb.Gettext, default_locale: "hr", locales: ~w(hr en de)

# Pozadinske karte. OpenFreeMap ne trazi API kljuc; provider se mijenja
# varijablom okoline, sto je mitigacija za rizik "tile provider ukine free tier".
config :dogo, :map_style_url, "https://tiles.openfreemap.org/styles/liberty"

# Configure the endpoint
config :dogo, DogoWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: DogoWeb.ErrorHTML, json: DogoWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Dogo.PubSub,
  live_view: [signing_salt: "mIDnBCj1"]

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :dogo, Dogo.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  dogo: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  dogo: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
