# Errors and public contracts gap analysis

> Analysis of the current `v3-spike` implementation against the deferred
> proposal in `errors.md`. This report states current facts first. It does not
> make the proposal part of the current public API.

## Scope and owner

This seam owns the public Jido error taxonomy, stable program codes, boundary
normalization, safe failure projection, and the recursive portable-term rule.
It also owns the rule for raw protocol control values at public result
positions.

The review covers these direct boundaries:

- `Jido.Error` definitions and projection
- Agent construction, validation, command, checkpoint, and restore results
- Agent Server command and lifecycle results
- Plugin callback fault and return normalization
- Persistence adapter controls and public persistence results
- Telemetry failure projection
- Portable Agent and Plugin state at validation and persistence boundaries

The review does not evaluate the full Agent, Plugin, persistence, Agent Server,
or observability design. Code under `lib` is the source of truth for implemented
behavior. Tests and public module documentation show which parts of that
behavior are intentional and verified.

## Implemented baseline

These items are current facts.

1. `Jido.Error` uses Splode. It defines five Splode classes: `invalid`,
   `execution`, `routing`, `timeout`, and `internal`. It defines six public
   error structs: `ValidationError`, `ExecutionError`, `RoutingError`,
   `TimeoutError`, `CompensationError`, and `InternalError`. Compensation uses
   the `execution` class. See `lib/jido/error.ex:47-107` and
   `lib/jido/error.ex:113-318`.

2. Current errors do not have a common `code` field. The public projection uses
   a derived `type` atom instead. Its known values include
   `validation_error`, `invalid_action`, `config_error`, `planning_error`,
   `execution_error`, `routing_error`, `timeout`, `compensation_error`, and
   `internal`. See `lib/jido/error.ex:484-499` and
   `lib/jido/error.ex:858-895`.

3. `Jido.Error.to_map/1` accepts any term. It returns exactly `type`, `message`,
   `details`, and `retryable?`. It bounds map and list items, nesting, and
   strings. It redacts sensitive keys and omits stacktrace keys. See
   `lib/jido/error.ex:479-535` and `lib/jido/error.ex:656-803`.

4. Agent validation uses `ValidationError` for many invalid definitions,
   schemas, states, and options. Agent state is parsed with the complete Zoi
   schema. This validation does not apply `Jido.PortableTerm.valid?/1`. See
   `lib/jido/agent/state.ex:23-75` and `lib/jido/agent.ex:439-446`.

5. Direct Agent execution normalizes some failures. Routing failures from
   `Jido.Signal` become `Jido.Error.RoutingError`. Invalid executable results,
   invalid state output, invalid Directives, and invalid `handle_signal/2`
   results become defined Jido errors. Returned callback errors pass through
   unchanged. A raise passes through as its original exception, and a throw or
   exit becomes a raw tuple. See `lib/jido/agent/command/runner.ex:29-47`,
   `lib/jido/agent/command/runner.ex:91-117`, and
   `lib/jido/agent/command/runner.ex:136-153`.

6. Plugin wrappers convert callback raises, throws, exits, and invalid results
   into `ExecutionError` for many Plugin callbacks. However, a callback result
   of `{:error, reason}` usually passes through unchanged. Public Plugin callback
   specifications use `term()` for the error position. See
   `lib/jido/plugin.ex:67-91`, `lib/jido/plugin.ex:438-460`,
   `lib/jido/plugin.ex:705-795`, and `lib/jido/plugin.ex:962-978`.

7. Agent Server command and lifecycle functions use broad `term()` error
   specifications. Current replies include raw atoms and tuples for admission,
   reentry, cancellation, readiness, hibernation, debug state, overload, and
   persistence. See `lib/jido/agent_server.ex:158-190`,
   `lib/jido/agent_server.ex:236-290`, `lib/jido/agent_server.ex:334-418`,
   `lib/jido/agent_server.ex:567-575`, `lib/jido/agent_server.ex:668-785`, and
   `lib/jido/agent_server.ex:801-836`.

8. The persistence adapter has fixed meanings for `:not_found`, `:conflict`,
   and `:indeterminate`. Public `Jido.Persistence` functions return raw adapter
   controls and other raw tuples. Adapter exceptions and invalid results become
   `ExecutionError`, not `PersistenceError`. See
   `lib/jido/persistence/adapter.ex:14-44`,
   `lib/jido/persistence.ex:59-150`, and `lib/jido/persistence.ex:386-430`.

