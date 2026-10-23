# Agent DSL calls are kept without parentheses in authored modules.
agent_locals = [
  agent: 1,
  agent: 2,
  agent: 3,
  routes: 1,
  route: 1,
  route: 2,
  route: 3,
  forward: 2,
  plugin: 1,
  plugin: 2,
  schema: 1,
  metadata: 1,
  signal_source: 1,
  topology: 1,
  connections: 1,
  connect: 2,
  initial_state: 1,
  count: 1,
  transform: 1,
  transform: 2,
  schedules: 1,
  schedule: 2,
  every: 1,
  cron: 1,
  timezone: 1,
  signal: 1,
  signal_bus: 1,
  name: 1,
  thresholds: 1,
  threshold: 2,
  on: 1
]

# Used by "mix format"
[
  import_deps: [:jido_action],
  locals_without_parens: agent_locals,
  export: [locals_without_parens: agent_locals],
  inputs: ["{mix,.formatter,.credo}.exs", "{config,lib,examples,test}/**/*.{ex,exs}"]
]
