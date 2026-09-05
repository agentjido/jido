> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../migration/10-execution-record.md) for the migration result.

# Basic SDK integration results

Latest run: **2026-09-04**.

Workflow examples named in this historical Basic report have since been
replaced by nine SDK fixtures. See the [current Workflow results](workflow-results.md)
for the new names and the preserved context, persistence, and approval checks.

The Basic suite now has **five fixtures and 22 integration tests**. It
replaces the ten domain-example groups in both `lib/examples/01_basic` and
`test/examples/01_basic`. Both folders now contain the same five fixtures. Tests
use the source Agent modules. The old research profiles are kept in
[the archive](archive/basic); their source folders were removed.

Run the suite:

```shell
mix test --include integration test/examples/01_basic
```

The tests also run in `mix examples` and `mix test --only integration`. There
are no skipped Basic cases or separate exclusion tags for failed obligations.

| Fixture | Passed | Failed | Obligation |
| --- | ---: | ---: | --- |
| Minimal Agent | 3 | 0 | Direct/live agreement, typed Action input, and isolated instances |
| Typed Command Agent | 4 | 0 | Construction, routing, executable input, and candidate validation |
| Plugin State Agent | 3 | 0 | State ownership and atomic composition |
| Directive Agent | 3 | 0 | Whole-batch validation and ordered post-commit effects |
| Controlled Turn Agent | 3 | 0 | Serialization, cancellation, queued work, and caller timeout |
| Authoring parity | 6 | 0 | All five fixtures across authoring forms and both Typed Command routes |
| Total | 22 | 0 | 22 enabled integration tests |

See the [suite and acceptance cases](../../test/examples/01_basic/README.md).

## Hex beta compatibility

The examples use `jido_action` 3.0.0-beta.6 from Hex. Minimal Agent declares
its small typed Action in the route and does not use a Flow. The compiled route
target still works through direct Agent commands, live helpers, Builder, and
Codec forms. The other Basic Actions remain named because they are larger,
have several routes, or define a distinct state and effect policy.

All 22 Basic tests pass. Input validation, state ownership, ordered Directives,
cancellation, and one commit per command remain covered. See the
[beta.6 adoption report](inline-actions-expressions-results.md).

## Syntax review changes

The approved syntax changes are implemented:

- Agent route inputs use `defaults` in Spark, Builder, direct route options,
  and Codec records. Flow step `params` is unchanged.
- Plugin declarations reject `as:`. The module identifies each Plugin.
- Generated documentation shows named inputs, optional call forms, options,
  return values, validation timing, and caller timeout behavior. Generated
  specs identify Signal and Agent results while keeping raw input types broad.

Verification on 2026-09-04:

- Combined Basic, authoring, and core Agent run: **93 passed** with seed 0.
  This includes all **20 Basic tests** and **22 authoring tests**.
- Default suite: **596 passed**, 248 excluded by existing tags.
- Formatting, compilation with warnings as errors, and Credo: passed.
- Documentation build: passed without documentation warnings.
- README example: passed through the live Agent Server and returned count 2.
- Dialyzer reports the same six existing findings listed below. No new
  finding was added.

The four new tests check compiled help and specs, argument names that could
conflict with helper parameters, and rejection of removed syntax. Existing
tests still prove omission, explicit values, shallow defaults, Plugin input
preparation, and construction parity.

## Initial Spark authoring verification

All five fixtures use Spark `agent` and `routes` blocks with nested `define`
entries. The original fifteen contract tests remain enabled. Five new parity
tests reconstruct each fixture through every authoring form and compare direct
execution with generated live calls through real Agent Servers.

- Basic suite: 20 passed, with no skipped cases.
- Authoring suite: 18 passed. This includes recompilation with a changed Action
  schema, Plugin preparation, route predicates, malformed route lists, and
  optional list arguments.
- Combined Basic, authoring, and core Agent run: 89 passed with seed 0.
- `mix test --cover --seed 703085`: 592 passed, 248 excluded by existing tags.
  Overall coverage is 54.4%, compared with 51.3% in a copy without this change.
  Coverage remains below the configured 80% target; the command exits with
  status 0. Opt-in examples remain part of the reported source coverage.
- Formatting, compilation with warnings as errors, and Credo: passed.
- `mix docs --no-open`: passed without documentation warnings.
- The README example ran through the live Agent Server and returned count 2.

The full coverage run exposed a race in an existing Server test. The test
created a child and then attached a monitor, so the child could exit first.
It now uses `spawn_monitor/1` to make both operations atomic. The original
normal-exit assertion is unchanged, and the same test seed passes.

`mix quality` still exits with status 2 because Dialyzer reports six existing
findings. The same six findings occur in an isolated copy with the DSL,
Builder, Codec, and Basic conversion removed. That copy retains the other
workspace changes. No new Dialyzer finding was added.

| Existing finding | Location |
| --- | --- |
| Covered fallback clause | `lib/jido/agent/command/runner.ex:250` |
| Unreachable `:ignore` pattern | `lib/jido/agent_server/plugin_child.ex:50` |
| Unreachable two-element result tuple | `lib/jido/persistence.ex:300` |
| Covered fallback clause | `lib/jido/persistence.ex:303` |
| Unreachable `false` pattern | `lib/jido/plugin.ex:1` |
| Unreachable `nil` pattern | `lib/jido/plugin/scheduler/runtime.ex:233` |

