defmodule Jido.MixProject do
  use Mix.Project

  @version "1.0.0"

  def project do
    [
      app: :jido,
      version: @version,
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      consolidate_protocols: Mix.env() != :test,

      # Docs
      name: "Jido",
      description:
        "A foundational framework for building autonomous, distributed agent systems in Elixir",
      source_url: "https://github.com/agentjido/jido",
      homepage_url: "https://github.com/agentjido/jido",
      package: package(),
      docs: docs(),

      # Coverage
      test_coverage: [
        tool: ExCoveralls,
        summary: [threshold: 90],
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
      source_ref: "v#{@version}",
      source_url: "https://github.com/agentjido/jido",
      extra_section: "Guides",
      extras: [
        {"README.md", title: "Home"},
        {"guides/getting-started.md", title: "Getting Started"},
        {"guides/actions.md", title: "Actions & Workflows"},
        {"guides/agents.md", title: "Agents"},
        {"guides/sensors.md", title: "Sensors"},
        {"guides/bus.md", title: "Signals & Bus"},
        {"guides/instructions.md", title: "Instructions"},
        {"guides/directives.md", title: "Agent Directives"}
      ],
      groups_for_modules: [
        Core: [
          Jido,
          Jido.Agent,
          Jido.Action,
          Jido.Workflow,
          Jido.Signal,
          Jido.Sensor,
          Jido.Discovery,
          Jido.Supervisor,
          Jido.Agent.Server
        ],
        Workflows: [
          Jido.Workflow.Chain,
          Jido.Workflow.Closure,
          Jido.Workflow.Tool
        ],
        Example_Actions: [
          Jido.Action.Directives,
          Jido.Actions.Arithmetic,
          Jido.Actions.Basic,
          Jido.Actions.Files,
          Jido.Actions.Simplebot,
          Jido.Actions.Syscall,
          Jido.Actions.Files.DeleteFile,
          Jido.Actions.Files.ListDirectory,
          Jido.Actions.Files.MakeDirectory,
          Jido.Actions.Files.WriteFile
        ],
        Directives: [
          Jido.Agent.Directive,
          Jido.Agent.Directive.DeregisterActionDirective,
          Jido.Agent.Directive.EnqueueDirective,
          Jido.Agent.Directive.RegisterActionDirective,
          Jido.Agent.Directive.SpawnDirective,
          Jido.Agent.Directive.KillDirective,
          Jido.Agent.Directive.PublishDirective,
          Jido.Agent.Directive.SubscribeDirective,
          Jido.Agent.Directive.UnsubscribeDirective
        ],
        Runner: [
          Jido.Runner,
          Jido.Runner.Chain,
          Jido.Runner.Instruction,
          Jido.Runner.Result,
          Jido.Runner.Simple
        ],
        Utilities: [
          Jido.Util,
          Jido.Error,
          Jido.Agent.Server.State
        ]
      ],
      skip_undefined_reference_warnings_on: [
        Jido.Agent.Server.Execute,
        Jido.Agent.Server.Process,
        Jido.Agent.Server.PubSub,
        Jido.Agent.Server.Signal,
        Jido.Agent.Server.Syscall
      ],
      groups_for_extras: [
        Guides: ~r/guides\/.*md/
      ],
      sidebar_items: [
        Home: "README.md",
        Guides: [
          "Getting Started": "guides/getting-started.md",
          Actions: "guides/actions.md",
          Instructions: "guides/instructions.md",
          Agents: "guides/agents.md",
          "Sensors & Signals": "guides/sensors.md",
          Directives: "guides/directives.md",
          "Signal Router": "guides/signal-router.md",
          Skills: "guides/skills.md"
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
        "GitHub" => "https://github.com/agentjido/jido"
      }
    ]
  end

  defp deps do
    [
      # Jido Deps
      {:backoff, "~> 1.1"},
      {:deep_merge, "~> 1.0"},
      {:elixir_uuid, "~> 1.2"},
      {:jason, "~> 1.4"},
      {:nimble_options, "~> 1.1"},
      {:ok, "~> 2.3"},
      {:phoenix_pubsub, "~> 2.1"},
      {:private, "~> 0.1.2"},
      {:proper_case, "~> 1.3"},
      {:telemetry, "~> 1.3"},
      {:typed_struct, "~> 0.3.0"},

      # Skill & Action Dependencies for examples
      {:abacus, "~> 2.1"},

      # Testing
      {:benchee, "~> 1.3", only: [:dev, :test]},
      {:benchee_html, "~> 1.0", only: [:dev, :test]},
      {:credo, "~> 1.7"},
      {:doctor, "~> 0.22.0", only: [:dev, :test]},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:excoveralls, "~> 0.18.3", only: [:dev, :test]},
      {:ex_dbug, "~> 1.2"},
      {:expublish, "~> 2.7", only: [:dev], runtime: false},
      {:mix_test_watch, "~> 1.0", only: [:dev, :test], runtime: false},
      {:mimic, "~> 1.7", only: [:dev, :test]},
      {:mock, "~> 0.3.8", only: [:dev, :test]},
      {:stream_data, "~> 1.1", only: [:dev, :test]}
    ]
  end

  defp aliases do
    [
      test: "test --trace",

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
