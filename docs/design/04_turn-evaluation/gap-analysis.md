# Turn evaluation gap analysis

## Scope and owner

This report analyzes only the Turn evaluation seam in Jido core. The seam owns
the command path from one Agent and one Signal to one candidate Agent and one
Directive list. The review covers Turn boundaries, route precedence, executable
selection, evaluation, commit revision stability, and terminal Outcomes.

The implementation under `lib/` is the source of truth for current behavior.
`docs/design/04_turn-evaluation/turn-evaluation.md` is a deferred proposal, not
an implemented contract. Adjacent Agent, Plugin, commit, and Agent Server design
documents are dependencies only where they set a direct input or output contract
for this seam.

This report does not review general Agent authoring, Plugin runtime management,
persistence adapter internals, or Directive implementation details.

## Implemented baseline

The following items are current facts.

1. `Jido.Agent.cmd/3` calls the private `Jido.Agent.Command.Runner`. The Runner
   prepares the command, calls `Jido.Exec.run/4`, finalizes the result, and
   returns `{:ok, agent, directives}` or `{:error, reason}`
   (`lib/jido/agent.ex:458-462`, `lib/jido/agent/command/runner.ex:29-47`).
2. Preparation validates caller context and the Agent. It then runs Plugin
   preparation before it calls `handle_signal/2`. Thus, the effective Signal is
   the Signal that selects the current executable
   (`lib/jido/agent/command/runner.ex:64-80`).
3. The default `handle_signal/2` builds a Router, requires exactly one returned
   target, merges route defaults with Signal data, and creates a validated
   `%Jido.Agent.Turn{}` (`lib/jido/agent.ex:464-477`,
   `lib/jido/agent/command/runner.ex:107-118`,
   `lib/jido/agent/command/runner.ex:178-219`). A custom `handle_signal/2` can
   create a different Turn (`lib/jido/agent/command/runner.ex:221-227`).
4. `%Jido.Agent.Turn{}` is the public prepared input to execution. It contains
   only `executable` and `input`. It accepts an Action, a Flow module, or a Flow
   value (`lib/jido/agent/turn.ex:1-11`, `lib/jido/agent/turn.ex:16-49`).
5. Finalization requires a plain map output. It prevents an executable from
   changing Plugin-owned state, validates Directive ownership, applies Plugin
   state updates in declaration order, and validates the complete Agent state
   through `Agent.transition/2` (`lib/jido/agent/command/runner.ex:120-154`,
   `lib/jido/plugin.ex:238-255`, `lib/jido/plugin.ex:826-875`,
   `lib/jido/agent.ex:439-446`).
6. The live Server creates a stable Turn ID before Plugin admission. Admission
   can run in one supervised task. The Runner then prepares the command and the
   Server starts asynchronous `Jido.Exec` work. Finalization runs in the Server
   after the Exec result arrives (`lib/jido/agent_server.ex:1285-1309`,
   `lib/jido/agent_server.ex:1370-1431`,
   `lib/jido/agent_server.ex:1440-1481`).
7. A live commit calculates `state_version + 1`, persists the candidate first,
   and changes live state only after persistence succeeds. It replies with the
   committed Agent and then starts the Directive actions. A pre-commit failure
   does not change the live Agent or its revision
   (`lib/jido/agent_server.ex:1493-1545`,
   `lib/jido/agent_server.ex:1548-1564`).
8. One live ActiveTurn starts with the source Signal and start revision. It adds
   the effective Signal and execution handle when execution starts. It remains
   active until all Directives stop, or until the Turn fails or is cancelled
   (`lib/jido/agent_server/active_turn.ex:48-83`,
   `lib/jido/agent_server.ex:1647-1764`,
   `lib/jido/agent_server.ex:1853-1875`).
9. The current public Outcome has five stages: `:prepare`, `:execute`,
   `:finalize`, `:commit`, and `:directive`. It contains both complete source and
   effective Signal values, commit revisions, timing, error data, and Directive
   counts (`lib/jido/agent/turn/outcome.ex:1-67`). Its validation requires a
   committed revision to equal the start revision plus one
   (`lib/jido/agent/turn/outcome.ex:109-153`).

## Aligned contracts

The following current behavior agrees with the intent of the seam proposal.

