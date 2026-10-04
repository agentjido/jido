# Research probes

This section records open contracts and implementation candidates for review.

1. [Distributed Authority](99_02_distributed_authority/README.md) — use an
   external ownership token to fence two local Erlang nodes.
2. [Hybrid DSL and Data-Defined Topology](99_03_data_defined_topology/README.md) —
   compare DSL, data, and JSON members at startup, addition, composition, and recovery.
3. [Child Topology Runtime](99_04_child_topology_runtime/README.md) —
   define separate child runtimes, lazy gates, Bus isolation, and branch recovery.

The [API review note](API_REVIEW.md) lists the proposed public changes.

## Run the section

```sh
mix test test/examples/99_research --include example --seed 0
```

Expected result: the external authority admits only its newest token. The core
DIST-03 test remains skipped because Jido itself cannot guarantee that one
logical identity has at most one live cluster owner.
The member and child runtime examples first failed in the first examples commit in this PR.
They now pass with the implementation candidate for issues 394 and 395.
See the API review note before accepting the DSL and runtime contracts.

## Promotion rule

Keep this probe in research until Jido has a public cluster-exclusive ownership
contract. External fencing is an application workaround, not that core
contract.

Promote the member examples after Topology accepts neutral Agent definitions
and the required tests pass. Promote the child examples after the runtime and
gate contracts are approved, implemented, and verified.