9. An indeterminate write stops the current Agent Server before more Action
   work can run. The public command error is still
   `{:persistence_failed, reason}`. See `lib/jido/agent_server.ex:1493-1507`,
   `lib/jido/agent_server.ex:1548-1594`, and
   `test/jido/persistence/indeterminate_write_test.exs:46-93`.

10. `Jido.PortableTerm.valid?/1` recursively accepts maps, tuples, and proper
    lists, and rejects PIDs, references, ports, functions, and improper list
    tails. Persistence checks the complete record before save and after load.
    See `lib/jido/portable_term.ex:1-24` and
    `lib/jido/persistence.ex:284-315,330-366`.

11. Telemetry and observation use the bounded `to_map/1` projection. Top-level
    telemetry keeps the derived `error_type` and `retryable?` values. See
    `lib/jido/observe.ex:293-312` and `lib/jido/telemetry/agent.ex:163-185`.

## Aligned contracts

These current facts agree fully or partly with the proposal.

- Splode is the error framework. Normal validation, execution, routing,
  timeout, and internal failures already have defined exception structs.
- Tagged APIs and their bang forms use the same validation exceptions for the
  normal Agent construction path. For example, `new!/1` raises the error from
  `new/1`; see `lib/jido/agent.ex:260-291`.
- Signal routing has an explicit normalization path from the adjacent Signal
  package to `Jido.Error.RoutingError`. See
  `lib/jido/agent/command/runner.ex:178-202`.
- Plugin and Exec wrappers contain many callback raises, throws, exits, and
  invalid returns. The tests verify this behavior for Plugin callbacks. See
  `test/jido/plugin/result_contract_test.exs:64-90` and
  `test/jido/plugin/validation_test.exs:247-275`.
- The current error projection is bounded, removes stacktraces, redacts common
  secret fields, preserves useful validation paths, and stays JSON encodable.
  See `test/jido/error_transport_test.exs:28-153` and
  `test/jido/error_transport_test.exs:155-330`.
- The persistence provider controls have documented meanings. The Agent Server
  treats an indeterminate compare-and-swap result and an adapter exception as
  loss of safe write authority. See
  `lib/jido/persistence/adapter.ex:23-35` and
  `test/jido/persistence/indeterminate_write_test.exs:46-93`.
- Recursive portability checks exist and run before adapter storage. Focused
  research tests cover nested portable values, PIDs, and improper lists. See
  `test/jido/persistence/checkpoint_portability_test.exs:15-49`.
- The raw `receive_response/2`, best-effort `cast/2`, local lookup, and OTP
  startup shapes exist as protocol-style exceptions. See
  `lib/jido/agent_server.ex:224-255` and `lib/jido/agent_server.ex:295-310`.

## Gaps

### Missing implementation

These proposal items have no complete implementation.

1. There are no `PersistenceError` or `RuntimeError` modules or Splode classes.
   There is also no public `Jido.Error.t()` union. Public specifications still
   use `term()` or `Exception.t()`. The proposal requires all three contracts.

2. Defined errors have no fixed `code` field. Therefore, the proposed timeout,
   cancellation, persistence, routing, validation, execution, and runtime codes
   cannot be stable program keys. Current program decisions use raw atoms,
   tuples, derived projection types, messages, phases, and detail fields.

3. There is no single normalization function for public boundaries. Direct
   Agent execution, Plugin callbacks, persistence callbacks, Agent Server
   replies, and startup paths use different rules. A returned error can be a
   defined exception, an arbitrary exception, an atom, a tuple, or a map.

4. The public persistence layer does not convert provider controls to
   `PersistenceError`. It also classifies adapter exceptions and invalid
   callback results as `ExecutionError`. Agent Server calls add a raw
   `{:persistence_failed, reason}` wrapper.

5. The proposed persistence timeout contract is absent. Agent Server options
   have `directive_timeout` and `readiness_timeout`, but no
   `persistence_timeout`. The code cannot yet produce the proposed
   `PersistenceError` with code `indeterminate` after a persistence callback
   timeout. See `lib/jido/agent_server/options.ex:8-34`.