- Direct execution does not commit Server state or dispatch Directives. It
  returns a validated candidate and Directive list. Live execution uses the
  same Runner preparation and finalization functions
  (`lib/jido/agent/command/runner.ex:30-42`,
  `lib/jido/agent_server.ex:1425-1429`,
  `lib/jido/agent_server.ex:1469-1481`).
- One Turn selects one Action or Flow and calls `Jido.Exec` once at the outer
  Agent boundary (`lib/jido/agent/command/runner.ex:32-41`,
  `lib/jido/agent_server.ex:1440-1466`).
- Plugin command preparation is a serial, fail-fast reduce in declaration order
  (`lib/jido/plugin.ex:696-703`). Tests prove the order and first-error stop for
  command preparation and live admission
  (`test/jido/plugin/contract_test.exs:490-516`,
  `test/jido/plugin/ordering_test.exs:198-232`).
- Executable output stays private from Plugin state update callbacks. Each
  current callback receives only its owned state and its owned Directives. The
  executable cannot write Plugin-owned state
  (`lib/jido/plugin.ex:238-251`, `lib/jido/plugin.ex:832-875`).
- Jido validates Directive ownership before a live commit. The Server also
  validates live-only batch rules before it persists the candidate
  (`lib/jido/agent/command/runner.ex:229-260`,
  `lib/jido/agent_server.ex:1485-1490`,
  `lib/jido/agent_server.ex:1639-1645`). Tests prove that invalid Directives do
  not commit (`test/jido/agent_server/directive_execution_test.exs:45-90`).
- The live Server serializes state-changing Turns. It postpones later Signals
  while admission, execution, or Directive work is active
  (`lib/jido/agent_server.ex:795-843`). A test proves sender-order processing
  across a blocked Turn (`test/jido/agent_server/public_api_test.exs:308-330`).
- The stable Turn ID supports targeted cancellation, and the Server rejects a
  stale Turn ID (`lib/jido/agent_server.ex:725-756`). The cancellation test also
  proves that the failed Turn does not commit
  (`test/jido/agent_server/public_api_test.exs:447-484`).
- Commit revision rules are implemented in both the Server and Outcome
  validation. Persistence tests prove that one successful Turn writes revision
  1, and that a revision conflict prevents live state change and Directive
  dispatch (`test/jido/persistence_test.exs:259-279`,
  `test/jido/persistence_test.exs:305-345`).
- Source and effective Signals are distinct current values. A live Plugin test
  proves that Plugin preparation can change the effective Signal while the
  source Signal stays unchanged
  (`test/jido/support/agent_server_runtime_test_fixtures.ex:67-73`,
  `test/jido/agent_server/directive_execution_test.exs:103-117`).

## Gaps

### Missing implementation

These items are proposals that have no complete current implementation.

1. There is no `Jido.Agent.Turn.Evaluator` module and no stage-aware
   `run/3` result. The current private boundary is
   `Jido.Agent.Command.Runner`, and it returns a flat error without the proposed
   evaluator stage or private execution result
   (`docs/design/04_turn-evaluation/turn-evaluation.md:198-219`,
   `lib/jido/agent/command/runner.ex:29-47`).
2. The proposed fixed order, route source Signal first and then prepare Plugins,
   is not implemented. The current Runner prepares Plugins first and routes the
   prepared Signal (`docs/design/04_turn-evaluation/turn-evaluation.md:74-101`,
   `lib/jido/agent/command/runner.ex:64-80`).
3. The proposed private route parameters are not a separate stored value. The
   current default route handler immediately merges route defaults and effective
   Signal data into `Turn.input` (`lib/jido/agent/command/runner.ex:107-118`,
   `lib/jido/agent/command/runner.ex:204-210`).
4. The proposed per-Plugin prepared input Map, bounded Transition, and
   Contribution types do not exist. The current public Plugin boundary uses
   `%Jido.Agent.Command{agent, signal, context}` for preparation and
   `update_state/3` for state composition (`lib/jido/agent/command.ex:1-22`,
   `lib/jido/plugin.ex:67-81`, `lib/jido/plugin.ex:826-875`). As a result, the
   current preparation callback can inspect the complete Agent and caller
   context. It cannot return one isolated Plugin input.
