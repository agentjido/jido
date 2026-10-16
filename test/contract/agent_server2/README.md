# AgentServer2 contract tests

This folder protects only the implemented `Jido.AgentServer2` API.
It does not test or replace the existing `Jido.AgentServer` suite.

Run from `jido`:

```sh
mix test test/contract/agent_server2 --seed 0
mix test.contract
```

The first command runs these 231 tests. The second runs the complete Covenant
passing-test gate, including the existing Agent and Topology contracts.
Covenant already discovers this folder through `test/contract`; no new test
alias or runtime dependency is required.

## Layout

- `startup_test.exs`: instance, Runner, options, configuration, and input checks.
- `requests_test.exs`: reads, state commits, replies, casts, context, and admission.
- `lifecycle_test.exs`: timeout, cancellation, ownership loss, cleanup, and races.
- `ownership_test.exs`: execution startup and delayed-timer scheduling checks.
- `logging_test.exs`: raw input and error values stay out of runtime failure logs.
- `policies_test.exs`: execution options, retries, hooks, failure decisions, and error Signals.
- `observation_test.exs`: terminal outcomes, telemetry, trace context, and bounded history.
- `integration_test.exs`: supervision, names, instance defaults and ownership, and ordered effects.
- `commit_plugins_test.exs`: ordered commit hooks, separate hook budgets, Plugin directive ownership, committed context, and callback cleanup.
- `plugins_test.exs`: Signal destinations, control directives, Plugin tree ownership, readiness, and ordered live admission.
- `activations_test.exs`: root versus worker identity, recovery, owned and independent children, adoption, startup races, monitor release, and coexistence.
- `activation_races_test.exs`: startup lookup failure, recovery cleanup barriers and budgets, required-root ownership, orphan dispatch, uncertain ancestry, bare-worker rejection, and lost adoption cleanup.
- `recovery_test.exs`: stable Ref routing, incumbent compatibility, local checkpoint validation, Plugin reconstruction, both commit crash windows, and local record lifetime.
- `persistence_test.exs`: required durable saves, separate deadlines, fault shutdown, explicit create/restore, Plugin conversion/reconstruction, crash windows, and portable data.
- `control_test.exs`: closed admission, bounded quiesce/resume, queued request rejection, callback safety, attached owners, idle expiry, confirmed hibernation, failed/uncertain saves, and control recovery.
- `support.ex`: suite-only Actions, Flow, Plugin barriers, and process checks.

Each test uses `JidoTest.Case` for instance isolation. Standalone checks use a
separate temporary Runner. Instance checks use the instance Runner. Coexistence checks start the existing AgentServer; all other fixtures use AgentServer2. Runtime implementation
stays in `lib/jido/agent_server2.ex`. Test support is loaded only with this
suite, not added to the package compilation paths.

Message barriers and process monitors control work completion. Short timer
waits test actual deadline expiry; they do not stand in for work completion.
Bounded asynchronous checks use `JidoTest.Eventually`.

The startup race tests temporarily use one online scheduler and a high-priority
tracer to hold execution admission or the activation-start reply. They restore
scheduler and tracing settings after each test. The Plugin cleanup test also uses one scheduler and
process priorities to keep kill delivery pending until cleanup waits. It checks
that an owned ETS resource is gone when the public stop call returns. It restores
the caller priority and scheduler setting on success or failure.

These tests run synchronously. Some tests read private state only to check the
built-in default without a 60-second wait or to control cleanup scheduling.
Private process and task records are not public contracts.

## Obligations and mutation checks

Read [the 94 obligations](../../contracts/jido/agent_server2.obligations.md),
[scope decisions](../../contracts/jido/agent_server2.decisions.yml), and
[the mutation baseline](../../contracts/jido/agent_server2.baseline.md).
The component is `jido.agent_server2`; its mutation targets are
`Jido.AgentServer2` and its nested `Activation` supervisor. Existing Agent, Topology, AgentServer, and dependencies
are not mutation targets. Required-root replacement is covered. Durable state recovery is covered. Distributed behavior remains outside this contract. Runtime tree helpers remain in the same source file.

Passing-test obligation coverage and mutation coverage are different checks.
The B1 focused profile also selects `Jido.Instance.RefFacade` with an explicit
module override to check shared runtime dispatch. It does not mutate AgentServer.
The focused mutation result does not establish a full component score.

## Rename later

Keep this folder and its fixtures together. To rename the prototype:

1. Rename this folder and the `JidoTest.AgentServer2` test namespace.
2. Rename the runtime module/file and update its test aliases, Jido wrappers,
   and Ref facade dispatch references. Keep the shared facade and incumbent names.
3. Rename `test/contracts/jido/agent_server2.*`, its component IDs, and test tags.
4. Update the scoped support-file ignore path in `mix.exs` and these commands.
5. Make a new mutation catalog and baseline; old IDs depend on the source.

There are no additional AgentServer2 runtime files or incumbent test fixtures
to rename. Shared Jido and Ref facade modules keep their names.

## Activation ownership

`Server.child_spec(opts)` returns a supervisor specification. OTP receives the
root PID; `Server.start(opts)` returns the worker. For standalone supervision,
`Server.Activation.start_link(opts)` returns `{:ok, root}`. Use
`Server.Activation.worker(root)` to find the worker and a trapping OTP owner for
a linked supervisor. `Server.activation(worker)` returns its root.
`Server.start_link(opts)` remains the bare-worker API and rejects runtime Plugins and persistence.
Use the activation path for normal operation, with or without Plugins.

