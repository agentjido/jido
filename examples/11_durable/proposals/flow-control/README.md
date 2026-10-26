# Proposed Flow timer, await, and selection contract

Status: design proposal. Example 11_06 implements the basic wait host.
The broader syntax below remains a proposal. This is a README
spike, not a public API. The upstream patch may change these names and result
shapes. Follow the [integration checklist](INTEGRATION.md) and use the verified
patched API before adding executable examples.

## Ownership

`Jido.Flow` lives in `jido_action`. Put canonical control data, the module DSL,
map/JSON authoring, validation, dependencies, and compilation there. Do not put
AgentServer, persistence, or OTP activation in that package. Event matching uses
portable event data; it must not require a dependency on `Jido.Signal`.

`jido` supplies the execution host: Signals become portable Flow events;
AgentServer saves acceptance, waits, selected results, cancellation, and completion.
Runic remains the execution graph authority. Do not add another step counter.
A runtime without wait support must reject these components before any Action
runs. Define a host capability contract in `jido_action`; implement it in `jido`.
Keep direct in-memory execution available without persistence when a host supports
waits. Persistence adds recovery, not a different Flow language.

## Proposed syntax

Keep named components, `needs:`, `input()`, `result()`, and explicit `output`.
Source order does not imply execution order. Durations are integer milliseconds;
absolute deadlines are Unix epoch milliseconds. Exactly one of `after_ms` and
`until_ms` is required for a timer. Evaluate a relative duration once when the
component becomes eligible, then save the absolute deadline.

```elixir
flow do
  step "prepare", action: Prepare, params: input()

  timer "cooldown", after_ms: 86_400_000, needs: ["prepare"]

  await "approval",
    event: "order.approved",
    match: %{order_id: input(:order_id)},
    needs: ["cooldown"]

  step "finish", action: Finish, params: %{approval: result("approval")}
  output result("finish")
end
```

`await` is a generic external-event wait. It is not an Action, raw `receive`,
or a wait on an arbitrary Elixir function. The host maps a Signal to portable
`%{id: ..., type: ..., data: ...}` event data. `match` compares declared keys in
`data` for equality. No callback predicates in saved Flow definitions.
The result of `await` is the matched event. A timer result is
`%{deadline_ms: ..., fired_at_ms: ...}`; save both before continuing.

Use selection when a wait has alternatives, including timeout:

```elixir
flow do
  step "prepare", action: Prepare, params: input()

  selection "decision", needs: ["prepare"] do
    await "approved", event: "order.approved",
      match: %{order_id: input(:order_id)}

    await "rejected", event: "order.rejected",
      match: %{order_id: input(:order_id)}

    timer "expired", after_ms: 2_592_000_000
  end

  step "finish", action: Finish, params: %{decision: result("decision")}
  output result("finish")
end
```

Selection returns `%{selected: "approved", value: event}`, or the corresponding
alternative and result. Its alternatives do not run Actions. A normal Choice can
route the saved selection result to an Action. Do not add Action targets to
selection or duplicate Choice behavior.

Timer and await are single-alternative waits. Selection groups alternatives.
Use one canonical wait representation and one resolution mechanism, with DSL
sugar for the single-alternative forms. Do not create three execution engines.
Expose the same meaning in map definitions and Codec; module-only macros are
not sufficient. New component kinds require deliberate Codec version handling.
Nested alternative names are scoped to their selection.

## Acceptance and selection rules

- One durable Flow remains the current Turn while it waits.
- Distinguish a saved waiting graph from a completed graph. No runnable work
  must not, by itself, mean that the Turn completed.
- Ordinary state-changing Turns stay queued. Status and cancellation remain available.
- Flow input has a separate admission path; it cannot queue behind its own Turn.
- Inputs target a stable Agent, Turn, and declared event. Save acceptance before acknowledgement.
- Keep a bounded saved input inbox. Save an early input for a declared event;
  consume it once. Define overflow and stale-target errors before implementation.
- A duplicate input ID returns its recorded acceptance; conflicting content is an error.
- An input satisfies one wait in the initial serial contract. Concurrent waits
  and broadcast consumption need separate design and are out of scope.
- Select by serialized acceptance order. If one event matches several alternatives,
  authored alternative order breaks the tie. At or after the absolute deadline,
  timeout wins. Host acceptance time, not producer timestamps, defines eligibility.
- Persist selection and input consumption together before downstream execution.
  Recovery must resolve a lost storage reply before it can choose again.
- Retain an input's saved acceptance order/time so recovery does not reject an
  event accepted before the deadline just because the Agent restarts after it.
- Ignore late events and stale wake messages for a resolved wait. Cancellation
  races use the same saved transition boundary.

## Long deadlines and resource lifetime

Separate caller timeout, per-Action attempt timeout, wait deadline, and whole-Turn
budget. Whole-Turn time includes waiting. Its default remains 60 seconds; a long
Flow must configure a suitable `turn_timeout` or `:infinity`.

Save UTC deadlines, never PIDs, references, timer references, or monotonic clock
values. Use monotonic time for local execution budgets. Recheck wall time on wake
and activation; use bounded wake intervals to detect clock changes. No claim of
perfect elapsed time across host clock errors is possible without a trusted clock.

A saved wait has no running Action task. It can release its runner. Deactivation
must preserve the pending Turn; current drain/cancel hibernation is not sufficient.
The active Agent can own local wakes. An inactive Agent advances when activated;
Jidoka can discover due records and activate it. Expose the next saved deadline
through an adapter-neutral recovery descriptor. Do not add a core polling service.

## Implementation and proof order

1. Agree canonical wait data, output shape, and host capability contract.
2. Keep the implemented Signal, timer, selection, and suspension lesson in 11_06.
3. Retain 11_08–11_12 for early-input, controlled-clock, and long-duration policy questions.
4. Add separate executable lessons only when they prove a distinct supported contract.
5. Keep design plans separate from executable coverage.
6. Build 11_13 and 11_14: topology and compatible-code recovery.

At each boundary test storage failure before and after commit, lost replies,
Agent loss, cancellation, duplicate inputs, and cleanup. Run the adapter contract
against memory and ETS. Cross-BEAM recovery requires retained adapter storage;
local ETS tests must not claim it. Postgres, cross-host leases, automatic discovery,
active-Flow migration, parallel waits, and exactly-once external effects are deferred.

## Recorded research proposals

- [#302](https://github.com/agentjido/jido_action/issues/302): timer, await,
  selection, repeated wait identity, and execution-host capabilities.
- [#303](https://github.com/agentjido/jido_action/issues/303): explicit Handoff
  into a new Turn with a fresh graph; Invoke keeps its same-execution meaning.
- [#304](https://github.com/agentjido/jido_action/issues/304): audit saved retry
  budgets and backoff before adding new retry APIs.
- [#305](https://github.com/agentjido/jido_action/issues/305): recovery evidence
  for repeated, nested, Map, and Invoke-selected waits.

These files include implemented boundaries and remaining proposals. The core
Handoff chain in 11_15 is implemented. Retry recovery, stable Turn receipt
lookup, composed recovery, and failed-work recovery remain proposals until
their contracts have executable evidence.
