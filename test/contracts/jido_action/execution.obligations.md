---
modules:
  - Jido.Exec
  - Jido.Exec.Compiler
  - Jido.Exec.Fact
  - Jido.Exec.Fact.LocalValue
  - Jido.Exec.Frame
  - Jido.Exec.Node.Choice
  - Jido.Exec.Node.Choice.Branch
  - Jido.Exec.Node.Choice.Selector
  - Jido.Exec.Node.Handoff
  - Jido.Exec.Node.Invoke
  - Jido.Exec.Node.Invoke.Finish
  - Jido.Exec.Node.Input
  - Jido.Exec.Node.Loop
  - Jido.Exec.Node.Loop.Start
  - Jido.Exec.Node.Map
  - Jido.Exec.Node.Map.Collection
  - Jido.Exec.Node.Output
  - Jido.Exec.Portable
  - Jido.Exec.Runtime
  - Jido.Exec.Source
  - Jido.Exec.Telemetry
  - Jido.Exec.ValueResolver
---
# Execution public promise obligations

## Purpose

Check focused facets of the [reviewed public promises](../../../guides/public-api-contract-review.md). The module reference defines the supported API. Passing tags are evidence for these facets, not complete branch or acceptance-matrix coverage.

### jido_action.execution.I17 — Choice selects the first match or its distinct default
- **scope:** `Jido.Exec.run/4, Jido.Exec.compile/2`
- **must:** Choice conditions run in authored order. Run only the first matching Action, or the default when none match. An option named fallback is an ordinary option distinct from the default. A failed selected Action does not trigger fallback. Compilation and Runic reconstruction preserve these rules.
- **kind:** functional
- **status:** active

### jido_action.execution.I18 — Policy bounds attempts and preserves outcome order
- **scope:** `Jido.Exec.run/4, Jido.Exec.start/6`
- **must:** Timeout applies to each attempt; max_attempts counts the first attempt and retries only eligible errors. Apply one concurrency policy to nested and collection work while Reduce and Iterate remain serial. Halting failure stops new admission while admitted work can finish. Defined result and failure order do not depend on completion order.
- **kind:** ordering
- **status:** active

### jido_action.execution.I19 — Effects retain canonical order without dispatch
- **scope:** `Jido.Exec.run/4, Jido.Exec.result/1, Jido.Exec.result/2`
- **must:** Return successful component effects in dependency then component order, with nested Flows at their parent position and collections in input or iteration order. Preserve duplicates. Failed output, failed items, cancellation, and uncertain execution expose no executable effect batch. Exec never performs the requests.
- **kind:** ordering
- **status:** active

### jido_action.execution.I20 — Execution follows caller and Runner process ownership
- **scope:** `Jido.Exec.run/4, Jido.Exec.start/6, Runic.Runner`
- **must:** Immediate Action failures cannot exit a live caller. Caller exit stops immediate work. Release owned tasks on completion, timeout, and termination. Keep the caller group leader and honor the selected local Task Supervisor. Managed work survives caller exit; successful Runner stop or cancel waits for owned tasks to exit, while failed persistent stop keeps its worker running. Unlinked user processes and custom executors require caller-owned cleanup.
- **kind:** functional
- **status:** active

### jido_action.execution.I21 — Managed results respect input scope and progress
- **scope:** `Jido.Exec.start/6, Jido.Exec.step/2, Jido.Exec.result/1, Jido.Exec.result/2`
- **must:** Read the input admitted by start, rejecting active, stopped, failed, foreign, or uncertain work as documented. Later input occurrences cannot replace its result. A manual step dispatches one scheduler unit and can report busy or complete; complete does not mean successful. Computed success is separate from Store acknowledgement. Native Runner control and lookup errors can retain atom reasons.
- **kind:** functional
- **status:** active

### jido_action.execution.I22 — Recovery preserves acknowledged stored progress
- **scope:** `Jido.Exec.resume/4, Runic.Runner.Store`
- **must:** Restore acknowledged stored completed work and continue remaining Action, Map, Iterate, nested Flow, Invoke, and Handoff progress with the same public value and effects. Use Runic hybrid fact rehydration by default when the Store supports fact storage so historical facts stay as references and the active frontier loads. Use full recovery for a Store without fact storage and for a native Batch unless the caller selects a supported specific recovery mode. Preserve dynamic invocation occurrence identity and reject incompatible changed targets. Resume requires runtime context and policy again. Guard snapshot projection after loss of live observations. Work completed after the last acknowledged checkpoint can repeat; no exactly-once execution or effect delivery is promised.
- **kind:** persisted-format
- **status:** active

### jido_action.execution.I23 — Telemetry retains bounded documented event shapes
- **scope:** `Jido.Exec.Telemetry, Jido.Exec.run/4, Jido.Exec.start/6`
- **must:** Emit documented Action-attempt and immediate-Flow events with measurements, outcome, and correlation fields. Start and stop metadata omit params, context, results, and full errors. Retries have separate attempt identities. Managed runtime events belong to Runic. Timeout or process death can prevent Action stop events; caller death can prevent Flow stop.
- **kind:** functional
- **status:** active

### jido_action.execution.I24 — Effect identity excludes retry attempt identity
- **scope:** `Jido.Exec.effect_id/4`
- **must:** For fixed execution, activation, output, and effect index, derive the same logical effect identity across attempts. A changed output identity or index can change it. The host owns deduplication and effect delivery; the identity does not provide exactly-once effects.
- **kind:** functional
- **status:** active

### jido_action.execution.I25 — Execution hosts own Action capabilities
- **scope:** `Jido.Exec.supports?/2, Jido.Exec.Runtime`
- **must:** Report only capabilities that the execution host gives to an Action callback. Ordinary execution reports no wait capability. Wait hosts report the wait capability, including through nested Flow and Invoke calls. Strip caller and bound values for the reserved `:jido_exec_capabilities` key and internal wait-host key. Return false for missing, unknown, or malformed capability lists. Require a map Action context.
- **kind:** security
- **status:** active
