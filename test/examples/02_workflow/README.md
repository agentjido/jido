# Workflow integration tests

Each Workflow integration test imports the real example source. The tests use
public Jido APIs and check visible results, errors, state, directives, and
adapter calls.

| Example | Main contract |
| --- | --- |
| `02_01_sequential_flow` | Step reuse, dependencies, commits, and schema boundaries |
| `02_02_effectful_steps` | Caller context, effect guards, output projection, and caching |
| `02_03_conditional_routes` | First-match Choice and explicit fallback policy |
| `02_04_parallel_join` | Defaults, independent branches, join, and branch failure |
| `02_05_ordered_batch` | Ordered Map, error collection, fail-fast, and Reduce |
| `02_06_bounded_iteration` | Early completion, bounds, and replacement-state validation |
| `02_07_nested_flow` | Child result scopes, shared context, and contracts |
| `02_08_executable_continuation` | Continuation types, shared budget, and input validation |
| `02_09_approval_workflow` | Separate Turns, portable directives, correlation, and idempotency |

Run the full section from the `jido` repository root:

```shell
mix test --include example test/examples/02_workflow --seed 0
```

Run one folder to test one example. These tests also run in `mix examples` and
`mix test --only example`. Each test has the `:example` tag and the
`group: :workflow` tag.

## Test boundary

The tests do not add execution barriers, private Server messages, or callbacks
to Action bodies. They do not use delays to inspect transient scheduler state.
Detailed scheduler timing, cancellation, and worker-lifecycle tests belong in
the package that owns those features.

The tests use a small public SDK helper for Agent startup and error inspection.
The approval example uses local search and booking adapters. These support
files make calls visible without network access.

## Current limits

Map `:collect_errors` keeps error positions, but its error payload contains the
message and not the complete typed Action error map. A `:fail_fast` Map rejects
the complete Turn and prevents its dependent Reduce.

A duplicate request or an ignored result Signal can still create a commit when
its Action returns unchanged state. Provider idempotency, approval rules, and
correlation checks are application policy. The approval example does not claim
durable booking recovery.

See the matching [source examples](../../../examples/02_workflow).
