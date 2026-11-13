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
