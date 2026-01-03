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
log_level =
  System.get_env("LOG_LEVEL", "debug")
  |> String.downcase()
  |> case do
    "debug" -> :debug
    "info" -> :info
    "notice" -> :notice
    "warning" -> :warning
    "error" -> :error
    "critical" -> :critical
    "alert" -> :alert
    "emergency" -> :emergency
    _ -> :debug
  end

config :logger,
  level: log_level,
  handle_otp_reports: false,
  handle_sasl_reports: false

# Disable default console handler (OTP 21+ / Elixir 1.15+)
config :logger, :default_handler, false
