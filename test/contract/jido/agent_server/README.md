# AgentServer contract tests

This folder protects the `Jido.AgentServer` runtime. The root
`jido.agent_server` component owns core request, Turn, failure-policy, and
control behavior. Its subfolders hold the activation, effects, Plugin runtime,
composition, durable Agent state, and durable Flow Turn components.

Run the focused suite or the complete Covenant gate from the `jido` repository:

```sh
mix test test/contract/jido/agent_server --seed 0
mix test.contract
```

## Scope

The complete folder covers startup, requests, execution, lifecycle control,
observation, post-commit effects, live Plugins, activation ownership, local
recovery, durable persistence, durable Flow progress and waits, composition,
and runtime upgrades.

These components do not claim distributed behavior. Agent value and authoring
rules remain in `jido.agent`. Persistence records and adapters keep their own
ownership. Durable Agent state and durable Flow progress have separate owners.

The obligation register is
[`agent_server.obligations.md`](../agent_server.obligations.md).
Current scope decisions are in
[`agent_server.decisions.yml`](../agent_server.decisions.yml).

The root mutation profile targets `Jido.AgentServer.Core`. Public tests cover
the shared `Jido.AgentServer` state-machine coordinator. Each AgentServer
subcomponent has its own focused mutation profile.
