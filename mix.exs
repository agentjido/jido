defmodule Jido.MixProject do
  use Mix.Project

  @version "3.0.0-beta.1"
  @description "An actor and agent framework for Elixir"

  # This is the source of truth for the v3 guide set. ExDoc adds a guide after
  # its file exists. This lets us review the complete contents before we write
  # the guide text.
  #
  # The Action and Signal boundary guides will link to the Jido Action and
  # Jido Signal documentation.
  @guide_toc [
    {"Start Here",
     [
       {"guides/v3/getting-started.livemd", "Getting Started"},
       {"guides/v3/build-your-first-agent.livemd", "Build Your First Agent"},
       {"guides/v3/actor-and-agent-framework.md", "Actors, Agents, And Jido"}
     ]},
    {"Core Contracts",
     [
       {"guides/v3/agent-definitions-and-instances.md", "Agent Definitions And Instances"},
       {"guides/v3/signals-commands-and-routes.md", "Signals, Commands, And Routes"},
       {"guides/v3/actions-flows-and-instructions.md", "Actions, Flows, And Instructions"},
       {"guides/v3/turns-commit-and-effects.md", "Turns, Commit, And Effects"},
       {"guides/v3/directives-and-outcomes.md", "Directives And Outcomes"},
       {"guides/v3/errors-and-runtime-guarantees.md", "Errors And Runtime Guarantees"}
     ]},
    {"Author Agents",
     [
       {"guides/v3/agent-dsl.livemd", "Agent DSL"},
       {"guides/v3/state-schemas.livemd", "State Schemas"},
       {"guides/v3/route-interfaces.livemd", "Route Interfaces"},
       {"guides/v3/plugin-state.md", "Plugin-Owned State"},
       {"guides/v3/builders-and-codecs.md", "Builders And Codecs"},
       {"guides/v3/authoring-extensions.md", "Authoring Extensions"}
     ]},
    {"Run Actors",
     [
       {"guides/v3/jido-instances.livemd", "Jido Instances"},
       {"guides/v3/start-and-address-agents.livemd", "Start And Address Agents"},
       {"guides/v3/agent-server-lifecycle.md", "Agent Server Lifecycle"},
       {"guides/v3/calls-casts-and-requests.livemd", "Calls, Casts, And Requests"},
       {"guides/v3/admission-cancellation-and-timeouts.md",
        "Admission, Cancellation, And Timeouts"},
       {"guides/v3/runtime-state-and-debugging.livemd", "Runtime State And Debugging"}
     ]},
    {"Add Capabilities",
     [
       {"guides/v3/plugin-contract-and-lifecycle.md", "Plugin Contract And Lifecycle"},
       {"guides/v3/plugin-runtimes.livemd", "Plugin Runtimes"},
       {"guides/v3/jido-signal-messaging.md", "Use Jido Signal"},
       {"guides/v3/signal-buses.livemd", "Connect A Signal Bus"},
       {"guides/v3/signal-dispatch.livemd", "Dispatch Signals"},
       {"guides/v3/schedules-and-heartbeats.livemd", "Schedules And Heartbeats"},
       {"guides/v3/durable-schedule-occurrences.md", "Durable Schedule Occurrences"},
       {"guides/v3/managed-sensors.livemd", "Manage Sensors"}
     ]},
    {"Compose Systems",
     [
       {"guides/v3/child-agents.livemd", "Start Child Agents"},
       {"guides/v3/ownership-orphans-and-remote-children.md",
        "Ownership, Orphans, And Remote Children"},
       {"guides/v3/topology-definitions.md", "Topology Definitions"},
       {"guides/v3/topology-dsl.livemd", "Topology DSL"},
       {"guides/v3/topology-builders-codecs-and-composition.md",
        "Topology Builders, Codecs, And Composition"},
       {"guides/v3/activate-and-repair-a-topology.livemd", "Activate And Repair A Topology"}
     ]},
    {"Persist And Recover",
     [
       {"guides/v3/portable-state-and-checkpoints.md", "Portable State And Checkpoints"},
       {"guides/v3/persistence-adapters.livemd", "Persistence Adapters"},
       {"guides/v3/compare-and-swap-hibernate-and-thaw.md",
        "Compare And Swap, Hibernate, And Thaw"},
       {"guides/v3/recoverable-effects.md", "Recoverable Effects"},
       {"guides/v3/runtime-coordination-state.md", "Runtime Coordination State"},
       {"guides/v3/threads-and-audit-records.md", "Threads And Audit Records"}
     ]},
    {"Operate And Extend",
     [
       {"guides/v3/configuration.md", "Configuration"},
       {"guides/v3/observe-agent-turns.livemd", "Observe Agent Turns"},
       {"guides/v3/telemetry-tracing-and-logs.md", "Telemetry, Tracing, And Logs"},
       {"guides/v3/test-agents-and-plugins.livemd", "Test Agents And Plugins"},
       {"guides/v3/deployment-and-shutdown.md", "Deployment And Shutdown"},
       {"guides/v3/limits-and-performance.md", "Limits And Performance"},
       {"guides/v3/extension-boundaries.md", "Extension Boundaries"},
       {"guides/v3/example-systems.md", "Example Systems"}
     ]},
    {"Upgrade",
     [
       {"guides/migration.md", "Upgrade From Jido v2 To v3"}
     ]}
  ]

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
      description: @description,
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
      api_reference: true,
      filter_modules: fn module, _metadata ->
        not String.starts_with?(Atom.to_string(module), "Elixir.Jido.Examples.")
      end,
      source_ref: "v#{@version}",
      source_url: "https://github.com/agentjido/jido",
      authors: ["Mike Hostetler <mike.hostetler@gmail.com>"],
      groups_for_extras: project_groups() ++ guide_groups(),
      extras: project_extras() ++ guide_extras(),
      extra_section: "Guides",
      formatters: ["html"],
      # README and the migration guide still link to the old guide set. Remove
      # these two entries when their v3 rewrites replace those links.
      skip_undefined_reference_warnings_on: [
        "README.md",
        "guides/migration.md",
        "CHANGELOG.md",
        "LICENSE"
      ],
      groups_for_modules: [
        "Agent Contracts": [
          Jido.Agent,
          Jido.Agent.StateBudget,
          Jido.Agent.Command,
          Jido.Agent.Turn,
          Jido.Agent.Turn.Outcome
        ],
        "Agent Authoring": [
          Jido.Agent.Builder,
          Jido.Agent.Codec,
          Jido.Agent.Codec.Registry,
          Jido.Agent.Extension,
          Jido.Plugin.Codec
        ],
        "Agent Directives": [
          Jido.Agent.Directive,
          Jido.Agent.Directive.AdoptChild,
          Jido.Agent.Directive.Emit,
          Jido.Agent.Directive.EmitToChild,
          Jido.Agent.Directive.EmitToParent,
          Jido.Agent.Directive.Error,
          Jido.Agent.Directive.Spawn,
          Jido.Agent.Directive.SpawnAgent,
          Jido.Agent.Directive.Stop,
          Jido.Agent.Directive.StopChild
        ],
        "Actor Runtime": [
          Jido,
          Jido.AgentServer,
          Jido.AgentServer.ChildInfo,
          Jido.AgentServer.DirectiveContext,
          Jido.AgentServer.ParentRef,
          Jido.Config.Defaults,
          Jido.RuntimeStore
        ],
        "Plugin Contracts": [
          Jido.Plugin,
          Jido.Plugin.DirectiveContext,
          Jido.Plugin.Init,
          Jido.Plugin.SignalContext
        ],
        "Built-In Plugins": [
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
        Topology: [
          Jido.Topology,
          Jido.Topology.Builder,
          Jido.Topology.Codec,
          Jido.Topology.Controller,
          Jido.Topology.Instance,
          Jido.Topology.Plan,
          Jido.Topology.Ref,
          Jido.Topology.Reference
        ],
        "Persistence And History": [
          Jido.Persistence,
          Jido.Persistence.Adapter,
          Jido.Persistence.ETS,
          Jido.Persistence.File,
          Jido.Persistence.Redis,
          Jido.Thread,
          Jido.Thread.Entry,
          Jido.Thread.EntryNormalizer
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
        Errors: [
          Jido.Error,
          Jido.Error.CompensationError,
          Jido.Error.ExecutionError,
          Jido.Error.InternalError,
          Jido.Error.RoutingError,
          Jido.Error.TimeoutError,
          Jido.Error.ValidationError
        ],
        Utilities: [
          Jido.ID,
          Jido.Util
        ]
      ]
    ]
  end

  defp project_groups do
    [Project: ["README.md", "CONTRIBUTING.md", "CHANGELOG.md", "LICENSE"]]
  end

  defp project_extras do
    [
      {"README.md", title: "Home"},
      {"CONTRIBUTING.md", title: "Contributing"},
      {"CHANGELOG.md", title: "Changelog"},
      {"LICENSE", title: "Apache 2.0 License"}
    ]
  end

  defp guide_groups do
    Enum.flat_map(@guide_toc, fn {group, guides} ->
      paths = for {path, _title} <- guides, File.regular?(path), do: path
      if paths == [], do: [], else: [{group, paths}]
    end)
  end

  defp guide_extras do
    for {_group, guides} <- @guide_toc,
        {path, title} <- guides,
        File.regular?(path),
        do: {path, title: title}
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
