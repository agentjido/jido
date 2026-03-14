import Config

config :jido, default: Jido.DefaultInstance

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
  config :git_hooks,
    auto_install: true,
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

# Import environment specific config (test.exs only)
if config_env() == :test do
  import_config "test.exs"
end
