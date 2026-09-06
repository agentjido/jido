> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../migration/10-execution-record.md) for the migration result.

# Factory example results

Date: 2026-09-04.

The Factory group has four runnable examples and 57 tests. The latest
[Flow factory results](flow-factory-results.md) cover the fourth example and
its 14 tests. The initial three examples and shared streaming have 43 tests. Model
calls use ReqLLM directly. The dependency resolved to `req_llm 1.22.0`; no Jido
peer version range was changed for this work.

## Verified behavior

| Example | Tests | Evidence |
| --- | ---: | --- |
| Live Conversation | 4 | Real ReqLLM HTTP encoding and decoding, history, duplicate rejection, safe authentication errors, failed turns, and a bounded tool loop |
| Three-Agent System | 26 | Model tools, validated batch creation, distinct job IDs, retries, factory inspection, a one-second queue schedule, one active worker, FIFO order, worker failure and cleanup, pause/resume/cancel, stale progress, event delivery during model work, IEx, and error output |
| Department Factory | 4 | Concurrent Research and Design, Build input dependencies, Quality input, result identity, pause/cancel, failure, and complete tree shutdown |
| Shared streaming | 9 | Text before completion, complete history commits, split tool arguments, batch submission, feedback during a stream, terminal output without repeats, partial-stream failure, authentication errors, and connection cleanup |
| Flow Factory | 14 | Nine workers, parallel joins, ordered Map, nested Flows, security Choice, bounded repair, correlated artifacts, live request parsing, cancellation, deadlines, and cleanup |

The HTTP fixtures use the real ReqLLM request and response path. They supply
fixed Anthropic response bodies, including HTTP 401 errors. A live request with
the local `.env` key returned HTTP 401: `API key is invalid.` The request used
the key from that file. No shell or application key replaced it. A second live
check with `OPENAI_API_KEY` and `openai:gpt-4.1-mini` succeeded through the chat
launcher. It returned a one-sentence explanation of molecular biology. The local
`.env` now selects that model. The live workshop probe also passed with this
provider. The model used factory status, submission, job inspection, and event
inspection tools. The current probe sends `add 3 jobs to the factory`. It created
three distinct numbered demo jobs in one batch. All three completed in order
with one worker at a time. Each worker stopped after completion. Live department work has not been
checked with this provider.

## Checks

These are the initial checks for the first three examples. The latest Flow
factory report records the new tests and the rerun of these 43 tests.

- `mix test --include integration test/examples/06_factory`: 43 passed.
- `mix run examples/06_factory/workshop_probe.exs`: passed with `openai:gpt-4.1-mini`.
- `mix q`: passed, including Dialyzer with no errors.
- `mix test`: 698 of 699 passed, with 197 excluded. The sole failure is the
  previously documented cluster ownership assertion in
  `test/jido/agent/distributed_authority_test.exs:32`. See
  [DIST-03 results](dist-03-results.md).
- Local Markdown links in the new group and profiles resolve.

## Runtime findings

An Agent command returns after its state commit, before all Directives have
finished. The IEx launcher follows bootstrap with another turn to wait for
child creation.

ReqLLM's finite total-timeout option uses an unlinked HTTP task. The example
sets that option to infinity and uses Jido-owned execution deadlines instead.
The tests confirm that owner shutdown stops a pending local HTTP task.

The terminal session permits repeated cleanup. `/quit` stops the session, and
the script can safely run its final cleanup afterward.

Model errors now retain the provider message and HTTP status. The error names
the key setting to check for HTTP 401. It removes the active key and omits raw
request and response fields. These details reach terminal output and background
result Signals. Tests check that a failed request preserves history and that
the prompt can accept the next message.

Chat sessions now stream by default. ReqLLM consumes each stream once and
assembles the full response and tool arguments. Only complete responses enter
history. Displayed text is temporary and cannot be removed by a failed turn.
The local SSE tests show text before the provider finishes, and show that
owner shutdown closes the HTTP connection. The live conversation and workshop
checks use streaming with `openai:gpt-4.1-mini`.

ReqLLM tools with a JSON Schema do not compile that schema for runtime input
validation. The factory tools now parse inputs with Zoi before sending Signals.
Invalid input returns a clear error to the model. The batch command uses one
state commit for all jobs, checks capacity first, and assigns distinct IDs.
Retries return the same jobs and do not emit new acceptance events.

## Current scope

The workshop has three main Agents and at most one temporary work item Agent.
The manager checks its FIFO queue each second and starts no new worker while
one is active. Pause and cancel stop the current worker. Resume queues a new
attempt from the last reported step. Worker failure releases the slot. These
workers perform timed demonstration steps and do not make model requests.

The department factory
produces text artifacts through four real Agents. It does not run generated
code, perform web research, or deliver an external product. The examples do
not enable durable replay. See the [run guide](../../examples/06_factory/README.md)
and [orchestrator plan](../../examples/06_factory/orchestrator-plan.md).