6. The proposed stable cancellation meanings are not implemented. Current
   control results use `:idle`, `:directing`, `:stale_turn`, and `:cancelled`.
   They do not use the proposed `no_active_turn`, `turn_mismatch`, `too_late`,
   and `turn_cancelled` RuntimeError codes. See
   `lib/jido/agent_server.ex:709-756`.

7. Portable state is not rejected at the Agent transition boundary. A schema
   that accepts a runtime term can admit it. Persistence rejects the term later,
   but an Agent without persistence can hold it. The proposal requires one
   portable-term contract for Agent and Plugin state before commit, with the
   exact failing state path.

8. The implementation does not have the proposed public identity values that
   error fields can safely reference, such as `Agent.Ref`, Plugin ID, and a
   stable Directive ID. This blocks the proposed closed field sets from using a
   common identity vocabulary.

### Design and code conflict

These current contracts directly differ from the proposal.

1. The proposal defines seven errors and seven classes. Current code documents
   six errors but implements five classes. It includes core
   `CompensationError`, which the proposal assigns to `jido_action`, and it
   lacks `PersistenceError` and `RuntimeError`. The current class order also
   puts execution before routing. Compare `docs/design/12_errors-and-contracts/errors.md:37-59,91-113`
   with `lib/jido/error.ex:5-16,39-45,99-107`.

2. The proposed projection has `class`, an error module in `type`, stable
   `code`, `message`, `retryable?`, and selected operation fields. Current
   `to_map/1` returns a derived atom in `type` and a general sanitized `details`
   map. It has no `class` or `code`. Compare
   `docs/design/12_errors-and-contracts/errors.md:174-194` with
   `lib/jido/error.ex:514-535`.

3. The proposal says public command, construction, and lifecycle error
   positions do not return arbitrary terms. Current public code and tests
   intentionally preserve raw terms. Examples include Plugin validation
   `:invalid_plugin_options`, cancellation `:idle` and `:stale_turn`, hibernation
   `:not_running`, debug state `:debug_not_enabled`, and persistence
   `{:persistence_failed, :indeterminate}`. See
   `test/jido/plugin/validation_test.exs:241-244`,
   `test/jido/agent_server/runtime_boundary_test.exs:400-409,530-539`,
   `test/jido/agent_server/public_api_test.exs:465-475`,
   `test/jido/agent_server/runtime_observability_test.exs:25-36`, and
   `test/jido/persistence/indeterminate_write_test.exs:46-61`.

4. The proposal says returned callback errors are defined composed errors.
   Current Agent and Plugin wrappers pass `{:error, reason}` through without
   checking it. Current tests require this pass-through behavior. See
   `lib/jido/agent/command/runner.ex:221-226`,
   `lib/jido/plugin.ex:448-449,712-713,785-786,810-811`, and
   `test/jido/plugin/result_contract_test.exs:68-75`.

5. The proposal limits error fields to identifiers and excludes Agent state,
   Plugin state, Signal data, payloads, and raw runtime values. Current error
   constructors accept `any()` subjects and targets and general detail maps.
   `CompensationError` stores an original error and result. Several boundaries
   put invalid state, Signal data, replacement Agents, callback results, and raw
   exceptions in details. The projection sanitizes these values, but the error
   structs themselves are not safe bounded values. See
   `lib/jido/error.ex:119-135,195-209,255-277`,
   `lib/jido/agent/state.ex:56-61`, and
   `lib/jido/agent/command/runner.ex:158-162,213-218`.

6. The proposal says callback raises become matching defined errors and broken
   framework invariants exit the live Server. Direct `Agent.cmd/3` returns a raw
   raised exception or `{kind, reason}` tuple. In live preparation,
   `start_turn/3` deliberately reraises and exits the Server. The code does not
   state which faults are application callback faults and which faults are
   framework invariant faults. See `lib/jido/agent/command/runner.ex:29-47` and
   `lib/jido/agent_server.ex:1285-1322`.

7. The proposal says the internal shutdown reason after an indeterminate write
   is `lost_write_authority`. Current code uses
   `{:shutdown, {:persistence_failed, failure}}`. Compare
   `docs/design/12_errors-and-contracts/errors.md:85-89` with
   `lib/jido/agent_server.ex:1560-1565`.

8. The proposal lists `whereis_local/2`, instance `child_spec/1`, and instance
   `start_link/1` as protocol exceptions. Current core exposes PID-based
   `AgentServer.whereis/3`, while the proposed Ref-first instance boundary is
   deferred. The table does not match the current public API names.

