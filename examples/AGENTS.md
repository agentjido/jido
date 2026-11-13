# Jido example instructions

These instructions apply to all files under `examples/`.

## Purpose

The examples are both a learning path and a living integration suite. Use
`table_of_contents.md` as the proposed learning order and coverage map.

Each example must:

- Teach one primary public contract or application pattern.
- Use the current public Jido API.
- Show production-shaped code.
- Have a deterministic offline run path.
- Test the behavior that its README claims.
- State what it proves and what it does not prove.
- Include failure, recovery, or cleanup behavior when it is part of the claim.

Before adding an example, confirm that it:

- Adds a distinct Jido contract, application pattern, or integration proof.
- Cannot be taught more clearly by extending an existing example.
- Has useful behavior that the offline suite can test.
- Belongs in Jido core examples rather than an ecosystem package or production
  guide.

Do not divide examples into Learn and Prove tracks. Put normal behavior,
validation, failure, recovery, and compatibility in the same sequence.

Small lessons should isolate one contract. Larger application examples can
combine many contracts when their composition is the subject of the example.

## Dogfood Jido core

Use examples as executable design probes. Implement the application with
current public Actions, Flows, Agents, Signals, Sessions, persistence, waits,
and telemetry before a new core abstraction is proposed.

Do not hide an awkward boundary with a private API, test-only callback, or
example-only runtime shim. A local fixture can replace an external service, but
it must keep the same Jido Flow and application boundary.

Every advanced example README must have a `Core Fit and Gaps` section. Record:

- Public contracts that compose cleanly.
- Repeated glue that might need a reusable helper.
- Missing public operations or unclear ownership.
- Persistence, portability, concurrency, recovery, or replay gaps.
- Weak error, telemetry, security, or testing contracts.
- Performance limits or control points that the application cannot express.

Classify each finding as application code, an ecosystem package concern, a
documentation gap, or a candidate Jido core change. Make each gap concrete and
reproducible. The example does not need to solve the gap.

## Learning order and scope

- Keep section and example numbers aligned with `table_of_contents.md`.
- Keep names and Signal types stable after an example is published.
- Update section READMEs and previous or next links after a move or renumber.
- Do not use a later chapter concept to explain an earlier chapter unless the
  dependency is explicit.
- The first-hour lessons extend one application across six lessons. Keep each
  lesson runnable and clear at its point in the sequence.
- Do not make one numbered example depend on private code from another
  numbered example.

## Action, Flow, and Agent authoring

Follow these rules:

1. Put the main Agent, Flow, or application module first in the primary source
   file.
2. Use `Jido.Joi` schemas at Agent, Action, Flow, Signal, and Plugin boundaries.
3. Use an inline Action or inline Flow step when only one owner uses the work.
4. Use a named Action when it is reused, needs a stable identity, is an
   extension point, or is the subject of the example.
5. Give every Flow an explicit `output` statement.
6. Add `output_schema` when it protects a concrete reusable result or teaches
   output validation. Do not add a broad schema only to fill the option.
7. Use JSON or direct definition forms only when the example teaches those
   forms.
8. Use `as:` for the main Agent routes that a reader calls.
9. Scope Signal types and sources to the section and example.
10. Use Action or Signal input for requested work.
11. Use execution context for runtime services and execution metadata.
12. Use Agent state for portable domain state.
13. Keep clients, callbacks, PIDs, ports, references, functions, and other
    temporary values out of Agent state, Signals, Sessions, Directives, and
    persisted values.
14. Do not call another `Jido.Action` module's `run/2` function directly. Use a
    Flow, an Agent route, or `Jido.Exec` so validation and instrumentation stay
    active.
15. Validate a complete external or model-selected plan before any side effect
    starts.
16. Give every retry, repair loop, tool loop, Map, and Iterate operation an
    explicit bound. Document the result when the bound is reached.
17. Return complete candidate Agent state. Keep post-commit effects in
    Directives and Plugin dispatch.
18. Use declarative topology when the lesson teaches declared topology. Do not
    add an Agent wrapper only to make topology look like another pattern.

One Action and an authored Flow use the same execution model. When a lesson
runs one Action, explain that Jido lowers it to a canonical one-step Flow.

## Communication and process boundaries

- Use Signals, replies, Directives, and declared connections for application
  communication.
- Do not use raw `send` or `receive` in reader-facing Action or Flow code.
- Raw messages are permitted in tests and local test support for deterministic
  barriers, monitors, and probes.
- Use bounded waits. If a test needs an intentional unbounded wait, prove that
  cancellation and cleanup always terminate it.
- Use stable `Jido.Agent.Ref` values when work must survive a process change,
  passivation, or client reconnect.
- Do not store a process identifier as durable or browser-facing identity.

## Runtime inspection and control

Use public APIs such as `Jido.call/4`, `Jido.cast/3`, `Jido.submit/4`,
`Jido.status/3`, `Jido.AgentServer.status/2`,
`Jido.AgentServer.snapshot/2`, `Jido.AgentServer.cancel_turn/3`, and public
telemetry events when they fit the lesson.

Follow these rules:

- Keep the operation under test separate from the code that observes it.
- Do not inspect private process state or depend on undocumented messages,
  functions, tables, or runtime structure.
- Do not add a hidden command, observer callback, or blocking callback only to
  make a test pass.
- Put deterministic blockers and probes in local test support.
- Do not present test support as application architecture.
- Treat `Jido.AgentServer.Status` as operational state.
- Treat `Jido.AgentServer.Snapshot` as a complete private snapshot. Do not send
  it directly to a browser or external caller. Build an application-owned
  public projection.

If a documented behavior cannot be observed or controlled with a clean public
API, record a core gap. Do not hide the gap with an example adapter.

## AI and external services

