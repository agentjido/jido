# Covenant contracts

`jido.agent` protects current `Jido.Agent.*` value, authoring, direct-command,
and composition behavior. Its obligation file is
`jido/agent.obligations.md`. The module list is a mutation target list, not a
public API list.

The Agent component does not own AgentServer lifecycle behavior, Directive
dispatch, persistence records or stores, Scheduler provider internals, or
shared Registry and Plugin internals. Those areas keep their normal focused
tests and owner contracts.

Run the passing-test gate from the `jido` repository:

```sh
mix test.contract
```

The command runs `test/contract` and writes `coverage.json`. Its percentage
means that each active obligation has a passing tagged test. It is not line or
mutation coverage.

Run mutation analysis only at an explicit review checkpoint:

```sh
MIX_ENV=test mix covenant.mutate jido.agent --macros --jobs 4 --seed 0 \
  --timeout 5000 --max-runtime 3600000
```

The previous full Agent mutation run used an older source and obligation set.
Its survivor ledger was removed during the 2026-10-19 hardening pass. Do not
claim a current full mutation result until the current profile completes.

`jido.agent_server2` retains its separate activation-runtime contract. The
retired `jido.topology` component has no active obligations.
