> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../migration/10-execution-record.md) for the migration result.

# DIST-01: remote owned children

Date: **2026-09-04**. Status: **Implemented after core contract agreement**.

```elixir
Directive.spawn_agent(Worker, :worker, node: target_node)
```

Omitted placement remains local. An explicit node must run the same named Jido
instance and matching Agent code. The old diagnostic `opts.node` form is now
rejected. The [research Agent](../../lib/examples/05_multi_agent/05_05_remote_child/remote_child.ex)
uses the supported first-class field.

## Behavior and evidence

The [core runtime tests](../../test/jido/agent/distributed_child_test.exs) run on
two real Erlang VMs. [Pure tests](../../test/jido/agent/child_placement_test.exs)
check construction, validation, and Agent evaluation without dispatch.

| Capability | Proof |
| --- | --- |
| Explicit placement | The child PID and supervisor belong to node B; the parent and its registry remain on A. |
| Signal exchange | EmitToChild starts work on B; EmitToParent carries a request ID and result back to A. Both Agents commit independently. |
| Execution ownership | A held Action has a distinct task PID on B. Parent shutdown and parent death remove both task and child. |
| Restart and stop | A remote restart retains committed state and updates the parent's tracked PID. Explicit stop removes a permanent child. |
| Validation and failure | Invalid placement, a missing module, a missing instance, an unavailable node, duplicate tags, and an unrelated child ID do not create a local fallback. |
| Delayed startup | A controlled supervisor barrier forces a timeout. Retries retain one request identity; a changed target is rejected while the request is unresolved. |
| Late result and cleanup | The late child-online event resolves one child. Parent loss before startup leaves no remote child. |
| Closed requests | Replaying an old request cannot recreate a stopped child, including after a SpawnRegistry process restart or a newer generation. A closed reply clears a pending start so a new generation can proceed. |
| Connection loss | The parent remains alive while distribution is disconnected. Closed request records survive reconnect and reject replay. This is a focused connection test, not a full partition/recovery guarantee. |

The tests use the [peer case](../../test/support/peer_case.ex). Peer calls use
standard IO for test control; Agent communication uses the distribution
connection. Cleanup runs after failed assertions as well as successful tests.

```shell
mix test test/jido/agent/distributed_child_test.exs test/jido/agent/child_placement_test.exs --seed 0
mix run lib/examples/05_multi_agent/05_05_remote_child/demo.exs
```

The original two-node test had one pass and one failure: SpawnAgent created the
child locally. That failure is now resolved. No acceptance assertion was removed
or skipped to add remote placement. The current node-targeting tests have
**16 passes and no skips**.

## Startup and completion

The parent's `directive_timeout` bounds the remote call (5 seconds by default).
A timeout or lost connection can leave startup unresolved. Core reports a
structured `child_spawn_indeterminate` error and an `:indeterminate` Outcome.
The earlier Agent state commit remains valid. A command reply confirms that
commit; it does not confirm completion of subsequent Directives.

Pending identities are visible in `Server.status/1` under
`runtime.pending_child_spawns`. The same request can be retried. A late verified
child-online notification resolves it. A changed request or stop cannot silently
discard an unresolved start. Stopping the parent activation prevents delayed
startup from leaving owned work behind.
If a late child stops before the parent tracks it, a retry receives
`spawn_request_closed`. This clears the pending request and permits a new spawn.

The target keeps the newest generation for each parent activation/tag in an
instance-owned SpawnRegistry. A stopped generation stays closed. This record
survives registry process restart and is removed after confirmed parent death.
Connection loss does not establish parent death. Records are runtime data, not
a durable distributed authority across loss of the Jido instance or VM.

## Validation and limits

| Check | Result |
| --- | --- |
| Pure and two-node core acceptance tests | 16 passed; no skips |
| Basic through Multi-agent | 170 passed; no skips |
| Retained legacy research tests | 69 passed; 34 historical skips |
| Standalone two-node example | Passed; exit 0 |
| `mix quality` | Passed; no application compile warnings or Dialyzer findings |
| `mix docs --no-open`, local links, Git whitespace | Passed |

Basic through Multi-agent still pass **170 tests, with no skips**. The earlier
focused Agent/runtime/instance regression run had **109 passes and one failure**.
The failing hibernate/thaw test also fails in an isolated checkout of unchanged
HEAD: thaw sees the old PID still registered. This is recorded as QA-HIBERNATE
in the [gap register](runtime-multi-agent-gaps.md), separate from node placement.

The [core contract](../design/remote-owned-children.md) defines supported behavior
and boundaries. Automatic failover, sharding, durable identity, leases, and
recovery authority remain later work. Adoption and generic cross-node Agent
lookup are not newly supported by this change. DIST-02 still needs its complete
node-loss, partition, and reconnect matrix; DIST-03 needs authority after
instance or node replacement.

Validation used Elixir 1.20.3 and OTP 29. The Elixir 1.18 / OTP 27 release
baseline still needs a separate run. No live vendor service was required.
No full-suite green result is claimed; QA-HIBERNATE and the previously recorded
group/context failures remain separate work.
