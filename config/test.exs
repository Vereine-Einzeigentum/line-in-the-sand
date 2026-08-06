import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environments.
config :line_core, LineCore.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "line_in_the_sand_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :line_web, LineWebWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "dGVzdCBzZWNyZXQga2V5IGJhc2UgZm9yIHRlc3RpbmcgcHVycG9zZXMgb25seQ==aabbcc",
  server: false

# Swoosh: no-op in tests
config :line_web, LineWeb.Mailer, adapter: Swoosh.Adapters.Test

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime
