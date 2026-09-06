# Runtime Inspection

Feature ID: `04_05_runtime_inspection`. Status: implemented within the tested scope.

## Added feature

Public inspection exposes committed state and its matching revision while work is active. Read this after the Basic and Workflow groups.

## Use

```elixir
alias Jido.Examples.AgentLiveDebugger

{:ok, server} = Jido.start_agent(jido, AgentLiveDebugger)
AgentLiveDebugger.snapshot(server)
```

## Evidence

2 enabled tests:

- a snapshot uses public inspection and removes secrets.
- inspection reads the committed state while an Action is still running.

Run:

```shell
mix test --include integration test/examples/04_runtime/04_05_runtime_inspection --seed 0
```

[Source](../../../../examples/04_runtime/04_05_runtime_inspection/agent_live_debugger.ex) ·
[Tests](../../../../test/examples/04_runtime/04_05_runtime_inspection/agent_live_debugger_test.exs)

## Boundary and next question

Redaction is application policy. Runtime phase is sampled separately from the state snapshot. This is not an automatic trace or progress stream.

See the [gap register](../../runtime-multi-agent-gaps.md) and
[verification report](../../runtime-multi-agent-results.md).