Worker lookup queries the supervisor and can wait for a bounded Plugin start.
If instance start or child spawn cannot resolve a live worker, it stops the new
root and returns `{:error, :worker_unavailable}`. Failed child starts release
their tag reservations.

All declared Plugin roots are required resources in one `:one_for_all` group.
Plugin supervisors can recover their internal children locally. Recovery restores the last published canonical Agent and revision before
Plugin initialization, then refreshes readiness and references. Publication uses
one atomic expected-revision replacement before success. Failed, cancelled,
and timed-out turns do not change it. The owned-child DynamicSupervisor starts empty after
group recovery. Runtime relationships survive worker recovery in one
supervisor-owned ETS table. Memory-only activation replacement uses startup arguments. Opt-in durable
restore recovers saved commits under B2. Neither mode restores later adoption
or saved child relationships; that remains B5.
Local checkpoints preserve schema-permitted local values without portable
serialization callbacks. Runtime context and handles are not checkpointed.
Crashes do not replay turns, hooks, or directives.

`spawn_child(parent, instance, tag)` defaults to `placement: :owned`.
Independent placement requires an instance and accepts `on_parent_exit: :stop`,
`:continue`, or `:emit_orphan`. The last needs `orphan_dispatch:` and emits
`jido.agent_server2.orphaned`. Parent loss means activation loss. `children/1`
returns current worker and root PIDs. `stop_child/3` stops the complete root.
`adopt_child/4` attaches an independent orphan within one instance and partition.

Normal OTP start functions must return within a bounded time. Put long work in
readiness. Admission closes at the readiness deadline; cleanup waits for a start
already executing in the supervisor to settle. Arbitrary never-returning start
functions are outside this contract. No process-link traversal remains.

Use `Server.stop/3` or `Jido.stop_agent_ref/4` for activation cleanup.
`Jido.stop_agent` is not an activation lifecycle API. The existing AgentServer implementation stays intact.

## Stable local Refs

An instance must have a stable namespace. Create one Ref and use it after worker
recovery. Each operation resolves the current worker; there is no automatic
retry. Caller timeout does not cancel accepted work.

```elixir
{:ok, ref} = Jido.agent_ref(MyJido, agent.id, partition: "tenant")
{:ok, committed, directives} = Jido.call(MyJido, ref, signal)
pending = Jido.submit(MyJido, ref, signal)
{:ok, next_agent, next_directives} = Jido.await(pending)
agent = Jido.agent(MyJido, ref)
revision = Jido.status(MyJido, ref).state_version
:ok = Jido.stop_agent_ref(MyJido, ref)
```

`use Jido` instances also expose `submit`, `await`, and `abandon`. Pending handles
remain owned by the submitting process. Missing or dead registration returns
`:not_found`; a registered starting AgentServer2 returns `:recovering`; Registry
loss or synchronous operation loss returns `:unavailable`. These are error
tuples. Best-effort casts and submissions can still race with worker loss.
A caller can lose a reply after commit and must not assume that an error means
no commit occurred. Unsupported operations return
`{:error, {:unsupported_runtime_operation, operation}}`. Incumbent Ref calls keep
their original results. Existing AgentServer2 calls return three-element success.

## Benchmark and load checks

```sh
mix run --no-start agent_server2_demo.exs
mix run --no-start agent_server2_load.exs 10 1000 10000
mix run --no-start test/bench/run.exs --profile agent_server2 --output tmp/agent-server2-activation/bench
mix test test/bench/core_bench_test.exs --include bench --seed 0
mix test test/system/runtime/agent_server2_load_test.exs --include system --seed 0
```

The load script runs each size twice with half the Agents using Plugins. The
Plugin shapes include process-free admission, one worker, and supervisor trees
of different widths. It checks startup, transient caller input release, turns,
worker recovery, full shutdown, Registry and Runner cleanup, and no new live processes or ETS tables after cleanup. Counts can decrease when
pre-existing VM work ends. Results go to `tmp/agent-server2-activation/`.
VM memory is a local measurement, not a production capacity guarantee. The
small benchmark profile traces standalone activation startup from its caller;
the load profile checks the instance DynamicSupervisor path.

## Durable runtime options

Use a stable Jido instance namespace. Persistence is disabled by default. Set
`persistence: adapter` or `:inherit`, `persistence_mode: :create` or `:restore`,
and a finite `persistence_timeout:` (default 5,000 ms). Create must save revision
zero before readiness. Restore has no missing-record fallback. Persistent worker
recovery reloads storage. Storage failure or uncertain required writes stop the
activation without success or post-commit effects. `:saving` permits reads and
queues new turns; cancellation returns `:commit_in_progress`. Caller wait does
not cancel save. Existing checkpoint callbacks own portable conversion.

Run the demo with `mix run --no-start agent_server2_demo.exs`. Run the two-cycle
load check with `mix run --no-start agent_server2_load.exs --persistent 10 1000`.
That check separates intentionally saved ETS records from process cleanup and
removes the records before comparing resource baselines. ETS is not disk storage.
