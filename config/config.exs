import Config

if config_env() in [:dev, :test] do
  config :covenant,
    root: ".",
    contracts_dir: "test/contracts",
    test_paths: ["test"]
end

if config_env() == :test do
  config :jido, runtime_store_timeout: 100

  # Keep normal test output quiet. CaptureLog installs its own handler when needed.
  config :logger, :default_handler, false
end