### Missing decision

The proposal needs these decisions before implementation can be precise.

1. Define the full closed code list for every error class. The proposal defines
   timeout and cancellation codes and one persistence code, but it does not
   define stable codes for the other validation, routing, execution,
   persistence, runtime, and internal failures already present in core.

2. Decide the compatibility plan for the current public projection. Existing
   callers can use `type`, `details`, and `retryable?`. The proposal changes the
   meaning of `type` and adds `class` and `code`. State whether this is a hard
   replacement, a versioned projection, or a compatibility period.

3. Decide whether `to_map/1` accepts only `Jido.Error.t()` or continues to
   accept arbitrary terms as a last-resort reporting boundary. The current
   implementation and telemetry depend on arbitrary-term projection.

4. Define the exact closed fields for each error and the allowed value types in
   each field. The current proposal gives one `PersistenceError` example and a
   general exclusion rule, but not complete schemas for all seven errors.

5. Define how package error composition is selected and exposed. The proposal
   refers to an active Jido Splode and per-instance composition, but current
   `Jido.Error` has one compile-time Splode. There is no instance option or
   public lookup for an active composition.

6. Define the normalization matrix for each callback boundary. It must state
   the class and code for a returned arbitrary term, an arbitrary exception, a
   raise, a throw, an exit, a task down result, an OTP timeout, and an internal
   invariant failure.

7. Decide which OTP exits are protocol controls and which ones are public Jido
   failures. In particular, separate caller wait timeout from admission timeout,
   Turn timeout, readiness timeout, Directive timeout, startup timeout, and a
   process-down reply.

8. Complete the list of allowed raw protocol results against the current public
   API. Current lifecycle and inspection calls add more raw controls than the
   table lists. Examples are `alive?/1`, `creation_info/1`, `recent_events/3`,
   `hibernate/2`, and child lifecycle operations.

9. Decide where the recursive portable-term rule runs. The design says Agent
   and Plugin state must be portable, but current code checks the persistence
   record. State whether validation must occur at construction, every
   transition, each Plugin contribution, checkpoint, restore, or all of these
   boundaries. Also define the path format for a portability error.

### Missing verification

The proposal lists required tests, but the current suite does not verify the
complete proposed contract.

1. There is no taxonomy test that checks the seven classes, their precedence,
   the closed module set, or `Jido.Error.t()`.

2. There is no stable-code table test. Current tests check derived projection
   `type` atoms instead. See `test/jido/error/normalization_test.exs:196-325`.

3. There is no boundary inventory test that proves every public command,
   construction, and lifecycle failure contains a defined composed error.
   Several tests verify the opposite raw results, as listed in the conflict
   section.

4. There is no test that checks the proposed projection keys, excludes the
   general `details` container, or permits only selected identity and operation
   fields. Current projection tests strongly verify the current four-key map.
   See `test/jido/error_transport_test.exs:242-255`.

5. There is no test that maps each callback return, raise, throw, exit, task
   down, and timeout to one specified class and code across Agent, Plugin,
   persistence, and Agent Server boundaries.

6. There is no non-research test that rejects non-portable Agent and Plugin
   state before a direct or live commit and reports the exact state path. The
   checkpoint portability test is tagged `research` and checks rejection only
   at persistence. See
   `test/jido/persistence/checkpoint_portability_test.exs:1-4,26-49`.

7. There is no persistence callback timeout test because there is no
   `persistence_timeout` option. Existing tests cover returned indeterminate
   values and raised compare-and-swap callbacks, but not a bounded callback
   timeout or the proposed public `PersistenceError` code.

8. There is no test for the exact `lost_write_authority` shutdown reason.
   Existing tests prove that the Server stops, but they expect the current
   `persistence_failed` reason.

9. There is no deliberate invariant-failure test that proves an unexpected
   framework invariant exits the Agent Server while ordinary callback faults
   return defined errors.

## Narrow dependency notes

These dependencies are direct. They must be resolved with this seam, but they
do not expand this report into a general design review.

- **Agent and Turn evaluation:** Their proposed result types use
  `Jido.Error.t()`, and their portable state rule needs validation support from
  this seam. See `docs/design/01_agent/agent.md:239-244` and
  `docs/design/04_turn-evaluation/turn-evaluation.md:145-149,209-213`.
