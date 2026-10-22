defmodule Jido.MixProject do
  use Mix.Project

  @version "3.0.0-beta.2"
  @description "A declarative actor and agent framework for Elixir"

  # This is the source of truth for the guide set. ExDoc adds a guide after
  # its file exists. This lets us review the complete contents before we write
  # the guide text.
  #
  # The Action and Signal boundary guides will link to the Jido Action and
  # Jido Signal documentation.
  @guide_toc [
    {"Start Here",
     [
       {"guides/getting-started.livemd", "Getting Started"}
     ]},
    {"From TypeScript",
     [
       {"guides/nodejs-and-the-beam.md", "Node.js and the BEAM"},
       {"guides/typescript-concept-map.md", "TypeScript Concept Map"},
       {"guides/types-and-validation.md", "Types and Validation"},
       {"guides/errors-and-async.md", "Errors and Async"},
       {"guides/effects-as-data.md", "Effects as Data"}
     ]},
    {"Core Concepts",
     [
       {"guides/otp-concepts-for-jido.md", "OTP Concepts"},
       {"guides/signal-to-effects.md", "Life of a Signal"},
       {"guides/pure-or-live-execution.md", "Pure or Live Execution"}
     ]},
    {"Author Agents",
     [
       {"guides/define-and-instantiate-an-agent.livemd", "Define an Agent"},
       {"guides/build-agent-routes.livemd", "Routes and Handlers"},
       {"guides/typed-signal-actions.livemd", "Typed Signals"},
       {"guides/agent-results-and-directives.md", "State and Directives"},
       {"guides/agent-mutations-and-diffs.livemd", "Mutations and Diffs"},
       {"guides/agent-documents-and-views.md", "Documents and Views"}
     ]},
    {"Compose Agents",
     [
       {"guides/composition-vocabulary.md", "Composition Vocabulary"},
       {"guides/declare-agent-topology.livemd", "Nested Agents"},
       {"guides/connect-agent-outputs.livemd", "Connect Agent Outputs"},
       {"guides/change-live-composition.md", "Change Live Composition"}
     ]},
    {"Build Plugins",
     [
       {"guides/extensions-and-plugins.md", "Extensions or Plugins"},
       {"guides/write-a-stateful-plugin.livemd", "Stateful Plugins"},
       {"guides/plugin-supervised-resources.livemd", "Supervised Resources"},
       {"guides/plugin-custom-directives.livemd", "Custom Directives"},
       {"guides/plugin-persistence-and-live-changes.md", "Plugin Persistence"}
     ]},
    {"Use Built-In Plugins",
     [
       {"guides/signal-bus-plugin.livemd", "Signal Bus"},
       {"guides/audit-records.md", "Audit Records"},
       {"guides/heartbeats-and-schedules.livemd", "Heartbeats and Schedules"},
       {"guides/managed-sensors.livemd", "Managed Sensors"}
     ]},
    {"Run Agent Servers",
     [
       {"guides/start-and-address-live-agents.livemd", "Start and Address Agents"},
       {"guides/send-signals-to-live-agents.livemd", "Call, Cast, and Await"},
       {"guides/agent-server-admission.md", "Admission and Deadlines"},
       {"guides/inspect-and-control-activations.livemd", "Inspect Activations"},
       {"guides/agent-activation-control.md", "Supervision and Lifecycle"}
     ]},
    {"Build Durable Systems",
     [
       {"guides/durability-model.md", "Durability Model"},
       {"guides/make-an-agent-durable.livemd", "Make an Agent Durable"},
       {"guides/durable-agent-activation.livemd", "Durable Activation"},
       {"guides/durable-turns-and-flows.livemd", "Durable Turns and Flows"},
       {"guides/durable-revisions-and-conflicts.md", "Revisions and Conflicts"},
       {"guides/checkpoints-and-data-upgrades.md", "Checkpoints and Upgrades"},
       {"guides/recovery-and-effect-limits.md", "Recovery Limits"}
     ]},
    {"Storage and Adapters",
     [
       {"guides/persistence-storage-model.md", "Storage Model"},
       {"guides/persistence-adapters.livemd", "Persistence Adapters"},
       {"guides/custom-persistence-adapter.md", "Custom Adapters"}
     ]},
    {"Operate Jido",
     [
       {"guides/configuration-and-tenant-isolation.md", "Instances and Tenants"},
       {"guides/action-discovery-and-permission.md", "Action Discovery"},
       {"guides/observe-agent-turns.livemd", "Observability"},
       {"guides/test-jido-systems.livemd", "Testing"},
       {"guides/deployment-and-performance.md", "Deployment and Sizing"}
     ]},
    {"Reference",
     [
       {"guides/v2-to-v3-migration.md", "Migrating from V2"}
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
      test_ignore_filters: [
        fn path ->
          (String.starts_with?(path, "test/contract/") or
             String.starts_with?(path, "test/bench/") or
             String.starts_with?(path, "test/examples/support/") or
             String.starts_with?(path, "test/authoring/") or
             String.starts_with?(path, "test/property/") or
             String.starts_with?(path, "test/system/")) and
            not String.ends_with?(path, "_test.exs")
        end
      ],

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
        plt_add_apps: [:ex_unit, :mix]
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
        q: :test,
        quality: :test,
        "test.bench": :test,
        "test.peer": :test,
        "test.examples": :test,
        "test.persistence": :test,
        "test.authoring": :test,
        "test.system": :test,
        "test.property": :test,
        "test.fuzz": :test,
        "test.contract": :test,
        "test.ci": :test,
        "test.services": :test,
        "test.services.minio": :test,
        "test.all": :test,
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
  defp elixirc_paths(:test),
    do: ["lib", "test/support", "test/jido/support"]

  defp elixirc_paths(:dev), do: ["lib"]
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
      skip_undefined_reference_warnings_on: [
        "CHANGELOG.md",
        "LICENSE"
      ],
      groups_for_modules: [
        "Agent Contracts": [
          Jido.Agent,
          Jido.Agent.Diff,
          Jido.Agent.Plugin,
          Jido.Agent.Plugin.Preparation,
          Jido.Agent.Plugin.Reduction,
          Jido.Agent.Ref,
          Jido.Agent.Command,
          Jido.Agent.Turn,
          Jido.Agent.View
        ],
        "Agent Authoring": [
          Jido.Agent.Extension,
          Jido.Agent.Topology,
          Jido.SignalAction
        ],
        "Agent Directives": [
          Jido.Agent.Directive,
          Jido.Agent.Directive.AgentAdd,
          Jido.Agent.Directive.AgentRemove,
          Jido.Agent.Directive.AgentReplace,
          Jido.Agent.Directive.AgentUpdate,
          Jido.Agent.Directive.ConnectionAdd,
          Jido.Agent.Directive.ConnectionRemove,
          Jido.Agent.Directive.ConnectionReplace,
          Jido.Agent.Directive.ConnectionUpdate,
          Jido.Agent.Directive.Emit,
          Jido.Agent.Directive.PluginAdd,
          Jido.Agent.Directive.PluginConfigure,
          Jido.Agent.Directive.PluginRemove,
          Jido.Agent.Directive.RouteAdd,
          Jido.Agent.Directive.RouteRemove,
          Jido.Agent.Directive.RouteReplace,
          Jido.Agent.Directive.RouteUpdate,
          Jido.Agent.Directive.RoutesReorder,
          Jido.Agent.Directive.RoutesSet,
          Jido.Agent.Directive.TopologySet,
          Jido.AgentServer.Directive,
          Jido.AgentServer.Directive.AgentSend,
          Jido.AgentServer.Directive.OwnerSend,
          Jido.AgentServer.Directive.ErrorReport,
          Jido.AgentServer.Directive.ProcessStart,
          Jido.AgentServer.Directive.AgentStart,
          Jido.AgentServer.Directive.ServerStop,
          Jido.AgentServer.Directive.AgentStop
        ],
        "Actor Runtime": [
          Jido,
          Jido.AgentServer,
          Jido.AgentServer.Signal.Error,
          Jido.AgentServer.DirectiveContext,
          Jido.Plugin.DirectiveContext,
          Jido.Plugin.Init,
          Jido.Plugin.SignalContext
        ],
        "Plugin Contracts": [
          Jido.Plugin,
          Jido.Plugin.Input,
          Jido.AgentServer.Plugin.Admission,
          Jido.AgentServer.Plugin.Commit
        ],
        "Built-In Plugins": [
          Jido.Plugin.Audit,
          Jido.Plugin.Audit.Record,
          Jido.Plugin.Bus,
          Jido.Plugin.Bus.Client,
          Jido.Plugin.Bus.Manager,
          Jido.Plugin.Heartbeat,
          Jido.Plugin.Heartbeat.Signal.Tick,
          Jido.Plugin.Scheduler,
          Jido.Plugin.Scheduler.Cancel,
          Jido.Plugin.Scheduler.Cron,
          Jido.Plugin.Scheduler.Occurrence,
          Jido.Plugin.Scheduler.Schedule,
          Jido.Plugin.SensorManager,
          Jido.Plugin.SensorManager.Init,
          Jido.Plugin.SensorManager.Start,
          Jido.Plugin.SensorManager.Stop
        ],
        "Persistence And History": [
          Jido.Persistence,
          Jido.Persistence.Adapter,
          Jido.Persistence.Bedrock,
          Jido.Persistence.Ecto,
          Jido.Persistence.Ecto.Migration,
          Jido.Persistence.Ecto.Record,
          Jido.Persistence.ETS,
          Jido.Persistence.File,
          Jido.Persistence.Mnesia,
          Jido.Persistence.Plugin,
          Jido.Persistence.Plugin.Context,
          Jido.Persistence.Redis,
          Jido.Persistence.S3,
          Jido.Persistence.Store
        ],
        Observability: [Jido.Telemetry],
        Errors: [
          Jido.Agent.Error,
          Jido.Error,
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
      # Use the sibling package for the shared lower-layer contracts.
      {:jido_action, path: "../jido_action", override: true},
      {:jido_signal, "~> 3.0.0-beta.5"},
      # AgentServer owns native Runic Runners and Worker cleanup.
      {:runic, "~> 0.1.0-alpha.12", override: true},

      # Jido Deps
      {:zoi, "~> 0.18.11"},
      {:spark, "~> 2.7"},
      {:splode, "~> 0.3.0"},
      {:telemetry, "~> 1.3"},
      {:telemetry_metrics, "~> 1.2"},
      {:opentelemetry_api, "~> 1.0", optional: true},
      {:sched_ex, "~> 1.2.1"},

      # Optional Persistence Adapters
      {:bedrock, "~> 0.7.2", optional: true},
      {:bedrock_raft, "~> 0.10.0", optional: true},
      {:ecto_sql, "~> 3.14", optional: true},

      # Development & Test Dependencies
      {:covenant,
       github: "mikehostetler/covenant",
       branch: "feat/component-directories",
       only: [:dev, :test],
       runtime: false},
      {:ecto_sqlite3, "~> 0.24.1", only: :test},
      {:postgrex, "~> 0.19 or ~> 1.0", only: :test},
      {:opentelemetry, "~> 1.0", only: :test, runtime: false},
      {:req_llm, "~> 1.21", only: [:dev, :test]},
      {:dotenvy, "~> 1.1", only: [:dev, :test]},
      {:git_ops, "~> 2.9", only: :dev, runtime: false},
      {:git_hooks, "~> 0.8", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.21", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:excoveralls, "~> 0.18.3", only: [:dev, :test]},
      {:stream_data, "~> 1.4", only: :test, runtime: false},
      {:mix_test_watch, "~> 1.0", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      # Default exclusions are declared once in test/test_helper.exs.
      test: "test --preload-modules",

      # Run normal categories with a fixed seed. Services are opt-in and are
      # deliberately absent from test.all.
      "test.bench": "test test/bench --only bench --seed 0",
      "test.peer": "test test/jido --only peer --seed 0",
      "test.examples": "test test/examples --only example --seed 0",
      "test.persistence": "test test/jido/persistence/conformance --only persistence --seed 0",
      "test.authoring": "test test/authoring --only authoring --seed 0",
      "test.system": "test test/system/runtime --only system --seed 0",
      "test.property": "test test/property --only property --seed 0",
      "test.fuzz": "test test/property --only fuzz --seed 0",
      "test.contract": "covenant.check",
      "test.ci": [
        "test test/jido test/property --include flaky --include property --seed 0",
        "covenant.check"
      ],
      "test.services":
        "test #{Path.wildcard("test/system/services/*_test.exs") |> Enum.join(" ")} --only service --seed 0",
      "test.services.minio": "test test/system/services/minio --only service --seed 0",
      "test.all":
        "test --preload-modules --include bench --include example --include authoring --include system --include flaky --include peer --include property --seed 0",

      # Helper to run docs
      docs: "docs --open",

      # Run to check the quality of your code
      q: ["quality"],
      quality: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "credo --strict --only warning",
        "covenant.check",
        "dialyzer",
        "test test/jido test/property --include flaky --include property --seed 0"
      ]
    ]
  end
end
