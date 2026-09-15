import Config

config :git_hooks, auto_install: false
config :jido, runtime_store_timeout: 100

# Keep test output quiet. ExUnit.CaptureLog installs its own handler when needed.
config :logger, :default_handler, false
