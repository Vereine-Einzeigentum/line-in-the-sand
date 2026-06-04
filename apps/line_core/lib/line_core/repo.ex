defmodule LineCore.Repo do
  use Ecto.Repo,
    otp_app: :line_core,
    adapter: Ecto.Adapters.Postgres
end
