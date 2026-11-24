# 17_06 Build and Work a Task List

Ask a Jido AI Agent to review a release. Its reasoning Flow builds an ordered
task list, and a work Flow reports progress as it works through the list.

## What you will learn

- Use a structured model response to select tasks from an allowlist.
- Use a Jido Flow to work through the list across Agent Turns and return a
  progress reply after each Turn.

## Read the code

Read the [Agent](example.ex), then the [planning Flow](plan.ex) and the
[work Flow](work.ex). Finish with the [hosted tests](example_test.exs).

## Run it

```sh
mix run examples/17_ai_reasoning_flows/17_06_reasoning_task_list/demo.exs
mix test.examples examples/17_ai_reasoning_flows/17_06_reasoning_task_list --warnings-as-errors
```

The demo shows three pending tasks after planning. After two advance
requests, it shows `1 of 3 completed` with one task in each state. The final
reply shows `3 of 3 completed` and includes the release changes, check
counts, and release notes status.

## Important behavior

- The reasoning Flow makes one structured model call with a five-second
  provider deadline, a 128-token output limit, and zero retries. It checks the
  full plan for unknown or duplicate tasks before it changes Agent state.
- Each advance request finishes the active task, if present, and starts the
  next pending task. The work Flow reads release facts from Agent state and
  puts the result on the completed task. A completed check can report a failure.
- A rejected plan leaves the current list intact. The next advance request can
  continue it. A valid new plan replaces the current list. An advance request
  after completion returns the same progress.

## Limits

The example uses one list per Agent and up to three tasks. The demo and tests
use a deterministic inference client and need no credentials. Agent state in
this example lasts for the lifetime of the Agent.

## Core Fit and Gaps

The AI request route and the work route share one Agent state schema. Each
Flow returns complete candidate state and a small reply. AgentServer commits
the task updates together, so the reply shows the finished task and the next
active task from the same Turn. The allowlist, duplicate check, and progress
fields belong to the application.

The AI Agent authoring docs can show this custom state pattern. The
`use Jido.AI.Agent` macro declares a state block, so a second block fails to
compile. This example uses `Jido.Agent` with `Jido.AI.Agent.Plugin` to define
its own state schema.

## Files

- [Agent](example.ex)
- [Task list schema and progress reply](task_list.ex)
- [Planning Flow](plan.ex)
- [Work Flow](work.ex)
- [Integration tests](example_test.exs)
- [Offline demo](demo.exs)
- [Plan fixture client](support/plan_client.ex)
- [Shared offline inference client](../../support/offline_inference_client.ex)

[Previous lesson](../17_05_custom_reasoning_flow/README.md) |
[Next application example](../../24_application_patterns/24_09_support_desk/README.md)
