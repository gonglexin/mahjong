defmodule Mahjong.Repo do
  use Ecto.Repo,
    otp_app: :mahjong,
    adapter: Ecto.Adapters.Postgres
end
