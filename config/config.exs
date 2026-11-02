import Config

if config_env() in [:dev, :test] do
  config :covenant,
    root: ".",
    contracts_dir: "test/contracts",
    test_paths: ["test"]
end

if config_env() == :test do
  import_config "test.exs"
end
