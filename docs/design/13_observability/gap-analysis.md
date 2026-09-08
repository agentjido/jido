# Observability gap analysis

## Scope and owner

This report compares the observability design with the current `jido` code.
The scope is limited to semantic telemetry, bounded metadata, metrics, logs,
trace propagation, the proposed OpenTelemetry bridge, and retirement of the
legacy observation paths.

Jido core owns the Agent lifecycle, Turn, commit, persistence, Directive, and
admission boundaries. It also owns the safe semantic metadata for these
boundaries. `jido_signal` owns the W3C Signal carrier. `jido_action` owns Action
and Flow telemetry and its internal task boundaries. The host application must
own the OpenTelemetry SDK, sampler, exporter, credentials, and Collector.

The design files are proposals, except for the stated OBS-01 subset. This
report treats code under `lib` as the source of current implemented behavior.
It treats all other design text as a proposal.

## Implemented baseline

The following items are current facts.

- `Jido.Telemetry.Agent` emits semantic span events for Agent lifecycle, Turn,
  commit, and Directive boundaries. It also emits the
  `[:jido, :agent, :turn, :settled]` point event. Span starts contain system and
  monotonic time. Terminal events contain a native-unit duration
  (`lib/jido/telemetry/agent.ex:46-73`, `lib/jido/telemetry/agent.ex:96-147`).
- Lifecycle telemetry currently covers only `:activate` and `:stop`. Each
  activation gets an `activation_id` (`lib/jido/agent_server.ex:493-500`,
  `lib/jido/agent_server.ex:1246-1251`).
- A successful Turn stops after commit. Directive work then runs. The settled
  event follows the Directive batch (`lib/jido/agent_server.ex:1493-1519`,
  `lib/jido/agent_server.ex:2621-2638`).
- Returned errors use `:stop` and classified metadata. Raised, thrown, or
  exited work uses `:exception` at the semantic helper boundary
  (`lib/jido/telemetry/agent.ex:76-93`,
  `lib/jido/agent_server.ex:2718-2746`).
- Semantic metadata passes through an allowlist. String identities have a
  256-byte limit. A string partition has a 128-byte limit. Unsupported values
  and keys are removed. Telemetry handler failures are caught
  (`lib/jido/telemetry/agent.ex:194-223`).
- Current Turn metadata includes Agent, activation, Signal, Turn, and legacy
  trace identities. It also includes creation-cause fields when they apply
  (`lib/jido/telemetry/agent.ex:8-43`,
  `lib/jido/agent_server/creation_cause.ex:24-61`).
- `Jido.Tracing.Trace` reads and writes both legacy `jido*` fields and W3C
  `traceparent` and `tracestate`. It rejects a partial or malformed trace family.
  New roots use a fixed W3C `00` trace flag (`lib/jido/tracing/trace.ex:1-47`,
  `lib/jido/tracing/trace.ex:92-126`).
- `Jido.Tracing.Context` stores trace data in the process dictionary. It makes
  child Signal contexts and clears the local context at the end of Agent Server
  work (`lib/jido/tracing/context.ex:12-37`,
  `lib/jido/tracing/context.ex:57-107`, `lib/jido/agent_server.ex:1275-1282`).
- The old `[:jido, :agent_server, :signal, ...]` and
  `[:jido, :agent_server, :directive, ...]` spans still run with the semantic
  spans (`lib/jido/agent_server.ex:2659-2693`).
- `Jido.Telemetry.metrics/0` defines three metrics. All three use legacy
  `:agent_server` events. `Jido.Telemetry.setup/0` also attaches the legacy log
  handler during application start (`lib/jido/telemetry.ex:63-125`,
  `lib/jido/application.ex:5-8`).
- The legacy observation API is public and active. It includes tracer callbacks,
  scoped callbacks, tracer failure policy, `SpanCtx`, `NoopTracer`, debug
  configuration, and a per-Agent debug event buffer (`lib/jido/observe.ex:1-98`,
  `lib/jido/observe/tracer.ex:1-67`, `lib/jido/debug.ex:1-114`,
  `lib/jido/agent_server/state.ex:50-60`).
- There is no `Jido.OpenTelemetry` module and no OpenTelemetry dependency in
  `mix.exs`. The application starts only the existing Telemetry handler
  (`mix.exs:351-362`, `lib/jido/application.ex:5-8`).

## Aligned contracts

The following current behavior agrees with the approved OBS-01 subset or with
the wider proposed contract.

