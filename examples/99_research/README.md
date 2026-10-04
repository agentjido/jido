# Research probe

This section retains one unsupported core contract.

1. [Distributed Authority](99_02_distributed_authority/README.md) — use an
   external ownership token to fence two local Erlang nodes.

## Run the section

```sh
mix test test/examples/99_research --include example --seed 0
```

Expected result: the external authority admits only its newest token. The core
DIST-03 test remains skipped because Jido itself cannot guarantee that one
logical identity has at most one live cluster owner.

## Promotion rule

Keep this probe in research until Jido has a public cluster-exclusive ownership
contract. External fencing is an application workaround, not that core
contract.
