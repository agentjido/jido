# Example SDK gaps and friction

This register collects reproducible findings from the offline example suite.
Each advanced example keeps the full evidence in its own `Core Fit and Gaps`
section. This file gives one index for later SDK investigation.

A finding can be:

- Application code.
- Ecosystem package concern.
- Documentation or learning-order friction.
- Candidate Jido core change.

Do not add a candidate core change only because an example needs application
code. Record the public contract that was attempted and the smallest failure
that makes the problem clear.

## Findings

### EX-001: A first-hour wait requires persistence setup

- Example: [00_06 Runtime inspection](00_start_here/00_06_runtime_inspection/README.md).
- Classification: Documentation and learning-order friction.
- Attempted contract: Run an AgentServer Flow wait in the first-hour path.
- First result: The in-memory host returned `unsupported_host` for the `waits`
  capability.
- Second result: Adding persistence without a stable namespace returned
  `persistence requires a Jido instance with a stable namespace`.
- Public solution: Configure a stable Jido namespace and a public persistence
  adapter, then start the Agent with `persistence: :inherit`.
- Core change: None proposed. The public operations are sufficient.
- Follow-up question: Should the first-hour path introduce namespace and
  persistence, or should its final lesson avoid a real wait?

### EX-002: A runner called an Action callback directly

- Example: [17_01 ReAct tool loop](17_ai_reasoning_flows/17_01_react_tool_loop/README.md).
- Classification: Application code and documentation friction.
- Attempted contract: Expand the next ReAct tool Flow by calling
  `ExpandNext.run/2` from a runner.
- Result: The stale call returned `{:error, :invalid_tool_calls}` after the
  Action input contract added routing and target data.
- Public solution: Use Agent preflight for graph inspection and run behavior
  through `Agent.cmd/3` or `Jido.Exec`, not an Action callback.
- Core change: None proposed. The example bypassed the public execution path.
- Follow-up question: Should public ReAct graph inspection expose a supported
  expansion view without executing a model round?

### EX-003: An inline Action host needs two declaration macro arities

- Example: [01_05 Inline Actions](01_actions/01_05_inline_actions/README.md).
- Classification: Documentation and authoring friction.
- Attempted contract: Import one three-argument host macro for an inline Action
  declaration with a `do` block.
- Result: Compilation failed with `undefined function inline_action/4`.
- Public solution: Define and import both arities. The four-argument form joins
  the option list and `do` block before it calls `parse_callback!/3`.
- Core change: None proposed. The public compiler API works after the host
  follows Elixir macro call shape.
- Follow-up question: Should the inline Action guide include a minimal host
  that shows both arities before it shows bound input?

### EX-004: JSON Signal schemas need string keys

- Example: [08_01 Signal Envelope](08_signals_and_messaging/08_01_signal_envelope/README.md).
- Classification: Documentation and boundary friction.
- Attempted contract: Serialize a custom Signal created from a Joi object with
  atom keys.
- Result: `Jido.Signal.Codec.serialize/2` returned
  `{:json_encode_failed, "Signal data must contain JSON values or binary data"}`.
- Public solution: Use a string-key Joi schema for JSON-bound Signal data.
- Core change: None proposed. The Signal catalog guide already states the wire
  data rule.
- Follow-up question: Should custom Signal compilation or JSON serialization
  identify the first non-JSON data path in its error details?

### EX-005: Agent output selectors require a declared output shape

- Example: [06_02 Pure and Hosted Execution Parity](06_agent_server/06_02_pure_hosted_parity/README.md).
- Classification: Documentation and authoring friction.
- Attempted contract: Select `output(:state)` and `output(:reply)` from an
  inline route Action that used the default broad output schema.
- Result: Agent compilation failed with `:unsupported_output_path` and named
  the missing `:state` field.
- Public solution: Declare an Action output schema that contains both selected
  fields.
- Core change: None proposed. Compile-time path validation prevented an unsafe
  route definition and gave a specific correction.
- Follow-up question: Should the Agent route guide place an output-schema
  example beside its first state or reply selector?

### EX-006: A reply-only route still needs explicit state projection

- Example: [23_02 Specialist pipeline](23_collaborative_agent_systems/23_02_specialist_pipeline/README.md).
- Classification: Documentation and authoring friction.
- Attempted contract: Return `%{reply: value}` from a stateless Agent route and
  select that field with `reply/2`.
- Result: Agent validation treated the complete Action output as candidate
  state and rejected the unrecognized `:reply` key.
- Public solution: Return both `state` and `reply`, declare both output fields,
  and select each with `state/1` and `reply/2`.
- Core change: None proposed. Explicit projection is safe and supported.
- Follow-up question: Should the first reply-selector example state that reply
  selection does not disable the default state projection?

### EX-007: Static declared topology has no public selected-subtree removal

- Example: [23_06 Nested organization](23_collaborative_agent_systems/23_06_nested_organization/README.md).
- Classification: Candidate Jido core change or explicit non-goal.
- Attempted contract: Remove one declared department and its descendants while
  the company root remains active.
- Result: The public runtime can stop the complete root-owned subtree, but no
  public operation addresses one declared member subtree for controlled
  removal.
- Public solution: The example proves complete root shutdown only and does not
  call private topology functions.
- Core change: Decide whether controlled declared-subtree removal belongs in
  Jido core or whether applications must model changing membership through
  separately owned dynamic Agents.
