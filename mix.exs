defmodule Jido.MixProject do
  use Mix.Project

  @version "1.2.0"

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
      description: "A toolkit for building autonomous, distributed agent systems in Elixir",
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
  defp elixirc_paths(:test), do: ["lib", "test/support", "test/jido/bus/support"]
  defp elixirc_paths(:dev), do: ["lib", "bench"]
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
          "guides/core-concepts.md"
        ],
        Guides: [
          "guides/agents.md",
          "guides/skills.md",
          "guides/directives.md",
          "guides/strategies.md",
          "guides/runtime.md",
          "guides/testing.md"
        ],
        "Deep Dives": [
          "guides/fsm-strategy.livemd"
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
        # Home & Project
        {"README.md", title: "Home"},

        # Start Here
        {"guides/getting-started.livemd", title: "Quick Start"},
        {"guides/core-concepts.md", title: "Core Concepts"},

        # Guides
        {"guides/agents.md", title: "Agents"},
        {"guides/skills.md", title: "Skills"},
        {"guides/directives.md", title: "Directives"},
        {"guides/strategies.md", title: "Strategies"},
        {"guides/runtime.md", title: "Runtime"},
        {"guides/testing.md", title: "Testing"},

        # Deep Dives
        {"guides/fsm-strategy.livemd", title: "FSM Strategy Deep Dive"},

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
          Jido.Action,
          Jido.Agent,
          Jido.Agent.Server,
          Jido.Instruction,
          Jido.Sensor,
          Jido.Workflow
        ],
        "Actions: Directives": [
          Jido.Agent.Directive,
          Jido.Agent.Directive.Enqueue,
          Jido.Agent.Directive.RegisterAction,
          Jido.Agent.Directive.DeregisterAction,
          Jido.Agent.Directive.Kill,
          Jido.Agent.Directive.Spawn,
          Jido.Actions.Directives
        ],
        Skills: [
          Jido.Skill,
          Jido.Skills.Arithmetic
        ],
        Examples: [
          Jido.Actions.Arithmetic,
          Jido.Tools.Basic,
          Jido.Actions.Files,
          Jido.Actions.Simplebot,
          Jido.Sensors.Cron,
          Jido.Sensors.Heartbeat
        ],
        Utilities: [
          Jido.Discovery,
          Jido.Error,
          Jido.Scheduler,
          Jido.Supervisor,
          Jido.Agent.Server.State,
          Jido.Util
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
      {:jido_action, github: "agentjido/jido_action", branch: "main"},
      {:jido_signal, github: "agentjido/jido_signal", branch: "main"},
      # {:jido_signal, path: "../jido_signal"},

      # Jido Deps
      {:backoff, "~> 1.1"},
      {:deep_merge, "~> 1.0"},
      {:jason, "~> 1.4"},
      {:msgpax, "~> 2.3"},
      {:nimble_options, "~> 1.1"},
      {:nimble_parsec, "~> 1.4"},
      {:ok, "~> 2.3"},
      {:phoenix_pubsub, "~> 2.1"},
      {:private, "~> 0.1.2"},
      {:proper_case, "~> 1.3"},
      {:splode, "~> 0.2.5"},
      {:telemetry, "~> 1.3"},
      {:poolboy, "~> 1.5"},
      {:telemetry_metrics, "~> 1.1"},
      {:typed_struct, "~> 0.3.0"},
      {:typed_struct_nimble_options, "~> 0.1.1"},
      {:sched_ex, "~> 1.1"},
      {:uniq, "~> 0.6.1"},
      # State Machine
      {:fsmx, "~> 0.5"},

      # Skill & Action Dependencies for examples
      {:req, "~> 0.5.16"},

      # ReAct example dependency (optional - requires API key)
      # Using GitHub main for upcoming tool call extraction improvements
      {:req_llm, github: "agentjido/req_llm", branch: "main", optional: true, override: true},

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
      {:stream_data, "~> 1.0", only: [:dev, :test]}
    ]
  end

  defp aliases do
    [
      # Helper to run tests with trace when needed
      # test: "test --trace --exclude flaky",
      test: "test --exclude flaky",

      # Helper to run docs
      # docs: "docs -f html --open",

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
