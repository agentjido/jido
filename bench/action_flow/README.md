# Action and Flow benchmarks

These runners check Flow construction, execution, DSL compilation, and the
current ReAct memory benchmark. Each runner has `quick`, `standard`, and
`stress` profiles. CI runs only `quick`.

Run a quick profile from the package root:

```sh
MIX_ENV=test mix run bench/action_flow/flow_compile.exs --profile quick
MIX_ENV=test mix run bench/action_flow/flow_run.exs --profile quick
MIX_ENV=test mix run bench/action_flow/dsl_compile.exs --profile quick
MIX_ENV=test mix run bench/action_flow/react_stress.exs --profile quick
```

Reports go under `tmp/bench/action_flow/`. They include the runtime
environment and a source fingerprint. Result checks and process cleanup are
pass conditions. Timing and memory values are trend data. They have no CI
limit.

The ReAct runner starts `bench/react_memory.exs` in a fresh BEAM VM. That file
stays the owner of the ReAct implementation and memory measurement.