- Follow-up question: If supported, how does removal coordinate admission,
  child persistence, in-flight Turns, and rollback after partial shutdown?

### EX-008: Definition upgrade cannot replace the Agent origin module

- Example: [24_08 Controlled Agent Upgrade](24_application_patterns/24_08_controlled_agent_upgrade/README.md).
- Classification: Documentation and authoring friction.
- Attempted contract: Migrate an Account V1 Agent snapshot into an instance
  created directly from the compiled Account V2 module.
- Result: `Jido.upgrade_agent/4` rejected the candidate with
  `:upgrade_identity` because its origin module changed.
- Public solution: Use the V2 definition as a complete data template, preserve
  the saved origin module, instantiate the migrated state, and snapshot the
  result.
- Core change: None proposed. Stable origin is an intentional persistence and
  callback boundary.
- Follow-up question: Should the upgrade guide include one complete schema and
  route replacement example that states this origin rule?

### EX-009: Definition rollback is a new forward version

- Example: [24_08 Controlled Agent Upgrade](24_application_patterns/24_08_controlled_agent_upgrade/README.md).
- Classification: Documentation and operational-model friction.
- Attempted contract: Upgrade V1 to V2, then restore the V1 definition with
  version 1.
- Result: `Jido.upgrade_agent/4` rejected the reverse migration with
  `:definition_version_not_advanced`.
- Public solution: Publish version 3 with the earlier behavior and migrate V2
  state into the version 1 state shape.
- Core change: None proposed. Monotonic versions make upgrade history clear.
- Follow-up question: Should Jido call this a forward rollback in its operator
  guide and include a version timeline?

### EX-010: Durable AI stream dispatch must be portable

- Example: [24_06 Phoenix LiveView Chat](24_application_patterns/24_06_phoenix_liveview_chat/README.md).
- Classification: Documentation and integration friction.
- Attempted contract: Send model stream Signals directly to the LiveView PID
  through `jido_ai_dispatch` during a durable Agent Turn.
- Result: AgentServer rejected the Turn because the PID in durable context was
  not portable.
- Public solution: Subscribe the LiveView to a conversation topic and use the
  portable `:pubsub` dispatch target in Turn context.
- Core change: None proposed. Durable context must stay portable.
- Follow-up question: Should the AI streaming guide use PubSub as its first
  hosted Agent example and reserve PID dispatch for pure or transient runs?

### EX-011: Dynamic runtime adoption and ownership transfer have no public API

- Example: [09_05 Logical ownership transfer](09_dynamic_agent_composition/09_05_logical_ownership_transfer/README.md).
- Classification: Candidate Jido core change or explicit non-goal.
- Attempted contract: Adopt an independent Agent into a live parent, transfer
  its runtime ownership to another parent, and apply owner-linked shutdown.
- Result: The current public API can create, activate, resolve, and stop stable
  Agents, but it has no dynamic child adoption or process-owner transfer
  operation. The old example README named APIs that do not exist.
- Public solution: Store logical ownership in an application Agent. The Jido
  instance remains the process owner, and shutdown stays explicit.
- Core change: Decide whether dynamic runtime ownership is a Jido capability or
  an application protocol. If it is a core capability, define adoption,
  transfer, fencing, in-flight Turn, persistence, and shutdown semantics.
- Follow-up question: Can ownership transfer commit atomically with the old
  owner's release, or must the contract expose a recoverable intermediate
  state?

### EX-012: An indeterminate activation rejects direct stop

- Example: [12_06 Indeterminate Write](12_persistence/12_06_indeterminate_write/README.md).
- Classification: Documentation and operational-model friction.
- Attempted contract: Stop an activation after its persistence adapter saved a
  candidate revision but returned an indeterminate result.
- Result: `Jido.stop_agent/3` returned `{:error, :unsafe_resume}` because a
  normal stop could publish an unsafe checkpoint from the faulted process.
- Public solution: Configure persistence on the Jido instance, resolve the
  stable Agent Address, call `Jido.reconcile_agent/3`, verify replacement from the
  authoritative record, and then stop the replacement.
- Core change: None proposed. The safety boundary and recovery operation are
  public and testable.
- Follow-up question: Should the persistence guide show reconcile-before-stop
  as the standard operator response to an indeterminate write?

### EX-013: Explicit-Catalog document decode still needs codec selection

- Examples: [02_04 Stored JSON](02_flow_authoring/02_04_stored_json/README.md)
  and [07_07 Codec documents](07_instance_catalog_documents/07_07_codec_documents/README.md).
- Classification: Candidate public API or documentation change.
- Attempted contract: Decode a stored Flow or Agent document through
  `Jido.Codec.decode/2` or `decode_json/2` with an explicit trusted Catalog.
- Result: Decode returned a `:catalog_not_ready` issue because document routing
  also needs the globally published codec index. Naming `Jido.Flow.Codec` or
  `Jido.Agent.Codec` works, but both modules have hidden documentation.
- Public solution: Obtain the current writer as an opaque module through the
  documented `Jido.Codec.Encoder.codec/1` protocol and pass it in the public
  `:codec` option.
- Core change: Decide whether explicit-Catalog decode should route bundled
  document types without global publication, or expose a public codec selector
  by document type and version.
- Follow-up question: How should an offline importer select a codec when it has
  only the stored document and no current runtime value of that type?
