---
title: Jido.Signal component and sub-components
status: current
last-reviewed: 2026-11-19
---

# Jido.Signal component and sub-components

Purpose: Record the envelope, Router, Bus, and Dispatch contracts.
Review result: All four checks have evidence for each owner (R5).
Findings and boundary decisions remain open. No source change is approved.

## 2026-11-19 top-level review

Reviewed [`release/v3` at `6fdc009a`](https://github.com/agentjido/jido/commit/6fdc009a1edd6261f3e26509fa2905bb9192faa5)
for [tracker #453](https://github.com/agentjido/jido/issues/453). This section
records the pinned review. The R5 records below describe the earlier review.

### Four checks

| Check | Evidence |
| --- | --- |
| Public surface | `Signal.new/1,2,3` returns a Signal or an envelope error string. The bang forms raise. `use Jido.Signal` exposes static metadata, schema, data validation, and typed constructors. Typed constructors fix `type`, `dataschema`, and validated `data`. Joi data errors stay distinct from envelope errors. Construction generates UUIDv7 only for a missing ID and defaults specversion to `"1.0"`. The sender supplies source and optional time. Context helpers read and update flat extensions and attach W3C Trace data. Codec handles the canonical map, JSON, and trusted Erlang terms, including batches and a byte limit. Catalog checks one Signal against an exact `{type, dataschema}` registration and reports structured validation errors. Boundary supplies bounded diagnostic views. [Envelope](../../lib/jido/signal.ex) · [Context](../../lib/jido/signal/context.ex) · [Codec](../../lib/jido/signal/codec.ex) · [Catalog](../../lib/jido/signal/catalog.ex) · [Boundary](../../lib/jido/signal/boundary.ex) |
| API contract usage | Agent admission and Directives check existing Signals. AgentServer Plugin callbacks use the struct schema for outbound Signals. Router reads the type from a recognized Signal module. Bus checks a Signal and uses the canonical map for records. HTTP Dispatch sends codec JSON. Timer uses the canonical map as input to its fingerprint. Trace.Context and telemetry use the Signal carrier. The public examples exercise construction, context, serialization, and causation. [Agent validation](https://github.com/agentjido/jido/blob/6fdc009a1edd6261f3e26509fa2905bb9192faa5/lib/jido/agent/validation.ex#L180) · [Directive](https://github.com/agentjido/jido/blob/6fdc009a1edd6261f3e26509fa2905bb9192faa5/lib/jido/agent/directive.ex#L75) · [Plugin callback](https://github.com/agentjido/jido/blob/6fdc009a1edd6261f3e26509fa2905bb9192faa5/lib/jido/agent_server/plugin/callbacks.ex#L198) · [Router](https://github.com/agentjido/jido/blob/6fdc009a1edd6261f3e26509fa2905bb9192faa5/lib/jido/signal/router.ex#L115) · [Bus record](https://github.com/agentjido/jido/blob/6fdc009a1edd6261f3e26509fa2905bb9192faa5/lib/jido/signal/bus/recorded_signal.ex#L110) · [HTTP Dispatch](https://github.com/agentjido/jido/blob/6fdc009a1edd6261f3e26509fa2905bb9192faa5/lib/jido/signal/dispatch/http.ex#L212) · [Timer](https://github.com/agentjido/jido/blob/6fdc009a1edd6261f3e26509fa2905bb9192faa5/lib/jido/plugin/timer/runtime.ex#L525) · [Trace carrier](../../lib/jido/trace/context.ex) · [Examples](../../examples/08_signals_and_messaging/README.md) |
| Duplication and code quality | The constructor and wire decoder repeat key, version, time, payload, and struct validation rules. Typed and positional constructors normalize keys twice. Catalog repeats envelope work after a data transform. Consumers of existing structs use different combinations of schema and context checks. The guides use both sets of extension helpers. The hidden Codec transport diagnostic forwarders and Context name forwarder have direct test coverage. Keep those compatibility surfaces in this review. [Constructor path](https://github.com/agentjido/jido/blob/6fdc009a1edd6261f3e26509fa2905bb9192faa5/lib/jido/signal.ex#L509) · [Wire path](https://github.com/agentjido/jido/blob/6fdc009a1edd6261f3e26509fa2905bb9192faa5/lib/jido/signal/codec.ex#L101) · [Catalog data path](https://github.com/agentjido/jido/blob/6fdc009a1edd6261f3e26509fa2905bb9192faa5/lib/jido/signal/catalog.ex#L249) · [Context guide](../../guides/signals/cloudevents-envelope-and-context.md) · [Boundary tests](https://github.com/agentjido/jido/blob/6fdc009a1edd6261f3e26509fa2905bb9192faa5/test/jido/codec/signal/boundary_test.exs#L23) · [Error tests](https://github.com/agentjido/jido/blob/6fdc009a1edd6261f3e26509fa2905bb9192faa5/test/jido/signal/public_boundary_errors_test.exs#L66) |
| Elixir and OTP design | Keep Signal an immutable value and Catalog an immutable index of trusted definitions. Joi, ID generation, Trace values, and JSON or term conversion can run in the caller. Signal needs no process, registry, or supervision. Keep these responsibilities distinct from routing, delivery, and process-local trace propagation. Reach places the envelope, Codec, Context, and Boundary in `value_model`, and Catalog in `definitions`. Telemetry proof covers the Trace carrier. The core has direct tests and no dedicated active Covenant record. [Reach](https://github.com/agentjido/jido/blob/6fdc009a1edd6261f3e26509fa2905bb9192faa5/.reach.exs#L24) · [Telemetry proof](https://github.com/agentjido/jido/blob/6fdc009a1edd6261f3e26509fa2905bb9192faa5/test/contracts/jido/telemetry.obligations.md#L56) · [Generated checks](../../test/property/jido_signal) |

Event identity uses `{source, id}`. Codec and Catalog preserve both. Bus
records have their own IDs, and Durable uses its own operation identity.
Router, Bus, and Dispatch remain separate review subjects. Their interfaces
serve as evidence for the top-level contract. [CloudEvents identity](https://github.com/cloudevents/spec/blob/v1.0.2/cloudevents/spec.md#id) ·
[Bus record identity](https://github.com/agentjido/jido/blob/6fdc009a1edd6261f3e26509fa2905bb9192faa5/lib/jido/signal/bus/recorded_signal.ex#L115) ·
[Durable start](https://github.com/agentjido/jido/blob/6fdc009a1edd6261f3e26509fa2905bb9192faa5/lib/jido/durable.ex#L48)

### Published findings

| Issue | Severity | Pinned evidence and impact |
| --- | --- | --- |
| [#454](https://github.com/agentjido/jido/issues/454) Validate existing envelopes before encoding | P2 | JSON encoding accepted a Signal with an invalid ID, version, or time. Decode rejected the result. An invalid presence flag changed absent data to null. [Map writer](https://github.com/agentjido/jido/blob/6fdc009a1edd6261f3e26509fa2905bb9192faa5/lib/jido/signal/codec.ex#L60) |
| [#455](https://github.com/agentjido/jido/issues/455) Reject duplicate envelope attributes before map conversion | P2 | JSON retained the first repeated ID. A constructor keyword list retained the last. The selected member can change event identity. [JSON decode](https://github.com/agentjido/jido/blob/6fdc009a1edd6261f3e26509fa2905bb9192faa5/lib/jido/signal/codec.ex#L325) · [Constructor](https://github.com/agentjido/jido/blob/6fdc009a1edd6261f3e26509fa2905bb9192faa5/lib/jido/signal.ex#L312) |
| [#456](https://github.com/agentjido/jido/issues/456) Honor `datacontenttype` in structured JSON | P2 | The codec emitted an object for `text/plain` data. Structured CloudEvents consumers expect text or Base64 for this media type. [JSON writer](https://github.com/agentjido/jido/blob/6fdc009a1edd6261f3e26509fa2905bb9192faa5/lib/jido/signal/codec.ex#L313) · [CloudEvents JSON section 3.1](https://github.com/cloudevents/spec/blob/v1.0.2/cloudevents/formats/json-format.md#31-handling-of-data) |
| [#457](https://github.com/agentjido/jido/issues/457) Reject trailing bytes in Erlang term payloads | P3 | A valid term envelope with one trailing byte decoded successfully. The codec discarded part of the payload. [Term reader](https://github.com/agentjido/jido/blob/6fdc009a1edd6261f3e26509fa2905bb9192faa5/lib/jido/signal/codec.ex#L332) |
| [#458](https://github.com/agentjido/jido/issues/458) Apply the absolute URI rule to `dataschema` | P3 | A URI with a fragment passed typed construction, catalog registration, and decode. An interoperability change must preserve exact schema identity and account for existing records. [URI refinement](https://github.com/agentjido/jido/blob/6fdc009a1edd6261f3e26509fa2905bb9192faa5/lib/jido/signal.ex#L462) · [RFC 3986 section 4.3](https://www.rfc-editor.org/rfc/rfc3986#section-4.3) |
| [#459](https://github.com/agentjido/jido/issues/459) Keep diagnostics safe for invalid struct fields | P3 | Preview raised `FunctionClauseError` for an invalid URI struct that Signal permits as data. Keep valid formatting and profile limits. [Special formatters](https://github.com/agentjido/jido/blob/6fdc009a1edd6261f3e26509fa2905bb9192faa5/lib/jido/signal/boundary.ex#L59) |
| [#460](https://github.com/agentjido/jido/issues/460) Share constructor and wire parsing rules | P3 | Consolidate identical rules. Preserve constructor defaults, strict wire requirements, extension policies, legacy markers, data flags, and current errors. This supersedes the core F1 reduction question below. [Construction](https://github.com/agentjido/jido/blob/6fdc009a1edd6261f3e26509fa2905bb9192faa5/lib/jido/signal.ex#L509) · [Wire parse](https://github.com/agentjido/jido/blob/6fdc009a1edd6261f3e26509fa2905bb9192faa5/lib/jido/signal/codec.ex#L101) |
| [#461](https://github.com/agentjido/jido/issues/461) Update Catalog data without a wire round trip | P3 | Replace the full envelope write and parse after a Joi transform. A probe confirmed that transforming explicit Base64 bytes into other valid UTF-8 bytes preserves Base64. Keep that result, exact numeric updates, and null versus absent data. [Catalog](https://github.com/agentjido/jido/blob/6fdc009a1edd6261f3e26509fa2905bb9192faa5/lib/jido/signal/catalog.ex#L249) · [Catalog tests](https://github.com/agentjido/jido/blob/6fdc009a1edd6261f3e26509fa2905bb9192faa5/test/jido/signal/catalog_test.exs#L451) |

### Verification

- Elixir 1.20.4 and OTP 29. Focused Signal, Codec, Trace, and telemetry tests
  passed 175 cases. Focused Agent, Directive, Bus record, and Timer consumer
  tests passed 43 cases. Four example files passed five cases. Public
  authoring passed eight cases.
- The selected Signal property and fuzz targets each passed four checks and
  skipped one deferred diagnostics check. Local probes confirmed the
  findings in the table. Repository searches for Signal, CloudEvents, and
  codec issues found no matching issue. Closed #374, #375, #425, and #436
  cover different contracts.
- Format passed. Reach passed the architecture policy and reported 273
  advisory findings across the project.
- The full Covenant command failed on the pinned commit. Of 2,924 tests,
  2,918 passed and six failed. The failures occurred in AgentServer durable
  activation and AI ReAct runtime tests. Covenant reported coverage for
  242 of 244 active obligations. [Activation tests](https://github.com/agentjido/jido/blob/6fdc009a1edd6261f3e26509fa2905bb9192faa5/test/jido/agent_server/durable_activation_contract_test.exs#L490) ·
  [ReAct tests](https://github.com/agentjido/jido/blob/6fdc009a1edd6261f3e26509fa2905bb9192faa5/test/jido/ai/reasoning/react/runtime_contract_test.exs#L1093)

## Implementation for tracker #453

The fixes cover the Signal envelope, codec, diagnostics, and Catalog
integration. Agent, AgentServer, and Plugin continue to own their checks
and error wrappers.

- The map and binary writers validate the envelope and extensions. A direct
  struct can still supply a DateTime or non-null data with the default
  presence flag. Catalog uses the same core check for an existing Signal.
- Construction and wire decode share the key, version, time, payload, and
  struct validation rules. Construction adds defaults and accepts nested
  extensions. Wire decode requires stored identity and uses flat extensions.
- JSON decode rejects repeated envelope keys. Constructors reject repeated
  keyword attributes. JSON payload data retains its former key behavior.
  Erlang term decode requires one complete term.
- Structured JSON encode checks the declared media type. JSON decode keeps
  reading older events with nonconforming `data`.
- Creation and Catalog registration require a fragment-free absolute
  `dataschema` URI. Raw codec reads and writes preserve a legacy fragment
  byte for byte. Catalog matching uses the exact URI.
- Catalog applies data transforms directly to the Signal and its data flags.
  Unit checks cover absent data, explicit null, numeric type changes, and
  explicit Base64. Diagnostic formatting uses a fixed summary if URI or
  calendar formatting fails.

Eleven added regression tests failed before the fixes. The existing
constructor and codec tests and the added Catalog data checks established
the expected behavior for the refactors. The focused check with warnings as
errors passed 213 tests, including Agent, Bus record, and Timer consumers.

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
