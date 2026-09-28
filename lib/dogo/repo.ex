defmodule Dogo.Repo do
  use Ecto.Repo,
    otp_app: :dogo,
    adapter: Ecto.Adapters.Postgres
end
