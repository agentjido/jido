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

if config_env() == :dev do
  config :git_ops,
    no_igniter?: true,
    mix_project: Jido.MixProject,
    changelog_file: "CHANGELOG.md",
    repository_url: "https://github.com/agentjido/jido",
    manage_mix_version?: true,
    version_tag_prefix: "v",
    types: [
      feat: [header: "Features"],
      fix: [header: "Bug Fixes"],
      perf: [header: "Performance"],
      refactor: [header: "Refactoring"],
      docs: [hidden?: true],
      test: [hidden?: true],
      chore: [hidden?: true],
      ci: [hidden?: true]
    ]
end
