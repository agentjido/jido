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

### EX-001: A first-hour wait requires persistence setup (resolved)

- Example: [00_06 Runtime inspection](00_start_here/00_06_runtime_inspection/README.md).
- Classification: Resolved documentation and learning-order friction.
- Attempted contract: Run an AgentServer Flow wait in the first-hour path.
- First result: The in-memory host returned `unsupported_host` for the `waits`
  capability.
- Second result: Adding persistence without a stable namespace returned
  `persistence requires a Jido instance with a stable namespace`.
- Public solution: Configure a stable Jido namespace and a public persistence
  adapter, then start the Agent with `persistence: :inherit`.
- Core change: None proposed. The public operations are sufficient.
- Resolution: Keep the real wait. The example and Flow Waits guide now state
  that a wait needs both persistence and a stable instance namespace.

### EX-002: A runner called an Action callback directly (resolved)

- Example: [17_01 ReAct tool loop](17_ai_reasoning_flows/17_01_react_tool_loop/README.md).
- Classification: Resolved application-code and documentation friction.
- Attempted contract: Expand the next ReAct tool Flow by calling
  `ExpandNext.run/2` from a runner.
- Result: The stale call returned `{:error, :invalid_tool_calls}` after the
  Action input contract added routing and target data.
- Public solution: Use Agent preflight for graph inspection and run behavior
  through `Agent.cmd/3` or `Jido.Exec`, not an Action callback.
- Core change: None proposed. The example bypassed the public execution path.
- Resolution: `explain/0` and `preflight/1` are the supported inspection
  boundary. The graph-first guide now states that callers must use
  `Agent.cmd/3` or `Jido.Exec` for execution.

### EX-003: An inline Action host needs two declaration macro arities (resolved)

- Example: [01_05 Inline Actions](01_actions/01_05_inline_actions/README.md).
- Classification: Resolved documentation and authoring friction.
- Attempted contract: Import one three-argument host macro for an inline Action
  declaration with a `do` block.
- Result: Compilation failed with `undefined function inline_action/4`.
- Public solution: Define and import both arities. The four-argument form joins
  the option list and `do` block before it calls `parse_callback!/3`.
- Core change: None proposed. The public compiler API works after the host
  follows Elixir macro call shape.
- Resolution: The inline Action host guide now shows both arities before the
  owner example and explains how Elixir selects each form.

### EX-004: JSON Signal schemas need string keys (resolved)

- Example: [08_01 Signal Envelope](08_signals_and_messaging/08_01_signal_envelope/README.md).
- Classification: Resolved documentation and boundary friction.
- Attempted contract: Serialize a custom Signal created from a Joi object with
  atom keys.
- Result: `Jido.Signal.Codec.serialize/2` returned
  `{:json_encode_failed, "Signal data must contain JSON values or binary data"}`.
- Public solution: Use a string-key Joi schema for JSON-bound Signal data.
- Core change: None proposed. Atom-key Signal data remains valid inside one
  BEAM application.
- Resolution: The Signal data schema guide now puts the failing atom-key form
  beside the correct string-key JSON form, and the example links to it.

### EX-005: Agent output selectors require a declared output shape (resolved)

- Example: [06_02 Pure and Hosted Execution Parity](06_agent_server/06_02_pure_hosted_parity/README.md).
- Classification: Resolved documentation and authoring friction.
- Attempted contract: Select `output(:state)` and `output(:reply)` from an
  inline route Action that used the default broad output schema.
- Result: Agent compilation failed with `:unsupported_output_path` and named
  the missing `:state` field.
- Public solution: Declare an Action output schema that contains both selected
  fields.
- Core change: None proposed. Compile-time path validation prevented an unsafe
  route definition and gave a specific correction.
- Resolution: The route guide now states the `output_schema` rule beside its
  first state and reply selectors and names the compile error.

### EX-006: A reply-only route still needs explicit state projection (resolved)

- Example: [23_02 Specialist pipeline](23_collaborative_agent_systems/23_02_specialist_pipeline/README.md).
- Classification: Resolved documentation and authoring friction.
- Attempted contract: Return `%{reply: value}` from a stateless Agent route and
  select that field with `reply/2`.
- Result: Agent validation treated the complete Action output as candidate
  state and rejected the unrecognized `:reply` key.
- Public solution: Return both `state` and `reply`, declare both output fields,
  and select each with `state/1` and `reply/2`.
- Core change: None proposed. Explicit projection is safe and supported.
- Resolution: The route guide now states that reply selection does not disable
  default state mapping and gives both supported state choices.

### EX-007: Controlled declared-subtree removal (resolved)

- Example: [23_06 Nested organization](23_collaborative_agent_systems/23_06_nested_organization/README.md).
- Classification: Resolved Jido core gap.
- Attempted contract: Remove one declared department and its descendants while
  the company root remains active.
- Result: `Jido.AgentServer.remove_topology_member/4` removes one named member
  slot and its owned descendants from the current root activation.
- Public solution: The operation closes subtree admission, finishes accepted
  Turns by default, stops descendants before their parent, and keeps the root
  and sibling subtrees active. Repeated calls are safe. A partial timeout keeps
  removal pending so a retry can continue cleanup.
- Core change: Add the controlled operation to the public AgentServer facade.
  Keep the static declaration and durable child records unchanged. A new root
  activation creates the declared subtree again and restores saved state when
  persistence is enabled.
- Follow-up question: None.