- The four implemented semantic prefixes use start, stop, and exception
  suffixes. `turn.settled` is a separate terminal outcome event.
- A successful runtime order is `turn.start`, `commit.start`, `commit.stop`,
  `turn.stop`, Directive events, and `turn.settled`. A focused test holds the
  Directive task and proves this order
  (`test/jido/observe/agent_lifecycle_test.exs:174-224`).
- Returned execution errors do not become exception events. Directive task
  exits do become exception events
  (`test/jido/observe/agent_lifecycle_test.exs:230-270`,
  `test/jido/observe/agent_lifecycle_test.exs:352-380`).
- Semantic events exclude the tested private error, caller context, map
  partition, PID, function, reference, raw error, and stacktrace values
  (`test/jido/observe/agent_lifecycle_test.exs:230-269`).
- A failing external Telemetry handler does not change the Agent command result
  (`test/jido/observe/agent_lifecycle_test.exs:24-45`).
- Signal and child-Agent causation is implemented for local and remote Agent
  work. The tests cover child work, results, activation, notification, restart,
  and replacement (`test/jido/observe/causal_trace_test.exs:36-109`,
  `test/jido/observe/remote_causal_trace_test.exs:11-70`).
- W3C flags and bounded `tracestate` pass through child Signals. The
  `jido_signal` carrier limits `tracestate` to 512 bytes and 32 members
  (`test/jido/tracing/context_test.exs:99-123`,
  `../jido_signal/lib/jido_signal/trace.ex:185-206`).

## Gaps

### Missing implementation

These are current implementation gaps against the proposed design.

1. Core emits no `[:jido, :persistence, :operation, ...]` events. Persistence
   load and compare-and-swap run directly through `Jido.Persistence`
   (`lib/jido/agent_server.ex:2887-2904`,
   `lib/jido/persistence.ex:79-99`, `lib/jido/persistence.ex:119-135`).
2. Core emits no `[:jido, :agent, :admission, :rejected]` event. Admission
   timeout and overload paths only return an error or log a dropped cast
   (`lib/jido/agent_server.ex:1926-1958`).
3. Lifecycle events for create, hibernate, thaw, and delete do not exist. Only
   activation and stop are instrumented.
4. The proposed metric set does not exist. There are no semantic Turn, commit,
   persistence, lifecycle, Directive error, admission, or settlement metrics.
5. `Jido.Telemetry.Logger` does not exist. The current log consumer handles only
   legacy Signal and Directive events and uses the old log-level configuration
   (`lib/jido/telemetry.ex:117-243`,
   `lib/jido/observe/config.ex:43-128`).
6. Semantic events do not contain `traceparent`, `tracestate`,
   `telemetry_span_context`, `write_authority`, or a derived `sampled?` value.
   The normalizer does not allow these fields, except for `sampled?`, which no
   current trace conversion supplies (`lib/jido/telemetry/agent.ex:8-10`,
   `lib/jido/telemetry/agent.ex:27-43`,
   `lib/jido/telemetry/agent.ex:194-215`).
7. The optional OpenTelemetry dependency, public facade, private handler,
   semantic-to-span mapping, status mapping, cleanup, and global opt-out do not
   exist.
8. Jido-owned task starts do not copy OpenTelemetry context. This includes
   admission, execution adapters, Directives, Plugin readiness, and error-policy
   delivery (`lib/jido/agent_server.ex:1325-1336`,
   `lib/jido/agent_server.ex:1370-1383`,
   `lib/jido/agent_server.ex:1820-1825`,
   `lib/jido/agent_server.ex:2572-2592`,
   `lib/jido/agent_server/execution_adapter.ex:21-40`).
9. The legacy Agent Server events, tracer callbacks, tracer failure modes,
   debug APIs, and debug event buffer have not entered a deprecation or removal
   path in code.

### Design and code conflict

These are direct differences between current code and statements in the
proposed design.

1. The design says that core has no tracer callback or observer failure policy.
   Current public code provides both. A scoped tracer can run the observed
   function, and strict mode can raise on a tracer failure
   (`docs/design/13_observability/observability.md:31-37`,
   `lib/jido/observe.ex:136-147`, `lib/jido/observe/config.ex:227-244`).
2. The design says that core has no `Jido.Debug`, debug buffer, payload-logging
   option, or redaction opt-out. Current code provides `Jido.Debug`, permits
   `redact: false`, and stores recent events in Agent Server state
   (`docs/design/13_observability/observability.md:260-279`,
   `lib/jido/debug.ex:43-60`, `lib/jido/agent_server.ex:2651-2656`).
