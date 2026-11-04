defmodule Jido.MixProject do
  use Mix.Project

  def project do
    [
      app: :jido,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      dialyzer: [plt_add_apps: [:ex_unit], ignore_warnings: ".dialyzer_ignore.exs"],
      docs: docs(),
      package: package(),
      test_ignore_filters: test_ignore_filters(),
      test_coverage: test_coverage()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {Jido.Application, []},
      extra_applications: [:crypto, :inets, :logger, :public_key, :ssl]
    ]
  end

  def cli do
    [
      preferred_envs: [
        bench: :prod,
        "bench.ai.fresh_workflow": :prod,
        "bench.ai.state_growth": :prod,
        ci: :test,
        coveralls: :test,
        "coveralls.json": :test,
        quality: :test,
        "quality.contract": :test,
        "quality.coverage": :test,
        "quality.report": :test,
        "test.authoring": :test,
        "test.all": :test,
        "test.bench": :test,
        "test.ci": :test,
        "test.contracts": :test,
        "test.examples": :test,
        "test.fuzz": :test,
        "test.live": :test,
        "test.load": :test,
        "test.peer": :test,
        "test.property": :test,
        "test.services": :test,
        "test.system": :test
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp docs do
    published_guides =
      guide_toc()
      |> Enum.map(fn {section, guides} ->
        guides = Enum.filter(guides, fn {_title, path} -> File.regular?(path) end)
        {section, guides}
      end)
      |> Enum.reject(fn {_section, guides} -> guides == [] end)

    [
      main: "Jido",
      api_reference: true,
      extra_section: "Guides",
      extras: for({_section, guides} <- published_guides, {title, path} <- guides, do: {path, title: title}),
      groups_for_extras:
        for(
          {section, guides} <- published_guides,
          do: {section, Enum.map(guides, &elem(&1, 1))}
        )
    ]
  end

  # This exact list is the guide backlog. Add content at a listed path to
  # publish it. Do not replace the list with a guides/ wildcard: files that are
  # not listed here are not part of this guide set.
  defp guide_toc do
    [
      {:"Start Here",
       [
         {"Jido Mental Model", "guides/start-here/jido-mental-model.md"},
         {"Getting Started", "guides/start-here/getting-started.livemd"},
         {"Start a Jido Instance", "guides/start-here/start-a-jido-instance.livemd"},
         {"Build Your First Action", "guides/start-here/first-action.livemd"},
         {"Build Your First Flow", "guides/start-here/build-your-first-flow.livemd"},
         {"Build Your First Agent", "guides/start-here/first-agent.livemd"},
         {"Test Jido Code", "guides/start-here/testing-jido-code.livemd"}
       ]},
      {:"From TypeScript",
       [
         {"Node.js and the BEAM", "guides/from-typescript/nodejs-and-the-beam.md"},
         {"TypeScript Concept Map", "guides/from-typescript/typescript-concept-map.md"},
         {"Types and Validation", "guides/from-typescript/types-and-validation.md"},
         {"Errors and Async", "guides/from-typescript/errors-and-async.md"},
         {"Effects as Data", "guides/from-typescript/effects-as-data.md"}
       ]},
      {:"Core Concepts",
       [
         {"OTP Concepts for Jido", "guides/core-concepts/otp-concepts-for-jido.md"},
         {"Life of a Signal", "guides/core-concepts/signal-to-effects.md"},
         {"Pure or Live Execution", "guides/core-concepts/pure-or-live-execution.md"},
         {"Definitions and Runtime", "guides/core-concepts/definitions-instances-activations.md"},
         {"Turns and Effects", "guides/core-concepts/turns-commits-and-effects.md"}
       ]},
      {:Actions,
       [
         {"Actions", "guides/actions/actions.md"},
         {"Schemas and Validation", "guides/actions/schemas-validation.md"},
         {"Outputs and Effects", "guides/actions/action-effects.livemd"},
         {"Instructions and Targets", "guides/actions/instructions.md"},
         {"Action Context", "guides/actions/action-context.md"},
         {"Execution Policy", "guides/actions/action-execution-policy.md"},
         {"Test Actions", "guides/actions/testing-actions.livemd"}
       ]},
      {:"Author Flows",
       [
         {"Flows", "guides/flows/flows.md"},
         {"Flow DSL Tour", "guides/flows/flow-language.livemd"},
         {"Steps and Output", "guides/flows/flow-steps.md"},
         {"Inline Actions", "guides/flows/inline-actions.md"},
         {"Inline Action DSLs", "guides/flows/building-dsls-with-inline-actions.md"},
         {"References and Data", "guides/flows/flow-references.livemd"},
         {"Expressions", "guides/flows/flow-expressions.md"},
         {"Flow Dependencies", "guides/flows/flow-dependencies.livemd"},
         {"Choices and Conditions", "guides/flows/flow-choices.md"},
         {"Map and Reduce", "guides/flows/flow-collections.md"},
         {"Iterate and State", "guides/flows/flow-iterate-state.md"},
         {"Nested Flows", "guides/flows/nested-flows.livemd"},
         {"Dynamic Flows", "guides/flows/dynamic-flows.md"},
         {"Flow Extensions", "guides/flows/flow-modules.md"}
       ]},
      {:"Flows as Data",
       [
         {"Authoring Runtime Data", "guides/flow-data/authoring-runtime-data.md"},
         {"Flow Data Definitions", "guides/flow-data/flow-data.md"},
         {"Store Flows as JSON", "guides/flow-data/flow-storage.md"},
         {"Inspect Flows", "guides/flow-data/flow-inspection.md"},
         {"Flow Identity", "guides/flow-data/flow-identity-and-versioning.md"}
       ]},
      {:"Run Flows",
       [
         {"Execution", "guides/flow-runtime/execution.md"},
         {"Execute Flows", "guides/flow-runtime/flow-execution.livemd"},
         {"Managed Execution", "guides/flow-runtime/managed-execution.md"},
         {"Flow Waits", "guides/flow-runtime/flow-waits.md"},
         {"Flow Errors", "guides/flow-runtime/flow-errors.md"},
         {"Debug Flows", "guides/flow-runtime/debugging-flows.md"},
         {"Test Flows", "guides/flow-runtime/testing-flows.livemd"},
         {"Flow Security", "guides/flow-runtime/flow-security.md"}
       ]},
      {:"Author Agents",
       [
         {"Define an Agent", "guides/agents/define-and-instantiate-an-agent.livemd"},
         {"Agent State and Schemas", "guides/agents/agent-state-and-schemas.md"},
         {"Routes and Handlers", "guides/agents/build-agent-routes.livemd"},
         {"Transforms and Forwards", "guides/agents/route-transforms-and-forwards.md"},
         {"Agent Turns and Replies", "guides/agents/turns-state-and-replies.md"},
         {"State and Directives", "guides/agents/agent-results-and-directives.md"},
         {"Mutations and Diffs", "guides/agents/agent-mutations-and-diffs.livemd"},
         {"Documents and Views", "guides/agents/agent-documents-and-views.md"},
         {"Agent Callbacks", "guides/agents/agent-callbacks.md"},
         {"Test Agent Definitions", "guides/agents/testing-agent-definitions.livemd"}
       ]},
      {:"Compose Agents",
       [
         {"Composition Vocabulary", "guides/composition/composition-vocabulary.md"},
         {"Declare Agent Topology", "guides/composition/declare-agent-topology.livemd"},
         {"Connect Agent Outputs", "guides/composition/connect-agent-outputs.livemd"},
         {"Parent and Child Agents", "guides/composition/parent-and-child-agents.md"},
         {"Change Live Composition", "guides/composition/change-live-composition.md"},
         {"Topology Reconciliation", "guides/composition/topology-reconciliation.md"}
       ]},
      {:Signals,
       [
         {"Custom Signals", "guides/signals/signals-and-custom-types.md"},
         {"CloudEvents Context", "guides/signals/cloudevents-envelope-and-context.md"},
         {"Signal Data Schemas", "guides/signals/signal-data-schemas.md"},
         {"Signal Wire Format", "guides/signals/signal-codecs.md"},
         {"Signal Routing", "guides/signals/routing-and-router-dsl.md"},
         {"Signal Dispatch Adapters", "guides/signals/dispatch-adapters.md"},
         {"Signal Bus", "guides/signals/signal-bus-and-subscriptions.md"},
         {"Durable Subscriptions", "guides/signals/durable-subscriptions.md"},
         {"Signal Boundaries", "guides/signals/signal-boundaries.md"}
       ]},
      {:"Build Plugins",
       [
         {"Plugin Design", "guides/plugins/plugin-design.md"},
         {"Write a Stateful Plugin", "guides/plugins/write-a-stateful-plugin.livemd"},
         {"Plugin Routing", "guides/plugins/plugin-input-and-routes.md"},
         {"Plugin State", "guides/plugins/plugin-state-and-directives.md"},
         {"Custom Directives", "guides/plugins/plugin-custom-directives.livemd"},
         {"Supervised Resources", "guides/plugins/plugin-supervised-resources.livemd"},
         {"Post-Commit Work", "guides/plugins/plugin-post-commit-work.md"},
         {"Plugin Persistence", "guides/plugins/plugin-persistence.md"},
         {"Live Reconfiguration", "guides/plugins/plugin-live-reconfiguration.md"},
         {"Test Plugins", "guides/plugins/testing-plugins.livemd"}
       ]},
      {:"Built-In Plugins",
       [
         {"Audit Records", "guides/built-in-plugins/audit-records.md"},
         {"Signal Bus Plugin", "guides/built-in-plugins/signal-bus-plugin.livemd"},
         {"Agent Heartbeats", "guides/built-in-plugins/heartbeats.livemd"},
         {"Schedules", "guides/built-in-plugins/scheduler.livemd"},
         {"Managed Sensors", "guides/built-in-plugins/managed-sensors.livemd"}
       ]},
      {:"Run Agent Servers",
       [
         {"Start and Address Agents", "guides/agent-servers/start-and-address-live-agents.livemd"},
         {"Call, Cast, and Await", "guides/agent-servers/send-signals-to-live-agents.livemd"},
         {"Admission and Deadlines", "guides/agent-servers/agent-server-admission.md"},
         {"Status and Turn History", "guides/agent-servers/status-and-history.md"},
         {"Cancel Turns", "guides/agent-servers/cancel-turns.livemd"},
         {"Control Activations", "guides/agent-servers/inspect-and-control-activations.livemd"},
         {"Agent Lifecycle", "guides/agent-servers/agent-activation-control.md"},
         {"Hibernate and Thaw", "guides/agent-servers/hibernate-thaw-and-activate.md"},
         {"Child Agent Adoption", "guides/agent-servers/child-agents-and-adoption.md"},
         {"Runtime Effects", "guides/agent-servers/runtime-directives-and-effects.md"},
         {"Upgrade Live Agents", "guides/agent-servers/upgrade-live-agents.md"}
       ]},
      {:Durability,
       [
         {"Durability Model", "guides/durability/durability-model.md"},
         {"Make an Agent Durable", "guides/durability/make-an-agent-durable.livemd"},
         {"Durable Agent Activation", "guides/durability/durable-agent-activation.livemd"},
         {"Durable Turns and Flows", "guides/durability/durable-turns-and-flows.livemd"},
         {"Revisions and Conflicts", "guides/durability/durable-revisions-and-conflicts.md"},
         {"Checkpoints and Upgrades", "guides/durability/checkpoints-and-data-upgrades.md"},
         {"Durable Topology", "guides/durability/durable-topology.md"},
         {"Recovery Limits", "guides/durability/recovery-and-effect-limits.md"},
         {"Deletion and Tombstones", "guides/durability/deletion-and-tombstones.md"}
       ]},
      {:Storage,
       [
         {"Storage Model", "guides/storage/persistence-storage-model.md"},
         {"Persistence Adapters", "guides/storage/persistence-adapters.livemd"},
         {"Custom Adapters", "guides/storage/custom-persistence-adapter.md"},
         {"Local Stores", "guides/storage/local-persistence-adapters.md"},
         {"Ecto Storage", "guides/storage/ecto-persistence.md"},
         {"Redis and S3 Stores", "guides/storage/redis-and-s3-persistence.md"},
         {"Bedrock and Raft Storage", "guides/storage/bedrock-persistence.md"},
         {"Continuation Storage", "guides/storage/flow-continuations.md"}
       ]},
      {:"AI Agents",
       [
         {"Graph-First AI Agents", "guides/ai/graph-first-ai-agents.livemd"},
         {"Reasoning Setup", "guides/ai/reasoning-flows-models-and-limits.md"},
         {"AI Requests and Sessions", "guides/ai/requests-responses-and-sessions.livemd"},
         {"Model Context Lifecycle", "guides/ai/model-context-lifecycle.md"},
         {"Thread Projection", "guides/ai/thread-projection.md"},
         {"Inference Clients", "guides/ai/inference-clients.md"},
         {"Configure ReqLLM", "guides/ai/req-llm-configuration.livemd"},
         {"Model Capabilities", "guides/ai/model-capabilities.md"},
         {"Tools and Toolsets", "guides/ai/tools-skills-and-toolsets.livemd"},
         {"Tool Calls and Results", "guides/ai/tool-calls-and-results.md"},
         {"Model Budgets and Usage", "guides/ai/budgets-and-usage.md"},
         {"ReAct Reasoning", "guides/ai/react-reasoning.livemd"},
         {"Tool Review", "guides/ai/tool-review.md"},
         {"Reasoning Strategies", "guides/ai/reasoning-strategies.md"},
         {"Custom Reasoning Flows", "guides/ai/custom-reasoning-flows.livemd"},
         {"Test AI Agents", "guides/ai/testing-ai-agents.livemd"}
       ]},
      {:"Data and Contracts",
       [
         {"Jido.Joi Validation", "guides/data/joi-validation.md"},
         {"Jido.Codec Documents", "guides/data/versioned-documents.md"},
         {"Portable Values", "guides/data/portable-values-and-references.md"},
         {"Catalog and Discovery", "guides/data/catalog.md"},
         {"Sessions and Threads", "guides/data/sessions-and-threads.md"},
         {"Identifiers and UUIDv7", "guides/data/identifiers.md"},
         {"Jido Error Contracts", "guides/data/error-contracts.md"},
         {"Trace Context", "guides/data/trace-context.md"}
       ]},
      {:"Operate Jido",
       [
         {"Instances and Tenants", "guides/operations/configuration-and-tenant-isolation.md"},
         {"Production Setup", "guides/operations/production-configuration.md"},
         {"Observe Agent Turns", "guides/operations/observe-agent-turns.livemd"},
         {"Telemetry and Tracing", "guides/operations/telemetry-tracing-and-logs.md"},
         {"Metrics and OTel", "guides/operations/metrics-and-open-telemetry.md"},
         {"Runtime Debugging", "guides/operations/runtime-state-and-debugging.md"},
         {"Test Jido Systems", "guides/operations/test-jido-systems.livemd"},
         {"Deployment and Sizing", "guides/operations/deployment-and-performance.md"},
         {"Load Testing", "guides/operations/load-and-performance-testing.md"},
         {"Shutdown and Recovery", "guides/operations/shutdown-and-recovery.md"},
         {"Security Model", "guides/operations/security.md"}
       ]},
      {:Reference,
       [
         {"Public API Guide", "guides/reference/public-api-reference.md"},
         {"Module and Namespace Map", "guides/reference/module-and-namespace-map.md"},
         {"Configuration Reference", "guides/reference/configuration-reference.md"},
         {"Telemetry Events", "guides/reference/telemetry-event-reference.md"},
         {"Persistence Matrix", "guides/reference/persistence-adapter-matrix.md"},
         {"Reasoning Matrix", "guides/reference/reasoning-strategy-matrix.md"},
         {"V2 to V3 Migration", "guides/reference/v2-to-v3-migration.md"},
         {"Package Consolidation", "guides/reference/consolidated-package-migration.md"}
       ]}
    ]
  end

  defp test_coverage do
    [
      tool: ExCoveralls,
      output: "tmp/quality/coverage/coverdata",
      ignore_modules: [
        ~r/^Inspect\.Jido/,
        ~r/^Jido\.Test\./,
        ~r/^Jido\.Flow\.DSL\.Forms\.Flow\./,
        ~r/^Jido\.Flow\.DSL\.(?:Entity|Step|Output)$/,
        ~r/^Jido\.Flow\.DSL\.Forms\.(?:Map|Reduce|Choice(?:\.Option|\.Otherwise)?|Parallel(?:\.Action)?|Iterate(?:\.State)?|Invoke|Wait\.(?:Await|Timer|Selection(?:\.Await|\.Timer)?))$/,
        ~r/^Jido\.Action\.Generated\.Inline\./
      ],
      summary: [threshold: 90]
    ]
  end

  defp deps do
    [
      # Runtime
      {:multigraph, "~> 0.16.1-mg.5"},
      {:req_llm, "~> 1.29"},
      {:runic, "~> 0.1.0-alpha.13"},
      {:sched_ex, "~> 1.2.1"},
      {:spark, "~> 2.7.3"},
      {:splode, "~> 0.3.0"},
      {:telemetry, "~> 1.3"},
      {:telemetry_metrics, "~> 1.2"},
      {:yaml_elixir, "~> 2.12"},
      {:zoi, "~> 0.19.0", override: true},

      # Optional integrations
      {:bedrock, "~> 0.7.2", optional: true},
      {:bedrock_raft, "~> 0.10.0", optional: true},
      {:ecto_sql, "~> 3.14", optional: true},
      {:opentelemetry_api, "~> 1.0", optional: true},
      {:phoenix_pubsub, "~> 2.1", optional: true},

      # Development and test tools
      {:covenant, "~> 0.2.0", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_dna, "~> 1.5", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},
      {:excoveralls, "~> 0.18.5", only: [:dev, :test]},
      {:ex_slop, "~> 0.4", only: [:dev, :test], runtime: false},
      {:reach, "~> 2.8", only: [:dev, :test], runtime: false},

      # Test support
      {:ecto_sqlite3, "~> 0.24.1", only: :test},
      {:mimic, "~> 2.0", only: :test},
      {:opentelemetry, "~> 1.0", only: :test, runtime: false},
      {:plug, "~> 1.0", only: :test},
      {:postgrex, "~> 0.19 or ~> 1.0", only: :test},
      {:stream_data, "~> 1.4", only: :test, runtime: false}
    ]
  end

  defp aliases do
    [
      bench: "run test/perf/jido_ai/react_memory.exs",
      "bench.ai.fresh_workflow": "run test/perf/jido_ai/react_fresh_workflow.exs",
      "bench.ai.state_growth": "run test/perf/jido_ai/react_state_growth.exs",
      ci: [
        "compile --warnings-as-errors",
        "format --check-formatted",
        "test.ci",
        "credo --strict --min-priority higher",
        "credo --strict --mute-exit-status",
        "dialyzer --list-unused-filters",
        "ex_dna --max-clones 17",
        "reach.check --arch --smells"
      ],
      quality: [
        "quality.contract",
        "compile --warnings-as-errors",
        "format --check-formatted",
        "credo --strict --min-priority higher",
        "credo --strict --mute-exit-status",
        "dialyzer --list-unused-filters",
        "ex_dna --max-clones 17",
        "reach.check --arch --smells"
      ],
      "test.authoring": test_alias("test/authoring", :authoring),
      "test.all": "test.ci",
      "test.bench": test_alias("test/perf", :bench),
      "test.ci": &run_test_ci/1,
      "test.contracts": "covenant.check",
      "test.examples": test_alias("test/examples", :example),
      "test.fuzz": fn args ->
        run_tagged_tests("test/property", :fuzz, args)
        check_property_report!(args, :fuzz)
      end,
      "test.live": test_alias("test/external/jido_ai", :live),
      "test.load": test_alias("test/perf", :load),
      "test.peer": test_alias("test", :peer),
      "test.property": fn args ->
        run_tagged_tests("test/property", :property, args)
        check_property_report!(args, :property)
      end,
      "test.services": test_alias("test/external", :service),
      "test.system": test_alias("test/system", :system),
      "quality.contract": "test test/quality/quality_contract_test.exs --seed 0",
      "quality.coverage": fn args ->
        Mix.Task.run("app.start")
        Code.require_file("test/quality/support/contract.exs")
        Code.require_file("test/quality/support/component_proof.exs")
        Code.require_file("test/quality/support/coverage.exs")
        Jido.Quality.Coverage.run!(File.cwd!(), args)
      end,
      "quality.report": fn args ->
        Mix.Task.run("app.start")
        Code.require_file("test/quality/support/contract.exs")
        Code.require_file("test/quality/support/component_proof.exs")
        Code.require_file("test/quality/support/report.exs")
        Jido.Quality.Report.run!(File.cwd!(), args)
      end
    ]
  end

  defp test_alias(default_path, tag) do
    fn args -> run_tagged_tests(default_path, tag, args) end
  end

  defp run_tagged_tests(default_path, tag, args) do
    explicit_path? = Enum.any?(args, &test_path?/1)
    default_path? = File.exists?(default_path)

    if default_path? or explicit_path? do
      paths = if default_path? and not explicit_path?, do: [default_path], else: []
      Mix.Task.run("test", ["--only", Atom.to_string(tag), "--seed", "0"] ++ paths ++ args)
    else
      Mix.shell().info("No #{tag} tests found under #{default_path}")
    end
  end

  defp run_test_ci([]) do
    [
      ["quality.contract"],
      ["test", "--seed", "0"],
      ["test.authoring"],
      ["test.contracts"],
      ["test.examples"],
      ["test.property"],
      ["test.fuzz"],
      ["test.system"],
      ["test.load"],
      ["test.peer"],
      ["test.bench"]
    ]
    |> Enum.each(&run_mix_task!/1)
  end

  defp run_test_ci(args), do: Mix.raise("mix test.ci does not accept arguments: #{inspect(args)}")

  defp run_mix_task!(args) do
    mix = System.find_executable("mix") || Mix.raise("mix executable is not available")
    Mix.shell().info("test.ci: mix #{Enum.join(args, " ")}")

    case System.cmd(mix, args, env: [{"MIX_ENV", "test"}], stderr_to_stdout: true) do
      {output, 0} -> IO.write(output)
      {output, status} -> Mix.raise("mix #{Enum.join(args, " ")} failed with status #{status}\n#{output}")
    end
  end

  defp test_path?(argument) do
    not String.starts_with?(argument, "-") and File.exists?(argument)
  end

  defp check_property_report!(args, suite) do
    paths = Enum.filter(args, &test_path?/1)
    all? = paths == [] or Enum.any?(paths, &(Path.expand(&1) == Path.expand("test/property")))

    Code.require_file("test/property/support/report.exs")
    Jido.Test.Property.Report.check!(full: all?, suite: suite)
  end

  defp test_ignore_filters do
    [
      ~r/^test\/consumers\//,
      ~r/^test\/contracts\//,
      ~r/^test\/authoring\/support\//,
      ~r/^test\/examples\/support\//,
      ~r{^test/perf/(?:jido_ai/(?:react_fresh_workflow|react_memory|react_state_growth|react_stress|react_support)|jido_exec/flow_run|jido_flow/(?:dsl_compile|flow_compile)|jido_signal/run)\.exs$},
      ~r{^test/perf/(?:jido_signal/support|support)/},
      ~r/^test\/quality\/support\//,
      ~r{^test/property/(?:support|[^/]+/support)/},
      ~r{^test/external/(?:support|(?:minio|redis)/support\.exs)},
      ~r|^test/system/jido_agent_server/support/|
    ]
  end

  defp package do
    [files: [".formatter.exs", "lib", "mix.exs"]]
  end
end
