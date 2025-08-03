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
      ],
      preferred_cli_env: [
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

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Jido.Application, []}
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
          "guides/getting-started.livemd"
        ],
        "About Jido": [
          "guides/about/what-is-jido.md",
          "guides/about/design-principles.md",
          "guides/about/do-you-need-an-agent.md",
          "guides/about/where-is-the-AI.md",
          "guides/about/alternatives.md",
          "CONTRIBUTING.md",
          "CHANGELOG.md",
          "LICENSE.md"
        ],
        Examples: [
          "guides/examples/your-first-agent.livemd",
          "guides/examples/tool-use.livemd",
          "guides/examples/chain-of-thought.livemd",
          "guides/examples/think-plan-act.livemd",
          "guides/examples/multi-agent.livemd"
        ],
        Actions: [
          "guides/actions/overview.md",
          "guides/actions/workflows.md",
          "guides/actions/instructions.md",
          "guides/actions/directives.md",
          "guides/actions/runners.md",
          "guides/actions/actions-as-tools.md",
          "guides/actions/testing.md"
        ],
        Sensors: [
          "guides/sensors/overview.md",
          "guides/sensors/cron-heartbeat.md"
        ],
        Agents: [
          "guides/agents/overview.md",
          "guides/agents/stateless.md",
          "guides/agents/stateful.md",
          "guides/agents/directives.md",
          "guides/agents/runtime.md",
          "guides/agents/output.md",
          "guides/agents/routing.md",
          "guides/agents/sensors.md",
          "guides/agents/callbacks.md",
          "guides/agents/child-processes.md"
        ],
        Skills: [
          "guides/skills/overview.md",
          "guides/skills/testing.md"
        ]
      ],
      extras: [
        # Home & Project
        {"README.md", title: "Home"},

        # Getting Started Section
        {"guides/getting-started.livemd", title: "Quick Start"},

        # About Jido
        {"guides/about/what-is-jido.md", title: "What is Jido?"},
        {"guides/about/design-principles.md", title: "Design Principles"},
        {"guides/about/do-you-need-an-agent.md", title: "Do You Need an Agent?"},
        {"guides/about/where-is-the-AI.md", title: "Where is the AI?"},
        {"guides/about/alternatives.md", title: "Alternatives"},
        {"CONTRIBUTING.md", title: "Contributing"},
        {"CHANGELOG.md", title: "Changelog"},
        {"LICENSE.md", title: "Apache 2.0 License"},

        # Examples
        {"guides/examples/hello-world.livemd", title: "Hello World"},
        {"guides/examples/tool-use.livemd", title: "Agents with Tools"},
        {"guides/examples/think-plan-act.livemd", title: "Think-Plan-Act"},
        {"guides/examples/chain-of-thought.livemd", title: "Chain of Thought"},
        {"guides/examples/multi-agent.livemd", title: "Multi-Agent Systems"},

        # Actions
        {"guides/actions/overview.md", title: "Overview"},
        {"guides/actions/workflows.md", title: "Executing Actions"},
        {"guides/actions/instructions.md", title: "Instructions"},
        {"guides/actions/directives.md", title: "Directives"},
        {"guides/actions/runners.md", title: "Runners"},
        {"guides/actions/actions-as-tools.md", title: "Actions as LLM Tools"},
        {"guides/actions/testing.md", title: "Testing"},

        # Sensors
        {"guides/sensors/overview.md", title: "Overview"},
        {"guides/sensors/cron-heartbeat.md", title: "Cron & Heartbeat"},

        # Agents
        {"guides/agents/overview.md", title: "Overview"},
        {"guides/agents/stateless.md", title: "Stateless Agents"},
        {"guides/agents/stateful.md", title: "Stateful Agents"},
        {"guides/agents/directives.md", title: "Directives"},
        {"guides/agents/runtime.md", title: "Runtime"},
        {"guides/agents/output.md", title: "Output"},
        {"guides/agents/routing.md", title: "Routing"},
        {"guides/agents/sensors.md", title: "Sensors"},
        {"guides/agents/callbacks.md", title: "Callbacks"},
        {"guides/agents/child-processes.md", title: "Child Processes"},

        # Skills
        {"guides/skills/overview.md", title: "Overview"},
        {"guides/skills/testing.md", title: "Testing Skills"}
      ],
      extra_section: "Guides",
      formatters: ["html"],
      skip_undefined_reference_warnings_on: [
        "CHANGELOG.md",
        "LICENSE.md"
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
      files: ["lib", "mix.exs", "README.md", "LICENSE.md"],
      maintainers: ["Mike Hostetler"],
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => "https://github.com/agentjido/jido",
        "Agent Workbench" => "https://github.com/agentjido/jido_workbench"
      }
    ]
  end

  defp deps do
    [
      # Jido Ecosystem
      {:jido_action, github: "agentjido/jido_action"},
      {:jido_signal, github: "agentjido/jido_signal"},

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
      {:telemetry_metrics, "~> 1.1"},
      {:typed_struct, "~> 0.3.0"},
      {:typed_struct_nimble_options, "~> 0.1.1"},
      {:quantum, "~> 3.5"},
      {:uniq, "~> 0.6.1"},
      {:ex_dbug, "~> 2.1"},

      # Skill & Action Dependencies for examples
      {:abacus, "~> 2.1"},
      {:req, "~> 0.5.10"},

      # Development & Test Dependencies
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
        "format",
        "format --check-formatted",
        "compile --warnings-as-errors",
        "dialyzer --format dialyxir",
        "credo --all"
      ]
    ]
  end
end