5. The proposed contribution callback can add owned Directives. The current
   `update_state/3` callback can only return its next owned state. It receives
   owned Directives that the executable already returned
   (`docs/design/05_plugins/plugins.md:265-281`,
   `lib/jido/plugin.ex:80-81`, `lib/jido/plugin.ex:832-856`).
6. The proposed single owner-bound evaluation task is not implemented. Current
   live evaluation is split across an optional admission task, an Exec root or
   adapter, and Server-side finalization
   (`docs/design/04_turn-evaluation/turn-evaluation.md:151-168`,
   `lib/jido/agent_server.ex:1370-1431`,
   `lib/jido/agent_server.ex:1469-1490`).
7. The proposed `turn_timeout` for the complete pre-commit evaluation is not a
   Server option. The current `directive_timeout` also controls Plugin admission
   and custom Exec adapter callbacks. Normal `Jido.Exec` execution can exceed
   this timeout (`lib/jido/agent_server/options.ex:8-31`,
   `lib/jido/agent_server.ex:1382-1383`,
   `lib/jido/agent_server.ex:1454-1466`,
   `test/jido/agent_server/runtime_boundary_test.exs:232-259`).

### Design/code conflict

These current contracts conflict with the proposal. A design decision or a code
change is required. Documentation changes alone cannot align both sides.

1. **Routing occurs after Plugin preparation.** A Plugin can change Signal type
   or data before `handle_signal/2`. It can therefore change the selected
   executable and route defaults. The proposal says that selection uses the
   original source Signal and cannot change during the Turn
   (`docs/design/04_turn-evaluation/turn-evaluation.md:88-101`,
   `lib/jido/agent/command/runner.ex:69-80`,
   `lib/jido/plugin.ex:67-68`).
2. **Route precedence has different terminal behavior.** The adjacent Agent
   proposal says that Jido selects the first route by precedence and ignores
   lower matches. Current code rejects every result count other than one. A test
   explicitly requires an exact route plus a wildcard route to fail
   (`docs/design/01_agent/agent.md:95-114`,
   `lib/jido/agent/command/runner.ex:178-188`,
   `test/jido/agent_test.exs:306-316`).
3. **Direct and live validation boundaries are not equal.** Both paths share
   Runner finalization, but only the Server enforces the Directive count,
   terminal-Directive position, and Signal dispatch rules. Therefore a direct
   command can return a candidate and Directive list that the live path rejects
   before commit (`lib/jido/agent/command/runner.ex:120-133`,
   `lib/jido/agent_server.ex:1485-1490`,
   `lib/jido/agent_server.ex:1639-1645`). This conflicts with a strict reading of
   one shared complete evaluator and one final candidate validation.
4. **Fault handling does not have one rule.** `Runner.run/3` catches an exception,
   throw, or exit and returns the raw value. `finish_for_server/2` converts only
   finalization faults to an ExecutionError. Plugin wrappers normalize many
   Plugin callback faults. The proposal instead requires narrow wrappers to
   return defined Splode errors, while an unexpected evaluator invariant must
   crash live execution (`docs/design/04_turn-evaluation/turn-evaluation.md:141-149`,
   `lib/jido/agent/command/runner.ex:32-47`,
   `lib/jido/agent/command/runner.ex:96-105`).
5. **Outcome stages do not match the proposed live control stages.** Current
   Outcomes expose `:prepare`, `:execute`, and `:finalize` as separate stages.
   The adjacent Server proposal exposes one pre-commit `:evaluate` stage
   (`lib/jido/agent/turn/outcome.ex:13-14`,
   `docs/design/08_agent-server/agent-server.md:92-105`,
   `docs/design/08_agent-server/agent-server.md:300-324`).
6. **Outcome payload privacy does not match the adjacent proposal.** Current
   Outcomes contain complete source and effective Signal structs. The adjacent
   Server proposal says an Outcome contains Signal identities and counts, not
   Signal payloads (`lib/jido/agent/turn/outcome.ex:16-35`,
   `docs/design/08_agent-server/agent-server.md:327-331`).

### Missing decision

These points do not have one consistent accepted contract.