- **Plugins:** Plugin callback specifications, fault containment, owned state,
  and Directive errors depend on the normalization matrix and portable-term
  validation. Current Plugin callbacks still use `term()` error positions.
- **Persistence:** The adapter must keep raw provider control tags at the
  provider boundary. This seam must define their conversion at the public Jido
  boundary. The persistence design also proposes a stricter compare-and-swap
  result set than current code. See
  `docs/design/07_persistence/persistence-adapters.md:138-175`.
- **Agent Server and Jido instance:** Stable timeout, cancellation, overload,
  startup, reentry, and lifecycle codes require one agreed public boundary.
  Ref-first instance functions are not current core behavior.
- **Observability:** Telemetry currently depends on the existing `type` atom
  and arbitrary-term projection. Any projection change must update its
  low-cardinality status mapping. The observability proposal also expects
  distinct conflict and indeterminate statuses. See
  `docs/design/13_observability/observability.md:106-134`.
- **Adjacent packages:** `jido_action` and `jido_signal` already supply Splode
  errors. Core currently maps selected package errors for projection and wraps
  Signal routing errors. Composition must preserve those package contracts
  without copying package-owned concepts into core.

## Ordered recommendations

The following items are proposals. They are not current behavior.

1. Lock the public taxonomy first. Define the seven classes, class order,
   package ownership, closed error modules, exact fields, and `Jido.Error.t()`.
   Decide whether core removes `CompensationError` or keeps a temporary
   compatibility alias.

2. Publish one stable code registry. Include all current public failure
   meanings, not only timeout and cancellation. Give each code one owner, error
   class, retry default, and allowed public fields.

3. Lock the projection contract and its compatibility policy. Decide the new
   meaning of `type`, whether `details` remains, and whether arbitrary-term
   projection stays available as a separate defensive function for telemetry
   and crash reporting.

4. Implement one normalization entry point with boundary-specific context.
   Use it in Agent evaluation, Plugin wrappers, persistence, Agent Server
   command replies, and instance lifecycle helpers. Keep provider control atoms
   inside provider protocols and convert them before public Jido results.

5. Add `PersistenceError` and `RuntimeError`, then convert persistence,
   cancellation, admission, readiness, Directive, overload, reentry, startup,
   and process-unavailable failures. Add `persistence_timeout` only after its
   cancellation and indeterminate-write behavior is explicit.

6. Enforce portability before state becomes a valid Agent candidate. Return a
   `ValidationError` with a stable code and exact state path. Keep the
   persistence record check as defense in depth.

7. Separate application callback faults from internal invariant faults in the
   evaluator and Agent Server. Normalize the former. Let the latter exit, and
   test that boundary directly.

8. Replace tests that require raw public failures with code-based assertions.
   Add table-driven tests for taxonomy, normalization, protocol exceptions,
   projection safety, portable-state paths, persistence timeout, lost write
   authority, and bang/tagged parity.

9. Update public module documentation and types only after the implementation
   and tests agree. Keep deferred Ref-first and provider designs labeled as
   proposals until their code exists.

## Evidence index

- Seam proposal: `docs/design/12_errors-and-contracts/errors.md:13-212`
- Implemented error model: `lib/jido/error.ex:1-318,479-900`
- Error projection tests: `test/jido/error/normalization_test.exs:139-325` and
  `test/jido/error_transport_test.exs:28-330`
- Direct Agent boundary: `lib/jido/agent.ex:125-130,260-319,371-450,509-519`
- Turn runner boundary: `lib/jido/agent/command/runner.ex:29-47,91-153,221-288`
- Plugin boundary: `lib/jido/plugin.ex:47-105,438-460,696-815,826-869,962-978`
- Agent Server boundary: `lib/jido/agent_server.ex:158-418,567-836,920-1029,1285-1322,1440-1637,1926-1979,2874-3037`
- Persistence boundary: `lib/jido/persistence.ex:59-150,191-245,284-430` and
  `lib/jido/persistence/adapter.ex:14-46`
- Portable-term implementation: `lib/jido/portable_term.ex:1-24`
- Failure reporting: `lib/jido/observe.ex:293-312` and
  `lib/jido/telemetry/agent.ex:163-185`
- Current implemented scope statement: `guides/core-scope.md:1-22,91-107`
