---
title: Jido.Signal component and sub-components
status: current
last-reviewed: 2026-11-10
---

# Jido.Signal component and sub-components

Purpose: Record the envelope, Router, Bus, and Dispatch contracts.
Review result: All four checks have evidence for each owner (R5).
Findings and boundary decisions remain open. No source change is approved.

## Coverage and ownership

Review state: HEAD `85023dd` with local changes. The namespace has 28 files
and 6,272 lines. Router, Bus, and Dispatch remain separate sub-components,
as settled by D3 and D4. Their reviews are explicit below.

| Owner | Source responsibility | Success and failure coverage |
| --- | --- | --- |
| Signal core | Envelope, Context, Codec, Catalog, Boundary | Construction, invalid fields, portable decode, binary data, context, module decoding, and bounded/redacted output traced. |
| Router | Router, State, Route, Index, DSL, Inspect | Normalization, exact and wildcard order, predicates, invalid declarations, compiled routes and lookup equivalence traced. |
| Bus | Facade, Server, Store/Memory, RecordedSignal, Selector, Subscriptions, DurableSubscription, Runtime, Subscriber | Publish/store/delivery, replay, detach/delete, acknowledgement, target death, restore, full log and store errors traced. |
| Dispatch | Target normalization, Adapter behaviour, PID, PubSub, Bus, Logger and HTTP | Option validation, success/error delivery, ordered multiple targets, custom callbacks, telemetry and HTTP test server traced. |

All rows have source, caller, and test evidence. This does not prove external
service delivery or a live production store.

## Signal core

The public value uses CloudEvents fields with a version `1.0` envelope.
`new/1,2,3`, `new!/1,2,3`, schema checks, defined-module checks, extension/context
helpers, and `use Jido.Signal` form its construction surface. Generated Signal
modules expose their type, defaults, schema, data validation, and constructors.
Identity and time defaults belong to construction; decoding must not invent
them. Generated IDs do not infer a source or event type.

`schema/0` returns the envelope schema; `defined?/1` checks a Signal module.
`put_context/3`, `get_context/2`, `delete_context/2`, and `list_context/1`
operate on extensions. `normalize_extensions/1` and
`normalize_extension_name/1` enforce extension names and values. URI, time,
UTF-8, media-type, definition-schema, and macro compile exports support Joi
and generated definitions; they are not separate event lifecycles.

Context is portable envelope metadata. Trace propagation has a separate owner.
The Codec owns `to_map/1`, `from_map/1`, serialization and deserialization,
JSON and safe Erlang-term formats, a size limit, and binary data presence.
Absent data differs from explicit nil data. JSON has string-key restrictions
that the broader portable BEAM term contract does not share.

Codec exposes `serialize/1,2`, `serialize!/1,2`, and `deserialize/1,2`.
Its options choose format and maximum input size. Result tuples carry parse,
format, or option errors; the serialization bang form raises. Context also
exposes trace get/put/delete/ensure and extension wrappers. Catalog exposes
`new/1`, `new!/1`, `decode/2,3`, and `validate/2`; unknown identities and invalid
typed data return stable catalog errors. Boundary exposes `sanitize/2` and
`preview/1,2,3` for telemetry and transport profiles.

Signal Catalog resolves exact `{type, dataschema}` pairs from a trusted module
set. It preserves envelope identity while typed decoding can change data.
It is not the passive registered-value resolver in `Jido.Catalog`.
Boundary owns bounded/redacted presentation profiles, not a wire serializer.

AgentServer input, Plugin delivery, Bus, Dispatch, and AI requests consume the
envelope. Signal module macros supply typed application contracts. Keep the
codec and constructor rules separate where decode must require stored fields.
Do not replace presentation sanitization with raw term serialization.

**F1 — Design decision, P3.** Envelope and Codec repeat field/version/key
checks. They have different defaults and input forms. Consolidate only a
rule with equal valid inputs, error forms, and missing/nil behavior. No safe
large deletion was proved. Keep Catalog's exact schema identity check.

## Router

Public operations are `new/0,1,2`, `new!/0,1,2`, `add/2`, `remove/2`,
`merge/2`, `list/1`, `count/1`, `empty?/1`, `validate/1`, `normalize/1`,
`path/1`, `route/2`, `matches?/2`, `filter/2`, and `has_route?/2`.
The macro generates `router/0`, `routes/0`, and `route/1`; the DSL supplies
`route/2,3,4`. Route schema and State/Index exports support this contract.

Router is an immutable index. It does not dispatch work or own a process.
Ordering is exact, then `*`, then `**`, followed by pattern complexity,
priority, and registration order. Priorities are -100 through 100.
Predicates run after path matching; their failures mean no match. Runtime
routers permit unary functions; compiled routers require an MFA.

Bus uses Index for subscription lookup. Agent routes and Plugin preparation
use the public normalization and route forms. Dispatch validation remains a
separate caller obligation. Tests include lookup/matching properties.