1. Decide whether a Plugin can affect route selection. The current public Plugin
   documentation says preparation runs before routing
   (`lib/jido/plugin.ex:13-17`). The Turn, Agent, and Plugin proposals say route
   selection runs first and stays fixed
   (`docs/design/04_turn-evaluation/turn-evaluation.md:88-91`,
   `docs/design/01_agent/agent.md:111-114`,
   `docs/design/05_plugins/plugins.md:339-345`).
2. Decide whether route precedence selects the first match or whether multiple
   matches are an error. This affects exact routes, wildcard fallbacks, route
   priority, and declaration order.
3. Decide the public and internal stage vocabulary. Current code needs five
   Outcome stages. The adjacent design uses three control stages. The proposed
   evaluator also needs more detailed failure stages, but it does not list the
   allowed values for `{:error, stage, error}`.
4. Decide the exact parity promise for direct and live execution. The candidate
   assembly can be shared while Server-only Directive limits and dispatch target
   checks remain live policy. The phrase "same Turn Evaluator" does not state
   where these live-only checks belong.
5. Decide whether live Plugin admission remains outside the pure evaluator. The
   current runtime supports it, while the adjacent Plugin proposal removes it
   (`lib/jido/plugin.ex:71-72`, `docs/design/05_plugins/plugins.md:367-371`).
6. Decide whether an Outcome is an observation value with full Signals or a
   bounded public value with Signal IDs only. Also decide whether an Outcome is
   available through only telemetry and error policy, or through another public
   retrieval boundary.
7. Decide what "revision stability" means during evaluation. Current code
   snapshots `start_version` and commits exactly `start_version + 1`, but the
   proposed evaluator input has no explicit revision. If evaluation can be used
   outside one Server owner, the expected revision must be an explicit input or
   a Server-only invariant.

### Missing verification

These are test gaps. They are not proof that the current code is wrong.

1. No focused test proves the requested source-Signal routing rule. Add a Plugin
   that changes Signal type from route A to route B. Assert that route A remains
   selected and that only its executable input uses the effective Signal.
2. No parity test runs the same fixed Agent, Signal, Plugin configuration, and
   context through direct `cmd/3` and a live Server, then compares the candidate
   and Directive list before live dispatch. Add cases for Action, Flow, Plugin
   state, Plugin failure, invalid output, and Directives.
3. No test proves first-match route precedence across exact, `*`, `**`, complex,
   priority, and declaration-order ties. Current tests prove only single-route
   wildcard behavior and the current multiple-match error
   (`test/jido/agent_test.exs:581-633`).
4. No seam test proves that each proposed Plugin contribution sees only its
   declared state projection, owned Directives, and owned prepared input. The
   proposed callback types do not yet exist.
5. Current tests cover stale admission results and stale cancellation IDs, but
   there is no focused test that injects a late or duplicate successful Exec
   terminal result after cancellation and then starts another Turn. Add the test
   for the default Exec path and the custom ExecutionAdapter path.
6. Outcome constructor tests cover field consistency, and runtime tests cover
   several success, failure, and cancellation cases
   (`test/jido/agent/turn/outcome_test.exs:24-103`,
   `test/jido/agent_server/runtime_observability_test.exs:10-36`,
   `test/jido/agent_server/public_api_test.exs:368-484`). Add one table-driven
   live test for every terminal boundary, including admission timeout, Exec
   timeout, finalization failure, persistence conflict, successful zero-
   Directive commit, Directive failure, cancellation, and indeterminate cancel.
7. Add a revision test for a successful executable that returns state equal to
   the prior state. It must advance the revision once. Add a paired pre-commit
   failure case that proves no revision change.

## Narrow dependency notes

- **Agent seam:** It owns route declaration and precedence. Turn evaluation must
  not define a different multiple-match rule. The current Agent proposal and
  current tests disagree on this point
  (`docs/design/01_agent/agent.md:95-114`,
  `test/jido/agent_test.exs:306-316`).
- **Plugin seam:** It owns the preparation and contribution callback shapes.
  Turn evaluation cannot implement the proposed isolation model until the
  Plugin Command, Context, Transition, and Contribution contracts are accepted
  and implemented (`docs/design/05_plugins/plugins.md:219-291`).
- **Commit and effects seam:** It owns persistence and post-commit Directive
  execution. Its core order agrees with current code: validate, persist, change
  live state, reply, then dispatch (`docs/design/06_commit-and-effects/commit-and-effects.md:11-29`,
  `lib/jido/agent_server.ex:1493-1545`). Turn evaluation should return a complete
  candidate, but it should not own persistence or dispatch.
