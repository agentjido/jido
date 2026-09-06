# Basic SDK integration tests

Basic tests the smallest combinations of real SDK components. The suite has
five fixtures and 22 tests. Each fixture owns one integration boundary.

| Order | Fixture | Tests | SDK obligation |
| --- | --- | ---: | --- |
| 01_01 | [Minimal Agent](01_01_minimal_agent/minimal_agent_test.exs) | 3 | Direct/live agreement, typed Action input, and instance isolation |
| 01_02 | [Typed Command Agent](01_02_typed_command_agent/typed_command_agent_test.exs) | 4 | Construction, routing, executable input, and complete candidate validation |
| 01_03 | [Plugin State Agent](01_03_plugin_state_agent/plugin_state_agent_test.exs) | 3 | State ownership and atomic domain/Plugin commit |
| 01_04 | [Directive Agent](01_04_directive_agent/directive_agent_test.exs) | 3 | Whole-batch validation and ordered post-commit effects |
| 01_05 | [Controlled Turn Agent](01_05_controlled_turn_agent/controlled_turn_agent_test.exs) | 3 | Serialization, cancellation, queued work, and caller timeout |

Six tests in `authoring_formats_test.exs` compare Spark, map, keyword, Builder,
and JSON construction for every fixture, including both Typed Command routes.
Each form also executes through the real Agent Server.

Run all 22 tests:

```shell
mix test --include example test/examples/01_basic
```

They also run with `mix examples` or `mix test --only example`. All use the
`:example` tag. The normal test command excludes them.

The five implementations live in matching folders under
[`examples/01_basic`](../../../examples/01_basic). Tests import those Agent
modules. They do not define replacement Agents, Actions, or Plugins.

[Shared test support](../../support/basic_sdk_case.ex) starts real Agent Servers
under an isolated Jido instance. The
[Effects Plugin](../../../examples/01_basic/01_04_directive_agent/effects.ex) starts
a real supervised runtime and is shared by four fixtures. Directive Agent also
runs the same cases through `StatelessEffects`, which has no Plugin process.
Each Directive handler reads the committed Agent through `Server.snapshot/1`. No SDK component
is mocked. Invalid candidates and failing effects deliberately test rejection
and failure behavior.

The test observer and execution barriers use local process messages. These are
test controls only. All domain commands use Signals. Observer PIDs stay in
transient test controls and do not enter committed Agent state or Directives.
Typed Command Agent and Controlled Turn Agent supply the observer through
caller context. Their Signal data has no observer PID.

## Acceptance cases

1. Direct and live execution agree on defaults and overrides. A zero increment preserves the Agent but creates one new live commit revision.
2. Instance startup preserves separate identity and state, survives caller exit, and rejects duplicate IDs and invalid options.
3. Defaults and root schema rules survive construction with and without Plugin state.
4. Route defaults merge shallowly before Action validation; direct and live execution agree, invalid overrides fail, and the Action preserves untouched state fields.
5. A successfully executed Action cannot commit an invalid candidate or dispatch its effects.
6. Unknown and ambiguous routes return the same public routing error type through direct and live execution, execute nothing, and permit a later valid command.
7. Domain and Plugin state become visible in one commit, including to an effect handler.
8. An Action cannot overwrite Plugin-owned state or dispatch its otherwise valid effect.
9. Invalid Plugin output rejects the domain candidate and preserves the prior commit.
10. With and without a Plugin process, every Directive handler sees committed state and handlers run in list order.
11. An invalid later Directive prevents the complete commit and all dispatch.
12. A failed second dispatch preserves the commit, reports failure, and stops the batch.
13. Queued work keeps its own caller context and sees the prior Turn's committed state.
14. Cancellation terminates abandoned work, rejects stale cancellation, and preserves queued work without context from the abandoned Turn.
15. A caller timeout ends waiting; the started Turn can still commit once.

Construction covers invalid defaults, counts on either side of the bounds,
and reversed bounds. The suite uses public error, status, child, Plugin-state,
and snapshot APIs. It does not inject private Server or Exec completion messages.

Minimal Agent declares a default increment amount of 1. Typed Command Agent
declares a default profile patch. Signal data overrides defaults with one
top-level merge. A supplied nested patch replaces the complete default patch,
while the Action's later patch operation preserves untouched Agent state.
The cases include empty data, partial nested maps, `false`, invalid values,
`nil`, and non-map Signal data. Invalid input cannot enter the Action, commit
state, or dispatch effects. See [issue #13](https://github.com/mikehostetler/jido_v3/issues/13).

Routing failures use `Jido.Error.RoutingError`. The Typed Command Agent case
compares public error data from direct and live execution. It checks the Signal
target, the reason for a missing route, and the count and targets of ambiguous
routes. Both failures preserve the committed snapshot and dispatch no effects.
See [issue #12](https://github.com/mikehostetler/jido_v3/issues/12).

## Authoring decisions

Use `Jido.start_agent(jido, Agent, opts)` or the generated Jido instance API.
An Agent does not need its own startup wrapper. An omitted ID is generated; a
supplied ID must be a nonempty string. The Server belongs to the instance
supervisor and does not link to the original caller. `Server.start_link/1`
retains normal caller-link behavior.

Each Basic command uses a typed Action. Minimal Agent increments a count in
one Action, and the profile command applies and normalizes its patch in one
Action. These commands do not need a Flow. See the
[dependency probe](../../../docs/examples/inline-step-results.md) for the
dependency pin and compatibility checks. Use inline Step bodies when an
example already needs a Flow.

Basic declares command and Signal helpers with nested `define` entries in
Spark routes. Minimal Agent proves that the generated helper forwards Server
options and preserves result and error tuples. Signal constructors return
tagged results; their bang variants return a Signal directly.

A Directive-only Plugin can omit `child_spec/1`. The Server runs its dispatch
callback in a supervised task and supplies a `nil` runtime reference. Existing
Plugins with a process use that process. Typed validation, commit order,
timeout, and failure contracts apply to both forms.

Direct `cmd/3` returns a candidate and Directives. Its executable can perform
I/O. A failed Turn preserves committed Agent state but does not undo external
work. Applications own external idempotency and recovery. Fixed dependency
responses make the example state transitions repeatable.

## Current result and scope

All 22 tests pass. Agent schema composition preserves root validation
rules when it adds Plugin fields. See [current results](../../../docs/examples/basic-results.md).
The core schema and snapshot regression probes also run in the default suite.

The ten old Basic source folders and their repeated domain tests have been
removed. Their research profiles are kept in
[the archive](../../../docs/examples/archive/basic). Calculator, retry policy,
task-list rules, and local round-robin selection are not separate Basic SDK
acceptance contracts.

Durable recovery, live child groups, scheduled retries, and external services
belong in the later integration groups.
