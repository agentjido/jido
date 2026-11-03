[
  layers: [
    foundation: [
      "Jido.Id",
      "Jido.Joi",
      "Jido.Joi.*",
      "Jido.Expr",
      "Jido.Expr.*",
      "Jido.Trace",
      "Zoi.Type.Node"
    ],
    signal: [
      "Inspect.Jido.Signal.*",
      "Jido.Codec.Signal",
      "Jido.Codec.Signal.*",
      "Jido.Signal",
      "Jido.Signal.*",
      "Jido.Telemetry.Signal"
    ],
    definitions: [
      "Jido.Action",
      "Jido.Action.*",
      "Jido.Catalog",
      "Jido.Catalog.Entry",
      "Jido.Catalog.Error",
      "Jido.Catalog.Manifest",
      "Jido.Catalog.View",
      "Jido.Codec",
      "Jido.Codec.Compiler",
      "Jido.Codec.Config",
      "Jido.Codec.Contract",
      "Jido.Codec.Document",
      "Jido.Codec.Document.*",
      "Jido.Codec.Encoder",
      "Jido.Codec.Encoder.*",
      "Jido.Codec.Error",
      "Jido.Codec.Error.*",
      "Jido.Codec.Flow",
      "Jido.Codec.Flow.*",
      "Jido.Codec.Index",
      "Jido.Codec.Issue",
      "Jido.Codec.Limits",
      "Jido.Codec.Reference",
      "Jido.Codec.Static",
      "Jido.Codec.Term",
      "Jido.Codec.Value",
      "Jido.Codec.Value.*",
      "Jido.Flow",
      "Jido.Flow.*",
      "Jido.Instruction",
      "Jido.Session",
      "Jido.Thread",
      "Jido.Thread.*",
      "Runic.Identity.Projectable.Jido.Flow",
      "Runic.Identity.Projectable.Jido.Session",
      "Runic.Identity.Projectable.Jido.Thread",
      "Runic.Identity.Projectable.Jido.Thread.*"
    ],
    execution: [
      "Jido.Exec",
      "Jido.Exec.*",
      "Jido.Telemetry.Exec",
      "Runic.Component.Jido.Exec.*",
      "Runic.Identity.Projectable.Jido.Exec.*",
      "Runic.Transmutable.Jido.Instruction",
      "Runic.Transmutable.Jido.Exec.*",
      "Runic.Workflow.Invokable.Jido.Exec.*"
    ],
    runtime: [
      "Jido",
      "Jido.Agent",
      "Jido.Agent.*",
      "Jido.AgentServer",
      "Jido.AgentServer.*",
      "Jido.Codec.Agent",
      "Jido.Dispatch",
      "Jido.Dispatch.*",
      "Jido.Error",
      "Jido.Error.*",
      "Jido.Instance",
      "Jido.Instance.*",
      "Jido.Persistence",
      "Jido.Persistence.*",
      "Jido.Plugin",
      # Plugin.Config remains here until Jido.Error no longer depends on the
      # legacy Agent, Action, and Signal error taxonomies. It then moves with
      # Jido.Error to the declarative definitions layer.
      "Jido.Plugin.*",
      "Jido.RuntimeStore",
      "Jido.Telemetry",
      "Jido.Telemetry.OpenTelemetry*",
      "Jido.Telemetry.Persistence*",
      "Jido.Telemetry.Semantic*",
      "Jido.Trace.Context",
      "Jido.Trace.Context.*",
      "Runic.Workflow.EventApplicator.Jido.AgentServer.*"
    ],
    ai: [
      "Jido.AI",
      "Jido.AI.*",
      "Jido.Telemetry.AI",
      "Jido.Telemetry.AI.*",
      "Runic.Identity.Projectable.Jido.AI.*"
    ],
    composition: ["Jido.Application", "Jido.Catalog.Discovery"]
  ],
  deps: [
    mode: :allowlist,
    allowed: [
      foundation: [],
      signal: [:foundation],
      definitions: [:foundation, :signal],
      execution: [:foundation, :signal, :definitions],
      runtime: [:foundation, :signal, :definitions, :execution],
      ai: [:foundation, :signal, :definitions, :execution, :runtime],
      composition: [:foundation, :signal, :definitions, :execution, :runtime, :ai]
    ]
  ],
  source: [
    forbidden_modules: [
      "Jido.Config",
      "Jido.Codec.Manifest",
      "Jido.Codec.Registry",
      "Jido.Discovery",
      "Jido.Flow.Codec*",
      "Jido.Agent.Codec",
      "Jido.Signal.Codec",
      "Jido.Signal.Serialization",
      "Jido.Signal.UTF8",
      "Jido.PortableTerm",
      "Jido.AI.Telemetry*",
      "Jido.Exec.Telemetry",
      "Jido.Signal.ID",
      "Jido.Signal.Telemetry",
      "Jido.Signal.Trace",
      "Jido.Tracing.*"
    ],
    forbidden_files: [
      "lib/jido/config.ex",
      "lib/jido/codec/manifest.ex",
      "lib/jido/codec/registry.ex",
      "lib/jido/discovery.ex",
      "lib/jido/flow/codec.ex",
      "lib/jido/flow/codec/**",
      "lib/jido/agent/codec.ex",
      "lib/jido/signal/codec.ex",
      "lib/jido/signal/serialization.ex",
      "lib/jido/signal/utf8.ex",
      "lib/jido/portable_term.ex",
      "lib/jido/ai/telemetry.ex",
      "lib/jido/ai/telemetry/**",
      "lib/jido/exec/telemetry.ex",
      "lib/jido/signal/id.ex",
      "lib/jido/signal/telemetry.ex",
      "lib/jido/signal/trace.ex",
      "lib/jido/tracing/**"
    ]
  ],
  checks: [
    source_paths: ["lib"],
    layer_coverage: [require_all_modules: true, forbid_multiple_matches: true]
  ],
  boundaries: [
    public: [],
    internal: [],
    internal_callers: []
  ]
]