See the [implemented authoring contract](../design/agent-dsl-interfaces.md).
The verification entries below record earlier SDK runs.

## Earlier verification

- Route defaults and routing errors: the updated cases failed under the previous
  contracts, then passed with Signal precedence and error normalization. The focused command
  `mix test --include integration test/jido/agent_test.exs test/examples/01_basic --seed 0`
  passed all 66 tests.
- `mix test --include integration test/examples/01_basic --seed 0`: 15 passed.
- `mix test --include example --seed 0`: 753 passed, 36 skipped, 11 excluded.
  This combines 574 core tests and 179 example tests. The command excludes the
  11 separately tagged advanced integration tests. Basic is included.
- `mix format --check-formatted` and `mix compile --warnings-as-errors`: passed.
  The test run still reports existing type warnings from negative-input tests.
- `mix docs`: passed. Removed stale extra-file entries for missing guides;
  Plugin API docs remain available.
- The additional run with `--include integration` had 762 passed, 36 skipped,
  and two failures in the advanced Fixed Group and Elastic Group tests. Both
  failures recur at the same assertions when the changed SDK modules are loaded
  from committed HEAD in a separate test VM. These existing failures are outside
  Basic; no advanced group test was changed or newly skipped.
- Local Markdown links and source/test folder names: checked.
- The default suite includes the core schema and snapshot regression tests.
  Run these alone with `mix test --only basic_contract`.
- Basic has exactly five source folders, five matching test folders, and fifteen
  tests. Source modules have no dependency on `JidoTest`.
- The detached worktree is clean and has the same HEAD as the main checkout.
  All changes are already in the main folder; there is no separate commit to merge.

## Remaining Basic issue group

Issues #3, #9, #10, and #17 now use one authoring contract:

- Direct evaluation returns a candidate. The Server commits complete state.
  Executables can perform synchronous I/O; failure does not undo completed
  external work. Applications own idempotency and recovery.
- Startup uses `MyApp.Jido.start_agent/2` or `Jido.start_agent/3`. The Agent links
  to the instance supervisor. The caller can exit without stopping it.
- IDs are generated when omitted. Supplied IDs must be nonempty strings.
  Startup now rejects numeric IDs instead of converting them to strings.
  Malformed options return a structured error. A duplicate live ID does not
  replace the existing Agent.
- Ninety mechanical example startup wrappers were removed. The shared example
  runner uses the instance API directly. Explicit domain command and Signal
  helpers remain; no new macro or command DSL was added.
- Typed Plugin Directive dispatch no longer requires `child_spec/1`. Without a
  Plugin process, `dispatch/4` receives `nil` and runs in the Server-owned task.
  A declared process must still be available. Transient Turn context is supplied
  to the callback and is not added to the Directive or Agent state.

Minimal Agent tests generated IDs, caller exit, duplicate startup, malformed
options, and command-helper result/error behavior within its existing two tests.
Directive Agent runs its same three cases with and without a Plugin process.
Both forms preserve complete batch validation, dispatch order, and failure
semantics. The observer only records results; all SDK components are real.

Core tests cover caller links from `Server.start_link/1`, dispatch timeout,
dispatch task death, and a result Signal that commits in a later Turn. Flight
Booking removes its extra runtime module and uses transient booking-adapter
context. Its Directive contains only the request and idempotency key.

The focused group run passed all 47 tests. Basic remains five fixtures and
fifteen tests. Design documents remain `Pending approval` as required by
`docs/design/AGENTS.md`; this records document review status and does not block
the implemented SDK changes.

Issue #4 remains a separate shared-executable follow-up in `jido_action`.
Named-function targets are not implemented in this cleanup. Existing typed
Actions and Flows remain the executable contract.

## Caller context and commit revisions

