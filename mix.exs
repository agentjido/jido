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
          Jido.Action,
          Jido.Agent,
          Jido.Agent.Server,
          Jido.Discovery,
          Jido.Instruction,
          Jido.Sensor,
          Jido.Signal,
          Jido.Supervisor,
          Jido.Workflow
        ],
        "Agent Server": [
          Jido.Agent.Server.Callback,
          Jido.Agent.Server.Options,
          Jido.Agent.Server.Output,
          Jido.Agent.Server.Process,
          Jido.Agent.Server.Router,
          Jido.Agent.Server.Runtime,
          Jido.Agent.Server.Signal,
          Jido.Agent.Server.Skills,
          Jido.Agent.ServerSensors
        ],
        Bus: [
          Jido.Bus,
          Jido.Bus.Adapter,
          Jido.Bus.Adapters.InMemory,
          Jido.Bus.Adapters.PubSub,
          Jido.Bus.RecordedSignal,
          Jido.Bus.Snapshot
        ],
        "Signal Dispatch": [
          Jido.Signal.Dispatch,
          Jido.Signal.Dispatch.Adapter,
          Jido.Signal.Dispatch.Bus,
          Jido.Signal.Dispatch.ConsoleAdapter,
          Jido.Signal.Dispatch.LoggerAdapter,
          Jido.Signal.Dispatch.Named,
          Jido.Signal.Dispatch.NoopAdapter,
          Jido.Signal.Dispatch.PidAdapter,
          Jido.Signal.Dispatch.PubSub
        ],
        "Signal Router": [
          Jido.Signal.Router,
          Jido.Signal.Router.HandlerInfo,
          Jido.Signal.Router.NodeHandlers,
          Jido.Signal.Router.PatternMatch,
          Jido.Signal.Router.Route,
          Jido.Signal.Router.Router,
          Jido.Signal.Router.TrieNode,
          Jido.Signal.Router.WildcardHandlers
        ],
        Skills: [
          Jido.Skill,
          Jido.Skills.Arithmetic,
          Jido.Skills.Arithmetic.Actions,
          Jido.Skills.Arithmetic.Actions.Add,
          Jido.Skills.Arithmetic.Actions.Divide,
          Jido.Skills.Arithmetic.Actions.Eval,
          Jido.Skills.Arithmetic.Actions.Multiply,
          Jido.Skills.Arithmetic.Actions.Square,
          Jido.Skills.Arithmetic.Actions.Subtract
        ],
        Workflows: [
          Jido.Workflow.Chain,
          Jido.Workflow.Closure,
          Jido.Workflow.Tool
        ],
        "Example Actions": [
          Jido.Actions.Arithmetic,
          Jido.Actions.Basic,
          Jido.Actions.Directives,
          Jido.Actions.Files,
          Jido.Actions.Files.DeleteFile,
          Jido.Actions.Files.ListDirectory,
          Jido.Actions.Files.MakeDirectory,
          Jido.Actions.Files.WriteFile,
          Jido.Actions.Simplebot
        ],
        Directives: [
          Jido.Agent.Directive,
          Jido.Agent.Directive.DeregisterAction,
          Jido.Agent.Directive.Enqueue,
          Jido.Agent.Directive.Kill,
          Jido.Agent.Directive.RegisterAction,
          Jido.Agent.Directive.Spawn
        ],
        Runner: [
          Jido.Runner,
          Jido.Runner.Chain,
          Jido.Runner.Simple
        ],
        Sensors: [
          Jido.CronSensor,
          Jido.HeartbeatSensor
        ],
        Serialization: [
          Jido.Serialization.JsonDecoder,
          Jido.Serialization.JsonSerializer,
          Jido.Serialization.ModuleNameTypeProvider,
          Jido.Serialization.TypeProvider
        ],
        Utilities: [
          Jido.Error,
          Jido.Scheduler,
          Jido.Util
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
        "Start Here": [
          "Getting Started": "guides/getting-started.md",
          Actions: "guides/actions.md",
          Instructions: "guides/instructions.md",
          Agents: "guides/agents.md",
          "Sensors & Signals": "guides/sensors.md",
          Directives: "guides/directives.md",
          "Signal Router": "guides/signal-router.md",
          Skills: "guides/skills.md",
          Glossary: "guides/glossary.md"
        ],
        "About Jido": [
          "Why Jido?": "guides/why-jido.md",
          "Design Principles": "guides/design-principles.md",
          Alternatives: "guides/alternatives.md"
        ],
        Memory: [
          Memory: "guides/memory.md",
          "Memory Stores": "guides/memory-stores.md"
        ],
        Chat: [
          Chat: "guides/chat.md",
          "Chat History": "guides/chat-history.md"
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
      {:nimble_parsec, "~> 1.4"},
      {:ok, "~> 2.3"},
      {:phoenix_pubsub, "~> 2.1"},
      {:private, "~> 0.1.2"},
      {:proper_case, "~> 1.3"},
      {:telemetry, "~> 1.3"},
      {:typed_struct, "~> 0.3.0"},
      {:typed_struct_nimble_options, "~> 0.1.1"},
      {:quantum, "~> 3.5"},
      # {:ex_dbug, "~> 2.0"},
      {:ex_dbug, "~> 1.2"},
      # Skill & Action Dependencies for examples
      {:abacus, "~> 2.1"},

      # Ai
      {:ecto, "~> 3.12"},
      # Hex does not yet have a release of `instructor` that supports the `Instructor.Adapters.Anthropic` adapter.
      {:instructor, github: "thmsmlr/instructor_ex", branch: "main"},
      {:langchain, "~> 0.3.0-rc.1"},
      {:ex_json_schema, "~> 0.10.0"},

      # Development & Test Dependencies
      {:benchee, "~> 1.0", only: [:dev, :test]},
      {:benchee_html, "~> 1.0", only: [:dev, :test]},
      {:credo, "~> 1.7"},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.21", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:excoveralls, "~> 0.18.3", only: [:dev, :test]},
      {:expublish, "~> 2.7", only: [:dev], runtime: false},
      {:mix_test_watch, "~> 1.0", only: [:dev, :test], runtime: false},
      {:mock, "~> 0.3.0", only: :test},
      {:mimic, "~> 1.11", only: :test},
      {:stream_data, "~> 1.0", only: [:dev, :test]}
    ]
  end

  defp aliases do
    [
      # test: "test --trace",

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