- **F2 — Design decision, P3, high confidence.** `new/2` ignores options.
  Keeping an option parameter with no supported option adds caller uncertainty.
  Either document the empty set or deprecate this arity. Removal affects public
  callers; do not replace it with a new configuration layer.
- **F3 — Design decision, P2, high confidence.** Targets are documented as
  generic terms, but Index expands list targets as target collections. A list
  cannot also be an opaque single target. Specify this exception and add a
  public example before changing representation.

Keep Index and Route validation distinct. Indexed lookup and standalone path
matching serve different workloads; property equivalence is a useful guard.
No measured reason to replace the index was found.

## Bus

Public operations: `child_spec/1`, `start_link/1`, `via_tuple/1,2`,
`whereis/1,2`, `subscribe/2,3`, `unsubscribe/2,3`,
`delete_subscription/2`, `publish/2`, `replay/1,2,3`, and `ack/3`.
Names can use an instance scope or explicit registry. Subscription options
include target, ID, durable identity, start cursor, and a restricted selector.
Replay has an after-cursor and limit. Unsupported combinations return errors.

One GenServer serializes the log and subscription transitions. It stores a
whole publish batch before delivery. Ephemeral target death removes a
subscription. Durable target death detaches it and retains the cursor.
Only the attached target can acknowledge its one in-flight durable record.
The Memory store limits retained records and does not discard records still
needed by a durable subscriber. It is not durable across a process/node loss.

The Store behaviour separates log and subscription storage from Bus state.
Custom stores must return the declared result shape and must bound blocking
work. A call timeout does not cancel a store write or delivery. The caller
must not assume the operation had no effect and retry automatically.

Plugin Bus Manager owns host lifecycle; Plugin clients consume subscriptions.
Dispatch Bus delegates publication. Tests trace local and isolated registries,
store faults, restore, replay, cursor constraints, target death and capacity.

**F4 — Design decision, P3.** Keep subscription identity, live monitor state,
and retained durable cursor distinct. Removal and detachment have different
effects. A shared generic subscription framework would hide those rules.
No additional process or retry engine is justified by the reviewed paths.

## Dispatch

`validate_opts/1` validates a target tuple or list and retains the tuple form.
`dispatch/2` performs synchronous delivery. Internal Target values hold the
resolved adapter and normalized options. Built-ins are PID/named process,
PubSub, Bus, Logger, no-op, and HTTP. Custom adapters provide an option schema
and `deliver/2` through the Adapter behaviour.

Targets run in order. Returned errors are collected while later targets run.
An escaping fault from a custom adapter is re-raised and stops that traversal.
The caller owns concurrency, retries and circuit breaking. PID delivery sends
locally; PubSub needs its host API; Bus uses the public Bus contract; HTTP uses
a synchronous request with configured timeout; Logger uses bounded output.
No adapter establishes exactly-once external delivery.

AgentServer effects, Plugin dispatch, and standalone callers use this boundary.
Validation is repeated when a public tuple is dispatched. That check must not
be removed on the assumption that the tuple came from a prior validation.

- **F5 — Design decision, P3.** `nil` no-op and explicit `:noop` have different
  option checks and telemetry behavior. `:named` aliases the PID adapter;
  Logger also accepts two level option names. Verify downstream use and choose
  a compatibility policy before removing these branches.
- **F6 — Investigation, P3.** Structured dispatch errors depend on a setting.
  A fixed error form would reduce caller branches, but changes a public result.
  Establish the release policy before removing the compatibility option.

Keep the small adapter behaviour. It supplies a real extension point without
moving host supervision or retry policy into Signal.

## Checks and proof gaps

The second focused R5 run passed 675 tests, with three excluded. It included
Signal, codec, Persistence and durable AgentServer paths. Tests use local
processes and a local HTTP server; they do not establish external delivery.
Broad CI stopped in Action build tests; see [R5](../../components.md).

No focused active Covenant owner was found for the Signal core, Router, Bus,
or Dispatch. Plugin Bus proof is partial evidence for Bus, not proof of the
whole Signal namespace. Keep all four checklist rows distinct.

## Sources

- [Signal](../../lib/jido/signal.ex)
- [Codec](../../lib/jido/signal/codec.ex)
- [Catalog](../../lib/jido/signal/catalog.ex)
- [Boundary](../../lib/jido/signal/boundary.ex)
- [Router](../../lib/jido/signal/router.ex)
- [Index](../../lib/jido/signal/router/index.ex)
- [Bus](../../lib/jido/signal/bus.ex)
- [Subscriptions](../../lib/jido/signal/bus/subscriptions.ex)
- [Store](../../lib/jido/signal/bus/store.ex)
- [Dispatch](../../lib/jido/signal/dispatch.ex)
- [Adapter](../../lib/jido/signal/dispatch/adapter.ex)
- [Signal tests](../../test/jido/signal)
- [Codec tests](../../test/jido/codec/signal)
