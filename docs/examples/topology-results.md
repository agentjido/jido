> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../migration/10-execution-record.md) for the migration result.

# Topology authoring and local runtime spike

Date: 2026-09-04. Status: implemented within the local spike scope.

The spike adds a canonical `Jido.Topology` definition, Zoi-validated instance
input, stable group expansion, a Spark DSL, a Builder, and a versioned JSON
Codec. The Codec uses the existing trusted Agent Registry and document limits.
The same definition can come from all three authoring forms.

The local controller starts Buses and Agents in dependency order. It checks
readiness, establishes logical ownership, and repairs missing members. Agents
remain under the existing Jido Agent pool as temporary children. The controller
owns reactivation and retains one static desired definition.

The first four numbered examples cover independent Agents, a logical hierarchy,
a Bus swarm with 1000 workers, and keyed account records. The swarm has
checked-in DSL, Builder, and JSON forms. See the
[guide](../../lib/examples/07_topology/README.md).

## Validation

```sh
mix test test/jido/topology test/examples/07_topology --include example
mix quality
mix test
```

The initial focused suite passed all 33 tests. The 1000-worker example also starts one
coordinator, broadcasts a Signal, checks every committed worker result, and
checks shutdown cleanup. It uses `max_tasks: 4096`. The default task limit of
1000 was insufficient for this simultaneous fan-out. This is an execution
capacity setting, separate from the topology startup concurrency of 32.

`mix quality` passes formatting, compilation with warnings as errors, the
configured Credo command, and Dialyzer. Local links in the new guides and
profiles resolve, and `git diff --check` passes.

The initial full default suite reported four existing acceptance failures:

- Loaded checkpoint identity mismatch.
- A process handle in loaded checkpoint data.
- Admission after an indeterminate persistence write.
- Duplicate ownership across cluster nodes.

The first three are documented in the existing
[persistence boundary report](persistence-boundary-results.md). The fourth is
recorded in the existing [DIST-03 report](dist-03-results.md). The topology
change does not modify those tests or their core runtime implementations.

## Findings

Module restoration rebuilds an Agent from its module definition. It does not
retain topology-added metadata or Bus inputs from a prior definition. The
controller therefore loads saved state and its revision, validates identity,
and adds the current topology configuration before starting the Agent Server.
Temporary Agent children ensure every reactivation uses this path. The tests
check controller restart, Bus subscriptions after restore, a persisted worker
failure, and retained committed state. The adapter test uses ETS; it does not
prove disk or VM durability.

Readiness checks detect dead recorded processes and inspect required Bus
inputs during each repair pass. A Bus restart must not report ready solely
because its replacement process exists. Caller readiness timeouts remove
pending wait records and do not stop the controller.

## Scope

This spike supports one local Jido instance, eager activation, fixed topology
definitions, counted and keyed groups, normal Bus subscriptions, and one
singleton logical parent per Agent or group. A desired member is recreated
after a normal stop. Stop the controller to keep its members stopped.

Database adapters, live definition updates, version migration, cluster
placement, on-demand activation, generated route
interfaces, and durable work distribution remain outside this spike. A Bus
subscription is a broadcast connection. It does not select one worker for a
job. JSON stores definitions; input and committed Agent state remain separate.

## Composition extension

The composition extension adds imports, exports, inclusion input maps, resource
bindings, and nested re-exports in all three authoring forms. It adds one
numbered composed-system example. Codec version 2 stores embedded definitions;
version 1 documents remain readable. One root controller starts and repairs
the complete graph. Startup/check tasks are now asynchronous and time bounded.

The final focused suite passes all 52 tests, including the existing scale
example. New tests check definition/plan equality, private endpoint rejection,
wrong kinds, missing and duplicate bindings, recursive inclusion, nested
re-exports, complete-graph cycles, shared ownership, input isolation, root and
child limits, namespace collisions, global concurrency, blocked startup,
team failure, saved state, and shared subscriptions after restoration.

The final `mix quality` run passes. The full default suite recheck passes
751 of 755 tests, with 244 excluded by the existing test configuration. Its
four failures match the acceptance failures listed above. The first full run
also hit the 100 ms Signal delivery timeout in `ServerContextTest`. That test
passed with all 52 topology tests, and the full suite repeat with the same
seed did not reproduce the timeout. No acceptance test was disabled or changed.

See the [composed example](../../lib/examples/07_topology/07_05_composed_system/README.md).
Inclusion aliases are stable identity components. Instance IDs now escape
separators as well; existing simple IDs are unchanged. An earlier instance ID
containing `/` or `%` needs an explicit saved-identity migration before reuse.
Independent component pause, live replacement, and cluster placement remain
outside the implementation.