### EX-008: Definition upgrade cannot replace the Agent origin module (resolved)

- Example: [24_08 Controlled Agent Upgrade](24_application_patterns/24_08_controlled_agent_upgrade/README.md).
- Classification: Resolved documentation and authoring friction.
- Attempted contract: Migrate an Account V1 Agent snapshot into an instance
  created directly from the compiled Account V2 module.
- Result: `Jido.upgrade_agent/4` rejected the candidate with
  `:upgrade_identity` because its origin module changed.
- Public solution: Use the V2 definition as a complete data template, preserve
  the saved origin module, instantiate the migrated state, and snapshot the
  result.
- Core change: None proposed. Stable origin is an intentional persistence and
  callback boundary.
- Resolution: The upgrade guide now states that the saved origin module is a
  stable identity and callback boundary and names `:upgrade_identity`.

### EX-009: Definition rollback is a new forward version (resolved)

- Example: [24_08 Controlled Agent Upgrade](24_application_patterns/24_08_controlled_agent_upgrade/README.md).
- Classification: Resolved documentation and operational-model friction.
- Attempted contract: Upgrade V1 to V2, then restore the V1 definition with
  version 1.
- Result: `Jido.upgrade_agent/4` rejected the reverse migration with
  `:definition_version_not_advanced`.
- Public solution: Publish version 3 with the earlier behavior and migrate V2
  state into the version 1 state shape.
- Core change: None proposed. Monotonic versions make upgrade history clear.
- Resolution: The upgrade guide now calls this a forward rollback and shows
  the version 2 to version 3 sequence.

### EX-010: Durable AI stream dispatch must be portable (resolved)

- Example: [24_06 Phoenix LiveView Chat](24_application_patterns/24_06_phoenix_liveview_chat/README.md).
- Classification: Resolved documentation and integration friction.
- Attempted contract: Send model stream Signals directly to the LiveView PID
  through `jido_ai_dispatch` during a durable Agent Turn.
- Result: AgentServer rejected the Turn because the PID in durable context was
  not portable.
- Public solution: Subscribe the LiveView to a conversation topic and use the
  portable `:pubsub` dispatch target in Turn context.
- Core change: None proposed. Durable context must stay portable.
- Resolution: The ReAct streaming guide now recommends PubSub for hosted web
  clients and limits PID dispatch to pure or transient local runs.

### EX-011: Dynamic runtime adoption and ownership transfer — resolved

- Example: [09_05 Logical ownership transfer](09_dynamic_agent_composition/09_05_logical_ownership_transfer/README.md).
- Classification: Resolved Jido core change.
- Attempted contract: Adopt an independent Agent into a live parent, transfer
  its runtime ownership to another parent, and apply owner-linked shutdown.
- Result: `Jido.transfer_agent_ownership/4` now adopts an unowned resident Agent
  or transfers it with the exact current `Jido.AgentOwnership` value. The
  activation-specific fence rejects stale owners, and a matching request ID
  makes the last accepted request idempotent.
- Public solution: Use stable child and owner Addresses. Pass `expected: nil`
  for adoption and the current ownership value for transfer. Use
  `Jido.agent_ownership/2` to read the current local relation.
- Core change: The child activation replaces its owner monitor before success
  is visible. An in-flight Turn continues without cancellation or replay. The
  current owner activation stops the child. Ownership survives worker recovery
  but is not persisted and is released by child activation loss, passivation,
  or instance shutdown.
- Follow-up question: None for EX-011. Durable or distributed ownership needs a
  separate lease and failover contract.

### EX-012: An indeterminate activation rejects direct stop (resolved)

- Example: [12_06 Indeterminate Write](12_persistence/12_06_indeterminate_write/README.md).
- Classification: Resolved documentation and operational-model friction.
- Attempted contract: Stop an activation after its persistence adapter saved a
  candidate revision but returned an indeterminate result.
- Result: `Jido.stop_agent/3` returned `{:error, :unsafe_resume}` because a
  normal stop could publish an unsafe checkpoint from the faulted process.
- Public solution: Configure persistence on the Jido instance, resolve the
  stable Agent Address, call `Jido.reconcile_agent/3`, verify replacement from the
  authoritative record, and then stop the replacement.
- Core change: None proposed. The safety boundary and recovery operation are
  public and testable.
- Resolution: The hibernate and activation guide now gives
  reconcile-before-stop as the standard operator response and no longer tells
  the reader to stop the blocked activation directly.

### EX-013: Explicit-Catalog document decode has a bundled codec selector (resolved)

- Examples: [02_04 Stored JSON](02_flow_authoring/02_04_stored_json/README.md)
  and [07_07 Codec documents](07_instance_catalog_documents/07_07_codec_documents/README.md).
- Classification: Resolved public API and documentation gap.
- Attempted contract: Decode a stored Flow or Agent document through
  `Jido.Codec.decode/2` or `decode_json/2` with an explicit trusted Catalog.
- Result: `Jido.Catalog.Discovery.bundled_codec/2` now selects the bundled Agent
  or Flow codec by exact document type and version without reading published
  state. Unknown types and unsupported versions return structured Codec Issues.
- Public solution: Select the bundled codec, then pass it through the public
  `:codec` option with the explicit trusted Catalog. The selector does not
  authorize Catalog targets.
- Core change: Complete. The public bundled selector removes the offline
  importer gap without adding higher-layer Agent or Flow dependencies to
  `Jido.Codec`.
- Follow-up question: None.
