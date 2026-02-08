import Config

# Keep Logger enabled but silent by default in tests.
# This allows ExUnit.CaptureLog to work while keeping test output clean.
#
# - :default_handler, false disables the default console handler
# - handle_otp_reports: false suppresses GenServer crash reports
# - handle_sasl_reports: false suppresses supervisor reports
#
# To enable verbose logging during debugging, set LOG_LEVEL env var:
#   LOG_LEVEL=debug mix test test/my_test.exs
#
log_level = System.get_env("LOG_LEVEL", "debug") |> String.to_existing_atom()

config :logger,
  level: log_level,
  handle_otp_reports: false,
  handle_sasl_reports: false

# Keep error-path tests fast unless they explicitly opt into retries.
config :jido_action,
  default_max_retries: 0,
  default_backoff: 0

# Disable default console handler (OTP 21+ / Elixir 1.15+)
config :logger, :default_handler, false
