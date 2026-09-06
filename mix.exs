defmodule Jido.MixProject do
  use Mix.Project

  @version "2.3.3"

  def vsn do
    @version
  end

  def project do
    [
      app: :jido,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),

      # Docs
      name: "Jido",
      description:
        "An autonomous agent framework for Elixir, built for workflows and multi-agent systems.",
      source_url: "https://github.com/agentjido/jido",
      homepage_url: "https://github.com/agentjido/jido",
      package: package(),
      docs: docs(),

      # Coverage
      test_coverage: [
        tool: ExCoveralls,
        # ExCoveralls applies the core-only 90% gate from coveralls.json.
        summary: [threshold: 90],
        export: "cov"
      ],

      # Dialyzer
      dialyzer: [
        plt_add_apps: [:mix]
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:crypto, :logger],
      mod: {Jido.Application, []}
    ]
  end

  def cli do
    [
      preferred_envs: [
        examples: :test,
        coveralls: :test,
        "coveralls.github": :test,
        "coveralls.lcov": :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.json": :test,
        "coveralls.cobertura": :test
      ]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "examples", "test/support"]
  defp elixirc_paths(:dev), do: ["lib", "examples"]
  defp elixirc_paths(_), do: ["lib"]

  defp docs do
    [
      main: "readme",
      api_reference: false,
      filter_modules: fn module, _metadata ->
        not String.starts_with?(Atom.to_string(module), "Elixir.Jido.Examples.")
      end,
      source_ref: "v#{@version}",
      source_url: "https://github.com/agentjido/jido",
      authors: ["Mike Hostetler <mike.hostetler@gmail.com>"],
      groups_for_extras: [
        Project: ["LICENSE"]
      ],
      extras: [
        {"README.md", title: "Home"},
        {"guides/core-scope.md", title: "Core scope"},
        {"guides/migration.md", title: "V2 migration"},
        {"guides/agents.md", title: "Agent values"},
        {"guides/core-loop.md", title: "Command and commit"},
        {"guides/runtime.md", title: "Runtime controls"},
        {"guides/plugins.md", title: "Plugins"},
        {"guides/storage.md", title: "Persistence"},
        {"guides/benchmarks.md", title: "Core benchmarks"},
        {"LICENSE", title: "Apache 2.0 License"}
      ],
      extra_section: "Guides",
      formatters: ["html", "markdown"],
      skip_undefined_reference_warnings_on: ["LICENSE"],
      groups_for_modules: [
        Core: [
          Jido,
          Jido.Agent,
          Jido.Agent.StateBudget,
          Jido.Topology,
          Jido.AgentServer,
          Jido.Agent.Directive
        ],
        "Agent Authoring": [
          Jido.Agent.Builder,
          Jido.Agent.Codec,
          Jido.Agent.Codec.Registry,
          Jido.Plugin.Codec
        ],
        "Agent Data": [
          Jido.Agent.Command,
          Jido.Agent.Turn,
          Jido.AgentServer.ChildInfo,
          Jido.AgentServer.DirectiveContext,
          Jido.AgentServer.Options,
          Jido.AgentServer.ParentRef,
          Jido.AgentServer.Signal.ChildExit,
          Jido.AgentServer.Signal.ChildStarted,
          Jido.AgentServer.Signal.Orphaned
        ],
        "Agent Plugins": [
          Jido.Plugin,
          Jido.Plugin.DirectiveContext,
          Jido.Plugin.Init,
          Jido.Plugin.SignalContext,
          Jido.Plugin.Audit,
          Jido.Plugin.Audit.Record,
          Jido.Plugin.Bus,
          Jido.Plugin.Bus.Client,
          Jido.Plugin.Bus.Manager,
          Jido.Plugin.Dispatch,
          Jido.Plugin.Dispatch.Send,
          Jido.Plugin.Heartbeat,
          Jido.Plugin.Scheduler,
          Jido.Plugin.Scheduler.Acknowledge,
          Jido.Plugin.Scheduler.Cancel,
          Jido.Plugin.Scheduler.Cron,
          Jido.Plugin.Scheduler.Enqueue,
          Jido.Plugin.Scheduler.Occurrence,
          Jido.Plugin.Scheduler.Schedule,
          Jido.Plugin.SensorManager,
          Jido.Plugin.SensorManager.Init,
          Jido.Plugin.SensorManager.Start,
          Jido.Plugin.SensorManager.Stop
        ],
        "Domain Data": [
          Jido.Thread,
          Jido.Thread.Entry,
          Jido.Thread.EntryNormalizer
        ],
        Persistence: [
          Jido.Persistence,
          Jido.Persistence.Adapter,
          Jido.Persistence.ETS,
          Jido.Persistence.File,
          Jido.Persistence.Redis
        ],
        Observability: [
          Jido.Observe,
          Jido.Observe.Config,
          Jido.Observe.Log,
          Jido.Observe.Tracer,
          Jido.Observe.NoopTracer,
          Jido.Observe.SpanCtx,
          Jido.Debug,
          Jido.Telemetry,
          Jido.Telemetry.Formatter,
          Jido.Tracing.Context,
          Jido.Tracing.Trace
        ],
        Utilities: [
          Jido.Error,
          Jido.ID,
          Jido.Util
        ],
        Exceptions: [
          Jido.Error.CompensationError,
          Jido.Error.ExecutionError,
          Jido.Error.InternalError,
          Jido.Error.RoutingError,
          Jido.Error.TimeoutError,
          Jido.Error.ValidationError
        ]
      ]
    ]
  end

  defp package do
    [
      files: [
        "lib/jido",
        "lib/jido.ex",
        "mix.exs",
        ".formatter.exs",
        "README.md",
        "usage-rules.md",
        "guides",
        "LICENSE"
      ],
      maintainers: ["Mike Hostetler"],
      licenses: ["Apache-2.0"],
      links: %{
        "Documentation" => "https://hexdocs.pm/jido",
        "GitHub" => "https://github.com/agentjido/jido",
        "Website" => "https://jido.run",
        "Discord" => "https://jido.run/discord",
        "Changelog" => "https://github.com/agentjido/jido/blob/main/CHANGELOG.md"
      }
    ]
  end

  defp deps do
    [
      # Jido Ecosystem
      {:jido_action, "~> 3.0.0-beta.7"},
      {:jido_signal, "~> 3.0.0-beta.4"},

      # Jido Deps
      {:spark, "~> 2.7"},
      {:splode, "~> 0.3.0"},
      {:telemetry, "~> 1.3"},
      {:telemetry_metrics, "~> 1.2"},
      {:sched_ex, "~> 1.2.1"},

      # Development & Test Dependencies
      {:req_llm, "~> 1.21", only: [:dev, :test]},
      {:dotenvy, "~> 1.1", only: [:dev, :test]},
      {:git_ops, "~> 2.9", only: :dev, runtime: false},
      {:git_hooks, "~> 0.8", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test]},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.21", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:excoveralls, "~> 0.18.3", only: [:dev, :test]},
      {:mix_test_watch, "~> 1.0", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      # Default exclusions are declared once in test/test_helper.exs.
      test: "test --preload-modules",

      # Run the opt-in agent example suite
      examples: "test --only example",

      # Helper to run docs
      docs: "docs --open",

      # Run to check the quality of your code
      q: ["quality"],
      quality: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "credo --strict --only warning",
        "dialyzer"
      ]
    ]
  end
end
