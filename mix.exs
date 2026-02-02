defmodule Jido.MixProject do
  use Mix.Project

  @version "2.0.0-rc.2"

  def vsn do
    @version
  end

  def project do
    [
      app: :jido,
      version: @version,
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),

      # Docs
      name: "Jido",
      description:
        "Pure functional agents and OTP runtime for building autonomous multi-agent workflows in Elixir.",
      source_url: "https://github.com/agentjido/jido",
      homepage_url: "https://github.com/agentjido/jido",
      package: package(),
      docs: docs(),

      # Coverage
      test_coverage: [
        tool: ExCoveralls,
        summary: [threshold: 80],
        export: "cov",
        ignore_modules: [~r/^JidoTest\./]
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Jido.Application, []}
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.github": :test,
        "coveralls.lcov": :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.cobertura": :test
      ]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp docs do
    [
      main: "readme",
      api_reference: false,
      source_ref: "v#{@version}",
      source_url: "https://github.com/agentjido/jido",
      authors: ["Mike Hostetler <mike.hostetler@gmail.com>"],
      groups_for_extras: [
        "Start Here": [
          "guides/getting-started.livemd",
          "guides/core-loop.md",
          "guides/your-first-skill.md",
          "guides/your-first-sensor.md",
          "guides/observability-intro.md"
        ],
        Fundamentals: [
          "guides/agents.md",
          "guides/actions.md",
          "guides/signals.md",
          "guides/directives.md",
          "guides/state-ops.md",
          "guides/skills.md",
          "guides/strategies.md",
          "guides/runtime.md"
        ],
        Coordination: [
          "guides/await.md",
          "guides/orchestration.md"
        ],
        Operations: [
          "guides/observability.md",
          "guides/testing.md",
          "guides/configuration.md",
          "guides/persistence.md",
          "guides/storage.md",
          "guides/worker-pools.md",
          "guides/scheduling.md"
        ],
        Extending: [
          "guides/sensors.md",
          "guides/discovery.md",
          "guides/custom-strategies.md"
        ],
        Integrations: [
          "guides/phoenix-integration.md",
          "guides/ash-integration.md"
        ],
        Advanced: [
          "guides/fsm-strategy.livemd",
          "guides/errors.md"
        ],
        Migration: [
          "guides/migration.md"
        ],
        Project: [
          "CONTRIBUTING.md",
          "CHANGELOG.md",
          "LICENSE"
        ]
      ],
      extras: [
        {"README.md", title: "Home"},

        # Start Here
        {"guides/getting-started.livemd", title: "Quick Start"},
        {"guides/core-loop.md", title: "Core Loop"},
        {"guides/your-first-skill.md", title: "Your First Skill"},
        {"guides/your-first-sensor.md", title: "Your First Sensor"},
        {"guides/observability-intro.md", title: "Seeing What Happened"},

        # Fundamentals
        {"guides/agents.md", title: "Agents"},
        {"guides/actions.md", title: "Actions"},
        {"guides/signals.md", title: "Signals & Routing"},
        {"guides/directives.md", title: "Directives"},
        {"guides/state-ops.md", title: "State Operations"},
        {"guides/skills.md", title: "Skills"},
        {"guides/strategies.md", title: "Strategies"},
        {"guides/runtime.md", title: "Runtime"},

        # Coordination
        {"guides/await.md", title: "Await & Coordination"},
        {"guides/orchestration.md", title: "Multi-Agent Orchestration"},

        # Operations
        {"guides/observability.md", title: "Observability"},
        {"guides/testing.md", title: "Testing"},
        {"guides/configuration.md", title: "Configuration"},
        {"guides/persistence.md", title: "Persistence"},
        {"guides/storage.md", title: "Storage"},
        {"guides/worker-pools.md", title: "Worker Pools"},
        {"guides/scheduling.md", title: "Scheduling"},

        # Extending
        {"guides/sensors.md", title: "Sensors"},
        {"guides/discovery.md", title: "Discovery"},
        {"guides/custom-strategies.md", title: "Custom Strategies"},

        # Integrations
        {"guides/phoenix-integration.md", title: "Phoenix Integration"},
        {"guides/ash-integration.md", title: "Ash Integration"},

        # Advanced
        {"guides/fsm-strategy.livemd", title: "FSM Strategy Deep Dive"},
        {"guides/errors.md", title: "Error Handling"},

        # Migration
        {"guides/migration.md", title: "Migrating from 1.x"},

        # Project
        {"CONTRIBUTING.md", title: "Contributing"},
        {"CHANGELOG.md", title: "Changelog"},
        {"LICENSE", title: "Apache 2.0 License"}
      ],
      extra_section: "Guides",
      formatters: ["html"],
      skip_undefined_reference_warnings_on: [
        "CHANGELOG.md",
        "LICENSE"
      ],
      groups_for_modules: [
        Core: [
          Jido,
          Jido.Agent,
          Jido.AgentServer,
          Jido.Await
        ],
        Strategies: [
          Jido.Agent.Strategy,
          Jido.Agent.Strategy.Direct,
          Jido.Agent.Strategy.FSM,
          Jido.Agent.Strategy.State
        ],
        Skills: [
          Jido.Skill
        ],
        Directives: [
          Jido.Agent.Directive,
          Jido.Agent.Directive.Emit,
          Jido.Agent.Directive.Error,
          Jido.Agent.Directive.Spawn,
          Jido.Agent.Directive.SpawnAgent,
          Jido.Agent.Directive.StopChild,
          Jido.Agent.Directive.Schedule,
          Jido.Agent.Directive.Stop,
          Jido.Agent.Directive.Cron,
          Jido.Agent.Directive.CronCancel
        ],
        "Agent Components": [
          Jido.Agent.State,
          Jido.Agent.Schema,
          Jido.Agent.StateOps,
          Jido.Agent.StateOp,
          Jido.AgentServer.State,
          Jido.AgentServer.Status,
          Jido.AgentServer.Options,
          Jido.AgentServer.ErrorPolicy,
          Jido.AgentServer.SignalRouter
        ],
        "Built-in Actions": [
          Jido.Actions.Control,
          Jido.Actions.Lifecycle,
          Jido.Actions.Scheduling,
          Jido.Actions.Status
        ],
        Observability: [
          Jido.Observe,
          Jido.Observe.Log,
          Jido.Observe.Tracer,
          Jido.Observe.NoopTracer,
          Jido.Observe.SpanCtx,
          Jido.Telemetry
        ],
        Storage: [
          Jido.Storage,
          Jido.Storage.ETS,
          Jido.Storage.File,
          Jido.Persist
        ],
        Utilities: [
          Jido.Discovery,
          Jido.Error,
          Jido.Scheduler,
          Jido.Util,
          Jido.Agent.WorkerPool
        ]
      ]
    ]
  end

  defp package do
    [
      files: ["lib", "mix.exs", "README.md", "LICENSE", "usage-rules.md"],
      maintainers: ["Mike Hostetler"],
      licenses: ["Apache-2.0"],
      links: %{
        "Documentation" => "https://hexdocs.pm/jido",
        "GitHub" => "https://github.com/agentjido/jido",
        "Website" => "https://agentjido.xyz",
        "Discord" => "https://agentjido.xyz/discord",
        "Changelog" => "https://github.com/agentjido/jido/blob/main/CHANGELOG.md"
      }
    ]
  end

  defp deps do
    [
      # Jido Ecosystem
      {:jido_action, "~> 2.0.0-rc.2"},
      {:jido_signal, "~> 2.0.0-rc.2"},

      # Jido Deps
      {:deep_merge, "~> 1.0"},
      {:jason, "~> 1.4"},
      {:nimble_options, "~> 1.1"},
      {:ok, "~> 2.3"},
      {:phoenix_pubsub, "~> 2.1"},
      {:splode, "~> 0.3.0"},
      {:telemetry, "~> 1.3"},
      {:poolboy, "~> 1.5"},
      {:telemetry_metrics, "~> 1.1"},
      {:sched_ex, "~> 1.1"},
      {:uniq, "~> 0.6.1"},

      # Skill & Action Dependencies for examples
      # {:req, "~> 0.5.16"},

      # ReAct example dependency (optional - requires API key)
      # Using GitHub main for upcoming tool call extraction improvements
      # {:req_llm, github: "agentjido/req_llm", branch: "main"},

      # Development & Test Dependencies
      {:git_ops, "~> 2.9", only: :dev, runtime: false},
      {:git_hooks, "~> 0.8", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test]},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.21", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:excoveralls, "~> 0.18.3", only: [:dev, :test]},
      {:expublish, "~> 2.7", only: [:dev], runtime: false},
      {:mix_test_watch, "~> 1.0", only: [:dev, :test], runtime: false},
      {:mock, "~> 0.3.0", only: :test},
      {:mimic, "~> 2.0", only: :test},
      {:stream_data, "~> 1.0", only: [:dev, :test]},

      # Code generation
      {:igniter, "~> 0.7", optional: true}
    ]
  end

  defp aliases do
    [
      # Helper to run tests with trace when needed
      # test: "test --trace --exclude flaky",
      test: "test --exclude flaky",

      # Helper to run docs
      docs: "docs -f html --open",

      # Run to check the quality of your code
      q: ["quality"],
      quality: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "credo --min-priority higher",
        "dialyzer"
      ]
    ]
  end
end
