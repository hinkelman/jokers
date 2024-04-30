defmodule Jokers.Repo do
  use Ecto.Repo,
    otp_app: :jokers,
    adapter: Ecto.Adapters.Postgres
end
