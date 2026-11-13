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