- **Agent Server seam:** It owns admission, cancellation, timeouts, stable Turn
  identity, revision checks, commit, and Outcome publication. The evaluator must
  return enough private data for these duties, but it must not own process or
  timer state.
- **Jido.Exec:** It remains the Action and Flow execution boundary. The seam must
  support both synchronous direct execution and asynchronous live execution
  without changing Action or Flow result semantics.

## Ordered recommendations

The following items are proposals, in implementation order.

1. Lock the route contract first. Select one rule for source versus effective
   Signal and one rule for multiple route matches. Update the Agent, Plugin, and
   Turn design documents together before runtime work starts.
2. Lock the Turn stage model. Define evaluator failure stages separately from
   Server control stages and public Outcome stages. Provide one explicit mapping
   table.
3. Define the direct/live parity boundary. Put pure candidate and Directive
   validation in the shared evaluator. List each Server-only policy check, such
   as a per-Server Directive count limit, outside that parity contract.
4. Implement the new Plugin callback values and isolation rules before the new
   evaluator. The evaluator depends on these types for prepared inputs,
   Transition projections, and contributions.
5. Add `Jido.Agent.Turn.Evaluator` as a private pure module. Make it own fixed
   route selection, Plugin preparation, input construction, execution-result
   normalization, Plugin composition, and final candidate validation. Keep
   persistence, cancellation, timers, and dispatch in the Server.
6. Refactor direct and live callers to use the evaluator contract. For live
   asynchronous Exec, either make the evaluator support a prepare/resume private
   protocol or run the complete evaluator in one supervised task. Do not claim
   one task until code has this shape.
7. Add a dedicated `turn_timeout` if the accepted design keeps a complete
   evaluation timeout. Do not reuse `directive_timeout` for this contract.
8. Resolve the Outcome shape and stage conflict. Then update Outcome validation,
   telemetry, error policy inputs, status output, and tests as one change.
9. Add the focused verification listed above. Run direct tests first, then live
   Server tests, then persistence and Directive tests because those seams consume
   the evaluator result.

## Evidence references

Primary design evidence:

- `docs/design/04_turn-evaluation/turn-evaluation.md:20-56` — command boundary,
  direct/live sharing, and evaluation return semantics.
- `docs/design/04_turn-evaluation/turn-evaluation.md:58-110` — output privacy,
  fixed ordering, source/effective Signals, and serial Plugin rules.
- `docs/design/04_turn-evaluation/turn-evaluation.md:112-149` — proposed compiled
  evaluator shape and fault rules.
- `docs/design/04_turn-evaluation/turn-evaluation.md:151-227` — live boundary,
  stable identity, revisions, Outcomes, and cancellation.

Primary implementation evidence:

- `lib/jido/agent/command/runner.ex:29-133` — current shared command preparation,
  execution, and finalization.
- `lib/jido/agent/command/runner.ex:178-260` — current exact-one route and
  Directive ownership rules.
- `lib/jido/plugin.ex:67-102`, `lib/jido/plugin.ex:696-703`, and
  `lib/jido/plugin.ex:826-875` — current Plugin callback and serial reduction
  contracts.
- `lib/jido/agent_server.ex:1285-1545` — live Turn start, admission, Exec,
  finalization, persistence, commit, reply, and Directive start.
- `lib/jido/agent_server/active_turn.ex:48-129` and
  `lib/jido/agent/turn/outcome.ex:13-190` — current stable Turn identity and
  Outcome invariants.

Primary test evidence:

- `test/jido/agent_test.exs:292-316` and `test/jido/agent_test.exs:581-646` —
  current route selection, route input, and ambiguity behavior.
- `test/jido/plugin/contract_test.exs:490-563` — current Plugin preparation,
  command rejection, state validation, and direct Directive validation.
- `test/jido/agent_server/context_test.exs:227-272` — context flow, source and
  effective Signal use, Plugin state composition, and live revision.
- `test/jido/agent_server/directive_execution_test.exs:27-117` — commit before
  follow-up work and pre-commit Directive checks.
- `test/jido/persistence_test.exs:259-345` — persisted revision and stale-writer
  conflict behavior.
