import Config

# Configure your database
config :line_core, LineCore.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "line_in_the_sand_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

# For development, we disable any cache and enable
# debugging and code reloading.
config :line_web, LineWebWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base:
    "dGhpcyBpcyBhIGRldmVsb3BtZW50IHNlY3JldCBrZXkgYmFzZSB0aGF0IHNob3VsZCBiZSBjaGFuZ2Vk",
  watchers: []

# Enable dev routes for dashboard and mailbox
config :line_web, dev_routes: true

# Do not include metadata nor timestamps in development logs
config :logger, :console, format: "[$level] $message\n"

# Set a higher stacktrace during development. Avoid configuring such
# in production as building large stacktraces may be expensive.
config :phoenix, :stacktrace_depth, 20

# Initialize plugs at runtime for faster development compilation
config :phoenix, :plug_init_mode, :runtime