3. The design says that metrics and logs use the semantic contract. Current
   metrics and logs use only legacy `:agent_server` events
   (`docs/design/13_observability/observability.md:227-258`,
   `lib/jido/telemetry.ex:84-125`).
4. The design uses `jido_namespace`. Current semantic metadata and metric tags
   use `jido_instance`, which is an instance module or atom. `use Jido` has no
   `namespace` option (`docs/design/13_observability/observability.md:149-170`,
   `lib/jido/telemetry/agent.ex:12-19`, `lib/jido.ex:70-107`).
5. The bridge design requires the SDK to create root spans and apply sampling.
   Current Agent Server code creates a Jido trace before a bridge can do this,
   and new roots always use the W3C `00` flag
   (`docs/design/13_observability/opentelemetry-bridge.md:179-190`,
   `lib/jido/agent_server.ex:1285-1298`,
   `lib/jido/tracing/trace.ex:25-47`).
6. The design says that direct `Jido.Agent.cmd/3` emits no telemetry and that
   package events are disabled. Current `Agent.cmd/3` always calls
   `Jido.Exec.run/4`, and it passes no observation mode. A routed Flow starts
   its package-owned telemetry span without a disable option
   (`docs/design/13_observability/observability.md:29-32`,
   `docs/design/13_observability/observability.md:101-104`,
   `lib/jido/agent.ex:461-462`, `lib/jido/agent/command/runner.ex:29-42`,
   `../jido_action/lib/jido_exec/flow/adapter.ex:117-123`).
7. The public `Jido.Telemetry` types still allow raw `:error` terms and arbitrary
   metadata terms. This public documentation does not describe the strict
   semantic allowlist (`lib/jido/telemetry.ex:38-61`,
   `lib/jido/telemetry/agent.ex:194-215`).

### Missing decision

These points need a design decision before implementation.

1. Select one public identity tag: `jido_namespace` or `jido_instance`. Define
   its value, configuration source, length limit, and migration rule.
2. Define the exact event catalog in `Jido.Telemetry`. For each event, define
   required and optional measurements, metadata, status values, and units.
   Also decide if create, hibernate, thaw, and delete are runtime lifecycle
   events or higher-level operation events.
3. Define `write_authority` for each returned persistence result. The design
   lists the field but does not give a complete mapping for load, conflict,
   delete, stop-save, and runtime-checkpoint operations.
4. Define settlement duration. State if `turn.settled.duration` is total time
   from Turn start or only the time after the live Result. Current code reports
   total time from Turn start (`lib/jido/telemetry/agent.ex:141-146`).
5. Select exact metric names, metric kinds, tags, and error filters. The design
   lists metric subjects, but it does not define the complete public metric API.
6. Define the migration from the old `:trace`, `:debug`, and other log levels to
   `false | :errors | :interesting | :all`. Define how old redaction and
   argument-logging settings behave during the migration.
7. Confirm the supported `opentelemetry_api` version range. Define
   `available?/0` and `enabled?/0` when the API is present but the SDK is absent
   or not started.
8. Define the release and compatibility period for `Jido.Observe`, legacy
   `:agent_server` events, debug APIs, and `jido_otel`. Define which old event
   and configuration contracts remain stable during that period.

### Missing verification

These proofs do not exist in the current test set.

1. No test proves that direct `Jido.Agent.cmd/3` emits no Telemetry event from
   core and dependency packages. The current test only proves that the Agent
   semantic event probe receives no Agent runtime event
   (`test/jido/observe/agent_lifecycle_test.exs:10-21`).
2. There are no event-order and classification tests for persistence operations
   or admission rejection.
3. There are no tests for the complete semantic metric set or the proposed log
   modes.
4. The semantic privacy tests do not explicitly cover ports, Signal and
   Directive structs as direct metadata inputs, `tracestate`, or the reserved
   span reference. The helper unit test checks only a small sample of accepted
   and rejected fields (`test/jido/telemetry/agent_test.exs:57-99`).
5. There is no compile fixture for a consumer with no OpenTelemetry package.
   There are no bridge tests for API-only, disabled, SDK-backed, exporter, or
   handler-failure cases.
6. There are no OpenTelemetry parentage tests across admission, execution,
   Directive, readiness, error-policy, child-Agent, remote Signal, or concurrent
   Agent boundaries. The existing causal tests verify Jido IDs, not SDK span
   context.
