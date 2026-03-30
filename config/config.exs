import Config

config :jido, default: Jido.DefaultInstance

# Use time_zone_info as the default time zone database (replaces tzdata)
config :jido, :time_zone_database, TimeZoneInfo.TimeZoneDatabase

# Logger configuration for Jido telemetry metadata
# These metadata keys are used by Jido.Telemetry for structured logging
config :logger, :default_formatter,
  format: "[$level] $message $metadata\n",
  metadata: [
    :agent_id,
    :agent_module,
    :action,
    :directive_count,
    :directive_type,
    :duration_μs,
    :error,
    :instruction_count,
    :queue_size,
    :result,
    :signal_type,
    :span_id,
    :stacktrace,
    :trace_id,
    :strategy
  ]

# Git hooks and git_ops configuration for conventional commits
# Only enabled in dev environment (git_ops is a dev-only dependency)
if config_env() == :dev do
  # Worktrees use a `.git` file instead of a directory. We keep the explicit
  # project path for git_hooks and only auto-install hooks from a normal checkout.
  project_path = Path.expand("..", __DIR__)
  auto_install_git_hooks? = File.dir?(Path.join(project_path, ".git"))

  config :git_hooks,
    auto_install: auto_install_git_hooks?,
    project_path: project_path,
    verbose: true,
    hooks: [
      commit_msg: [
        tasks: [
          {:cmd, "mix git_ops.check_message", include_hook_args: true}
        ]
      ]
    ]

  config :git_ops,
    mix_project: Jido.MixProject,
    changelog_file: "CHANGELOG.md",
    repository_url: "https://github.com/agentjido/jido",
    manage_mix_version?: true,
    manage_readme_version: "README.md",
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

# Import environment-specific overrides only for the environments that define them.
if config_env() in [:prod, :test] do
  import_config "#{config_env()}.exs"
end