[Issue #11](https://github.com/mikehostetler/jido_v3/issues/11) adds
`Server.call(server, signal, context: %{...}, timeout: 5_000)`. The numeric timeout
form still works. Typed Command Agent now supplies its observer in caller
context for direct and live execution. Controlled Turn Agent uses context for
its observer and proves that queued calls retain separate context. A cancelled
Turn does not supply its context to the next Turn. The timeout case uses both
options and still allows the started Turn to commit.

[Issue #15](https://github.com/mikehostetler/jido_v3/issues/15) defines
`state_version` as the commit revision. Minimal Agent now includes an increment
of zero: the Agent remains equal, but a live successful Turn advances the
revision once. These checks extend the existing fifteen Basic tests.

The wider examples provide the persistence and adapter proof:

- Effectful Weather Lookup uses transient client context, compares direct and
  live results, checks context isolation, and restores the portable commit.
- Persistent Counter Recovery checks a duplicate's identical Agent, reads the
  newly stored revision before hibernation, and restores that revision again.
  Invalid input preserves both state and stored revision.
- Core tests cover context validation, reserved keys, legacy timeout calls,
  asynchronous requests, Plugin admission and preparation, and outbound Signals.
  Context remains available to post-commit Plugin work but is not copied to
  Plugin state or emitted Signal data.

The focused context and revision run passed 52 tests, with one existing skipped
stale-writer case. Basic still has five fixtures and fifteen passing tests.

That was the earlier context review. The later
[persistence fix](persistence-write-results.md) enables the stale-writer test;
the [current catalog](catalog.md) contains the latest group counts.

## Routing error contract

Issue [#12](https://github.com/mikehostetler/jido_v3/issues/12) now has one public
Agent command error type: `Jido.Error.RoutingError`. Command preparation wraps
Signal routing errors and preserves the message, details, retry hints, and
original error in `details.cause`. An existing Jido routing error is preserved.

Typed Command Agent checks unknown and ambiguous routes through direct and live
execution. Both return the same public error data and retain useful route
details. Neither failure enters an Action, commits state, or dispatches effects.
A later valid command commits successfully. Core tests also cover invalid
route definitions, invalid Signal types, custom routing callbacks, and
preservation of retry hints.

## Route input defaults

Issue [#13](https://github.com/mikehostetler/jido_v3/issues/13) now uses one rule:
`{executable, defaults}` prepares input with `Map.merge(defaults, signal.data)`.
Signal data takes precedence. The merge is shallow, and the executable validates
the combined input. Invalid supplied values do not fall back to route defaults.
The original Signal remains available in execution context.

Minimal Agent tests an empty Signal data map and an overriding amount through
direct evaluation and a live Server. Typed Command Agent tests default patches,
nested-map replacement, `false`, invalid values, `nil`, and non-map Signal data.
It checks that invalid input causes no Action entry, state commit, or effect.
These cases extend the existing tests; Basic still has five fixtures and fifteen
tests. Core tests also verify default-only keys and the unchanged Signal context.

This changes the prior complete-replacement behavior. Route maps now supply
defaults that a caller can override. Fixed behavior belongs in an Action or
an explicit `handle_signal/2` implementation.

## Agent schema fix

Agent schema composition previously used the whole result from `Zoi.extend/2`.
The installed Zoi version builds a new object and drops root refinement metadata.
This allowed invalid construction and invalid Action results to pass validation.

`Jido.Plugin.compose_schema/2` now takes the normalized fields from the extended
object and preserves the original Agent schema and its root metadata. Thus,
required Plugin fields keep their normal behavior, and root validation applies
with and without Plugin state.

The Basic tests now reject invalid defaults, out-of-range counts, reversed
bounds, and invalid complete candidates. A rejected candidate produces a
structured error, leaves the committed snapshot unchanged, and dispatches no
Directive. The Action does not repeat the schema's bound check.

The older core schema probe also used `:validate`, which the installed Zoi
version reserves for its internal validation signature. Its callback now uses
`:within_bound`, and its construction test checks valid input as well as invalid
input. These probes run in the default suite.

## Test timing fixes

The wider run exposed two existing test setup races. The overload test now waits
for Server readiness before it submits work with a zero queue limit. The failed
delivery test uses `spawn_monitor/1` to establish the monitor before the target
can exit. The runtime notification test now allows one second for delivery
instead of the default 100 ms under concurrent test load.

The previously observed Burst Buncher race also has a dispatch barrier. The test
waits for the replacement timer to be installed before it fires that timer.
These changes preserve the existing assertions and use no fixed sleeps.

## Integration evidence

- Minimal Agent uses its source definition, instance API, Signal Router,
  route input defaults, Action execution, registry, and Server commit.
- Typed Command Agent combines input schemas, route defaults, a shallow input
  merge, a nested state patch, final candidate validation, and effect suppression.
  Unknown and ambiguous routes use one public routing error type through direct
  and live execution.
- Plugin State Agent commits domain and Plugin state together. A real effect
  handler observes the complete snapshot. An Action overwrite or invalid Plugin
  contribution rejects the entire candidate.
- Directive Agent validates the entire batch before commit. A real supervised
  Plugin runtime records list order and reads the committed snapshot. Failure
  of the second dispatch keeps the commit, reports the outcome, and prevents
  the third dispatch.
- Controlled Turn Agent uses barriers and monitored execution. Queued commands
  see prior commits. Cancellation stops the abandoned task, rejects a stale
  Turn ID, and preserves valid queued work. A caller timeout does not cancel
  an already started Turn.

All SDK components are real. The shared observer and barriers control only
local test timing and observations. No live service, persistence recovery, or
private Server message is required. Agent state and Directives contain no test
observer PID.

## Scope changes

The old Basic tests mostly repeated successful state updates or domain
rejections. The ten old source folders and their tests have been replaced by
the five SDK fixtures. The catalog now has 95 current source profiles and ten
archived Basic research profiles.

Calculator, conversation history, task-list policy, toggles, retry budgets, and
local round-robin selection are not separate Basic SDK obligations. Runtime
recovery, scheduled retry delivery, live child groups, and external services
remain work for later groups. The 36 skipped cases in the wider example suite
are outside Basic; this rebuild does not claim to implement them.