7. There is no test that proves cleanup of all bridge process context on
   success, returned error, timeout, cancellation, exception, normal shutdown,
   and handler failure.
8. There is no equal-coverage proof that permits removal of the duplicate
   `:agent_server` events or the old tracer callbacks.

The focused current test run on 2026-09-08 passed 57 tests. The command covered
the Agent lifecycle, local causal trace, Telemetry consumer, semantic metadata,
trace helper, and trace context test files. This result verifies the listed
implemented baseline. It does not verify the missing features above.

## Narrow dependency notes

- `jido_signal` already supplies a bounded W3C carrier. Its public
  `Jido.Signal.Trace` module owns trace parsing, formatting, and Signal storage.
  Jido core should consume this contract and should not duplicate W3C parsing.
- `Jido.Tracing.Trace` is a compatibility adapter that joins legacy UUID values
  with the W3C carrier. Its retirement must be coordinated with all current
  `jidotraceid`, `jidospanid`, `jidoparentspanid`, and `jidocausationid` users.
- `jido_action` owns Flow and Action task execution. It has its own Telemetry
  tracker and process starts. Jido core cannot complete end-to-end
  OpenTelemetry propagation inside those processes without a small explicit
  contract in `jido_action`. The dependency direction must stay from `jido` to
  `jido_action`; `jido_action` must not depend on Jido core.
- Jido core also starts Plugin and error-policy tasks. The core bridge must copy
  context at these boundaries. This work must not move Plugin or execution
  semantics into the observability layer.
- `jido_ai` must own model, prompt, token, tool, retrieval, and cost semantics.
  This report makes no recommendation about those event details.

## Ordered recommendations

The following items are proposals. They are not current behavior.

1. Lock the semantic contract first. Resolve the identity tag, lifecycle scope,
   exact event fields, status and `write_authority` mappings, duration meanings,
   metric definitions, and the meaning of pure-command observation.
2. Complete the semantic source. Add admission and persistence events. Add the
   missing lifecycle operations only if the locked contract keeps them. Add
   W3C carrier fields and one safe span-correlation reference.
3. Move built-in metrics and logs to semantic events. Add the full metric set
   and the four log modes. Keep reporters outside core. Prove the metadata and
   metric-tag cardinality rules before bridge work.
4. Add the optional OpenTelemetry API boundary and `Jido.OpenTelemetry`. Test a
   consumer build with no OpenTelemetry dependency before automatic startup is
   enabled.
5. Add explicit OpenTelemetry context transfer at every Jido-owned process
   boundary. Then add the minimum compatible propagation contract to
   `jido_action`. Prove local, remote, concurrent, timeout, cancellation, and
   shutdown paths.
6. Run semantic and OpenTelemetry coverage beside the legacy path. Remove
   legacy `:agent_server` spans only after the new path has equal or better
   result, failure, order, privacy, and parentage coverage.
7. Deprecate and remove tracer callbacks, `SpanCtx`, `NoopTracer`, strict tracer
   failure policy, old debug observation controls, and `jido_otel` in the
   selected compatibility sequence. Publish configuration and event migration
   tables before removal.

## Evidence index

- Design contract: `docs/design/13_observability/observability.md:14-313`
- Bridge proposal and test matrix:
  `docs/design/13_observability/opentelemetry-bridge.md:23-343`
- Semantic emitter: `lib/jido/telemetry/agent.ex:1-223`
- Legacy metrics and logs: `lib/jido/telemetry.ex:1-308`
- Agent Server event placement: `lib/jido/agent_server.ex:1285-1525`,
  `lib/jido/agent_server.ex:2621-2747`
- Signal trace adapter: `lib/jido/tracing/trace.ex:1-262`
- Process trace context: `lib/jido/tracing/context.ex:1-127`
- Legacy observation API: `lib/jido/observe.ex:1-98`,
  `lib/jido/observe/tracer.ex:1-67`
- Debug state and API: `lib/jido/debug.ex:1-114`,
  `lib/jido/agent_server/state.ex:50-73`, `lib/jido.ex:203-229`
- Focused semantic tests: `test/jido/observe/agent_lifecycle_test.exs:10-392`
- Causal tests: `test/jido/observe/causal_trace_test.exs:13-320`,
  `test/jido/observe/remote_causal_trace_test.exs:11-218`
- Trace tests: `test/jido/tracing/trace_test.exs:8-236`,
  `test/jido/tracing/context_test.exs:12-154`
