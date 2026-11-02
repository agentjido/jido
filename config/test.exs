import Config

config :jido, runtime_store_timeout: 100

# Keep normal test output quiet. CaptureLog installs its own handler when needed.
config :logger, :default_handler, false