- Default AI examples use a deterministic `Jido.AI.InferenceClient`.
- Keep the same Action and Flow path in offline and live modes.
- Live model, MCP, database, object-store, and other service runners are
  opt-in.
- State the required service, environment variables, setup, possible cost,
  timeout, and cleanup.
- Fail with a clear setup message when an opt-in requirement is absent.
- Never put credentials in source, fixtures, Signals, Flow input, Agent state,
  Sessions, Threads, tool results, snapshots, telemetry, or test output.
- Provider request `options` are normal Flow input. They are not a secret
  channel.
- Give model retries, fallback models, tool rounds, output repair, token use,
  elapsed time, and cost explicit bounds.
- Record the model and usage when a fallback model serves a request.
- Keep MCP client implementation in `jido_connect`. Jido core receives MCP
  tools through `Jido.AI.ToolSource`.

Memory, retrieval, guardrails, middleware, evaluation, multimodal operations,
compaction, and long-running Session management can be application Flows. Do
not invent a core API for the example. Use the implementation pressure to
identify a justified core gap.

## File layout

Use this layout:

```text
examples/
  support/                    # Stable code used by two or more sections

  NN_section/
    README.md
    support/                  # Stable code used by two or more examples here

    NN_MM_example/
      README.md
      example.ex              # Main reader-facing source
      example_test.exs        # Colocated integration proof
      demo.exs                # Optional executable runner
      support/                # Scaffolding local to this example
      fixtures/               # Local JSON, media, and other input data
```

Apply these placement rules:

- Keep reader-facing code in the numbered example directory.
- Keep first-class Agents, Flows, Plugins, adapters, and worker roles at the
  example root when they are part of the lesson.
- Put fake services, probes, barriers, and other scaffolding in local
  `support/`.
- Move code to section support only when two or more examples need one stable
  building block.
- Move code to `examples/support/` only when two or more sections need it.
- Use `Jido.Examples.Support.*` for shared support modules.
- Use specific role names. Do not create generic `Helpers` modules.
- Prefer small local duplication when it keeps a lesson self-contained.
- Keep fixture data beside its consumer.
- Split files by domain role, not by line count.
- Do not hide a role that the lesson teaches in a generic support file.

## README contract

Every numbered example must have a short `README.md` with:

- The problem and visible result.
- The main contracts or pattern.
- The recommended reading order.
- An exact test command.
- An exact runner command when a runner exists.
- Expected output or expected state.
- Important failure, recovery, and cleanup behavior.
- A `Limits` section.
- A `Core Fit and Gaps` section for advanced examples.
- Links to source, tests, fixtures, and shared support.
- Previous and next links when sequence matters.

Use this structure:

```markdown
# NN_MM Example title

One sentence that states the problem and result.

## What you will learn

- Main Jido contract or application pattern.
- Important boundary or failure behavior.

## Read the code

Read [the main source](example.ex) first.

## Run it

`mix test.examples examples/NN_section/NN_MM_example --warnings-as-errors`

Expected result: state the visible result.

## Important behavior

State the main success, failure, recovery, and cleanup behavior.

## Limits

State what the example does not prove or support.

## Core Fit and Gaps

State what composes cleanly and record reproducible gaps.

## Files

- [Source](example.ex)
- [Tests](example_test.exs)
```

Section READMEs give the learning order and one short description per example.
Do not copy detailed implementation text into a section README.

Use comments for Jido boundaries and important design decisions. Do not explain
each code statement with a comment.

## Behavior tests

Every supported example must have a colocated `*_test.exs` file with
`@moduletag :integration`.

The tests must:

- Use public Jido APIs.
- Prove the main README claim.
- Cover the main success path.
- Cover the stated validation, failure, recovery, or cleanup path.
- Use deterministic adapters and explicit synchronization.
- Avoid `Process.sleep/1` and timing-only assertions.
- Confirm process and resource cleanup when the example starts children or
  external resources.
- Use unique IDs, namespaces, handler IDs, and temporary paths.
- Leave global application configuration as it was before the test.

Keep detailed core edge cases in `test/jido/`. Example tests must read as a
clear proof of documented behavior, not as a copy of the core test suite.

Run a focused example with:

```sh
mix test.examples examples/NN_section/NN_MM_example --warnings-as-errors
```

Run the full offline example suite after shared support, example discovery, or
more than one section changes:

```sh
mix test.examples --warnings-as-errors
```

## Executable runners

An offline `demo.exs` or `run.exs` must:

- Load its own reader-facing source and required public support files.
- Run from the repository root with the documented command.
- Avoid `test/support`, Mimic, ExUnit, and private test helpers.
- Produce one clear result and terminate.
- Return a nonzero exit status on failure.
- Need no credentials or network access.

Put live, paid, or external-service runners behind an explicit opt-in command.
Do not make an offline runner silently select a live provider.

## Inventory integrity

The folder tree is the source of truth for example inventory. Verify:

- Section and example IDs and order.
- Required README, source, and test files.
- README links and exact commands.
- Every supported example is included in `mix test.examples`.
- No stable example test is skipped.
- Every runner named in a README exists and runs.

Do not write manual example counts or dated pass totals in documentation unless
a tool generates and verifies them.

## Review checklist

1. Confirm the example's place in `table_of_contents.md`.
2. State its main public contract or application pattern.
3. Keep reader-facing source self-contained and production-shaped.
4. Check schemas, explicit Flow output, bounds, portability, and cleanup.
5. Check support-file scope and remove private cross-example dependencies.
6. Add or update the README, `Limits`, and `Core Fit and Gaps` sections.
7. Run the focused example test and every documented runner.
8. Run `mix format --check-formatted`.
9. Run the full example suite when the change has shared scope.
10. After a move or removal, delete empty directories and verify all links.
