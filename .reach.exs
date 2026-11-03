[
  layers: [
    foundation: [
      "Jido.Id",
      "Jido.Joi",
      "Jido.Joi.*",
      "Jido.Expr",
      "Jido.Expr.*",
      "Jido.PortableTerm",
      "Zoi.Type.Node"
    ],
    signal: ["Inspect.Jido.Signal.*", "Jido.Signal", "Jido.Signal.*"],
    definitions: [
      "Jido.Action",
      "Jido.Action.*",
      "Jido.Codec",
      "Jido.Codec.*",
      "Jido.Discovery",
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
      "Jido.Telemetry.*",
      "Jido.Tracing",
      "Jido.Tracing.*",
      "Runic.Workflow.EventApplicator.Jido.AgentServer.*"
    ],
    ai: [
      "Jido.AI",
      "Jido.AI.*",
      "Runic.Identity.Projectable.Jido.AI.*"
    ],
    composition: ["Jido.Application"]
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
    forbidden_modules: ["Jido.Config"],
    forbidden_files: ["lib/jido/config.ex"]
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
