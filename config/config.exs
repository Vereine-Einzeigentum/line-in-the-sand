import Config

# General application configuration
config :line_core,
  ecto_repos: [LineCore.Repo]

# Configures the endpoint
config :line_web, LineWebWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: LineWebWeb.ErrorHTML, json: LineWebWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: LineWeb.PubSub,
  live_view: [signing_salt: "xK7mR2pN"]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
