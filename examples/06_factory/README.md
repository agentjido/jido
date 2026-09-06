# Factory examples

These four examples build a live conversation and then a factory with its own
Agent tree. All model calls use `req_llm` directly. There is no `jido_ai` layer.

| Example | What it adds |
| --- | --- |
| [06_01_live_conversation](06_01_live_conversation/conversation.ex) | One Agent, a live model, and text history across turns. |
| [06_02_three_agent_system](06_02_three_agent_system/system.ex) | Three main Agents, a work queue, temporary worker Agents, inspection tools, and result Signals. |
| [06_03_department_factory](06_03_department_factory/orchestrator.ex) | Four real department heads and an explicit dependency plan. |
| [06_04_flow_factory](06_04_flow_factory/README.md) | A large Flow coordinates nine workers, parallel builds and reviews, and two bounded repair cycles. |

## Add a key and start

Put your provider key in the repository's `.env` file. For the default Anthropic
model, use `ANTHROPIC_API_KEY`. Set `FACTORY_MODEL` to change the provider and
model. The selected provider must support tools for examples 2 and 3.

To use the OpenAI key, set these values in `.env`:

```dotenv
FACTORY_MODEL=openai:gpt-4.1-mini
OPENAI_API_KEY=your-key
```

If `OPENAI_API_KEY` is already set in the file, add only `FACTORY_MODEL`.

Run the conversational agent from the repository root:

```sh
mix run examples/06_factory/chat.exs conversation
```

The shell launcher loads the project `.env` with Dotenvy and makes its values
available to ReqLLM. Existing shell environment variables take precedence.
The `.env` file is ignored by Git. A missing file is allowed when the shell
already supplies the keys. See the [Dotenvy API](https://hexdocs.pm/dotenvy/Dotenvy.html).

You can also set the key in your shell and use IEx:

```sh
export ANTHROPIC_API_KEY='your-key'
export FACTORY_MODEL='anthropic:claude-haiku-4-5'
mix deps.get
iex -S mix
```

Do not put the key in a source file.
Model clients and request options stay in runtime context, outside Agent state
and Signals. See the [ReqLLM API](https://req-llm.hexdocs.pm/ReqLLM.html) for
model selection and provider key options.

## 1. A basic live conversation

In IEx:

```elixir
alias Jido.Examples.Factory.IEx, as: FactoryChat
{:ok, chat} = FactoryChat.start(:conversation)
FactoryChat.say(chat, "My name is Pat.")
FactoryChat.say(chat, "What is my name?")
FactoryChat.chat(chat)
```

`say/2` waits for the answer in this first example. The Agent stores system,
user, and assistant text. Failed model calls preserve committed history.
Each request has an ID, and repeated IDs are rejected before a model call.

Chat sessions stream text by default with `ReqLLM.stream_text/3`. Text appears
as it arrives. The terminal does not repeat the full answer when the turn ends.
Streamed text is temporary output; only a complete successful answer enters
conversation history. If the stream fails or stops early, the terminal marks
any displayed text as partial. A failed turn cannot remove text already shown.

Tool arguments are assembled before a tool runs. Text can continue after a tool
result. Factory events can print between text chunks. The prompt uses simple
terminal lines and does not restore text that you were typing when an event
arrives. Stream callbacks and HTTP resources stay outside Agent state and
Signals. Stopping the owner closes a pending streaming connection.

To wait for a full response without streamed output in IEx:

```elixir
{:ok, chat} = FactoryChat.start(:conversation, context: %{stream: false})
```

The direct Agent API keeps non-streaming requests by default. To receive text
chunks there, pass `context: %{stream: true, on_stream: callback}`. The callback
accepts the request ID and one of `:start`, `{:delta, text}`, or `:round_end`.
The normal Agent reply still contains the complete answer.

The prompt prints the selected model at startup. Request errors show the HTTP
status and provider message. An HTTP 401 error means the provider rejected the
key. For the default model, replace `ANTHROPIC_API_KEY` in `.env`, then restart
the command. An exported shell value takes precedence; remove an old override
with `unset ANTHROPIC_API_KEY` before you restart. For another provider, set
`FACTORY_MODEL` and supply that provider's key.

Error replies remove the active API key and omit raw request bodies, response
bodies, and headers. The same error details reach the conversation and factory
when a background model request fails.

The direct Agent API is also available:

```elixir
{:ok, _} = Jido.start_link(name: ChatExample)
{:ok, agent} = Jido.start_agent(ChatExample,
  Jido.Examples.Factory.LiveConversation,
  exec_opts: [timeout: 50_000])

Jido.Examples.Factory.LiveConversation.chat(agent, "message-1", "Hello",
  timeout: 60_000)
```

## 2. Three Agents and Signal exchange

```elixir
{:ok, system} = FactoryChat.start(:workshop)
FactoryChat.chat(system)
```

Try: `Start a factory job to make a demo report.` Then ask for its status.
The model selects `submit_work`; its callback sends a `factory.command` Signal
to the factory. The tool returns a queued job receipt. A Scheduler Plugin sends
a queue check Signal each second, including when the queue is empty. If the
factory is idle, it starts the first queued item in a temporary worker Agent.
Only one worker can be active. The worker runs three timed demonstration steps
and sends progress Signals to the factory. The factory sends events to the
system owner, which forwards them to the conversation Agent.

Try: `add 3 jobs to the factory`. The model uses `submit_jobs` to create three
numbered demo jobs in one command. Each job has a distinct ID. You can also
supply a goal for each job. The batch is accepted only if all goals are valid
and the factory has space for every job. A repeated batch returns the same IDs.

```text
System
  Conversation -- commands and inspection --> Factory manager
       ^                                           |
       | factory.event                             | starts one child
       +------------- System <---------------------+
                                                   |
                                             Work item Agent
                                                   |
                                     factory.worker.progress
```

There are three main Agents and at most one temporary worker Agent. These
workers perform demonstration steps; they do not call an LLM or build an
external product. The manager owns queue order and job status. Workers own
their step timers. This separates scheduling from item execution.

Completion stops the worker. The next queue check can start another item.
Pause stops the worker and saves its last reported step. Resume places the item
at the end of the queue and starts a new worker attempt on a later check.
Cancel stops the worker and removes the item from the queue. Results from old
attempts are rejected. An unexpected worker exit fails the item and releases
the active slot. A failed item does not retry automatically.

The IEx observer prints committed factory events even while a model request is
pending. `say/2` returns after the conversation request commits; the answer
prints later. A second message is rejected while a model request is active.

Available model tools:

- `submit_work(goal)` — accept one job per conversation request ID.
- `submit_jobs(count, goals)` — queue up to 20 workshop jobs per conversation
  request ID. An empty or omitted goals list creates numbered demo goals.
  A supplied list must contain exactly `count` nonblank goals.
- `factory_status()` — return jobs, results, queue order, active worker ID,
  status counts, capacity, and scheduler activity.
- `factory_job(job_id)` — read one job's progress, result, worker ID, and queue position.
- `factory_events(job_id)` — read recent factory events; use an empty ID for all jobs.
- `pause_work(job_id)` — stop new work from starting.
- `resume_work(job_id)` — continue pending work.
- `cancel_work(job_id)` — abandon the job and reject late results.

The chat prompt also accepts these commands without an LLM request:

| Input | Result |
| --- | --- |
| `/status` | Print factory jobs. |
| `/job ID` | Inspect one job and its queue position. |
| `/events` | Print the last 100 factory events. |
| `/pause ID` | Pause that job. |
| `/resume ID` | Resume that job. |
| `/cancel ID` | Cancel that job. |
| `/back` | Return to IEx. Keep the factory running. |
| `/quit` | Stop this session and its Agent tree. |

Try: `Inspect the factory queue and scheduler. What is running?` After a job
finishes, ask: `Inspect that job and its events. What was the result?`

Use `FactoryChat.status(system)`, `FactoryChat.job(system, id)`, `FactoryChat.events(system)`, or
`FactoryChat.stop(system)` from IEx. The text prompt is small; events can print
while you type. It does not provide full-screen terminal editing.

## 3. A factory with department heads

```elixir
{:ok, factory} = FactoryChat.start(:departments)
FactoryChat.chat(factory)
```

Try: `Prepare a design and implementation proposal for a support ticket triage service.`

This starts seven Agents: the system owner, conversation, factory orchestrator,
and four department heads. The orchestrator owns this fixed plan:

```text
Research -----+
              +--> Build --> Quality
Design -------+
```

Research and Design run concurrently. Build receives their actual text
artifacts. Quality receives the Build artifact. Each department calls the live
model and commits its own result. The orchestrator accepts only results that
match the active job, department, and attempt ID.

This first plan produces Markdown text in Agent state. Research has no web
access. Build produces a proposal; it does not modify a repository. Quality
produces a review; a completed job does not mean that code passed tests or that
the review approved it. Ask for the result, or inspect it in IEx:

```elixir
{:ok, %{jobs: jobs}} = FactoryChat.status(factory)
# Use the job ID printed by the event observer:
job = Map.fetch!(jobs, "the-job-id")
IO.puts(job.stages["quality"].text)
```

The [orchestrator plan](orchestrator-plan.md) describes the larger factory,
department workers, plan revisions, delivery, approvals, budgets, and recovery.

## 4. A larger Flow across sub-agents

```sh
mix run examples/06_factory/06_04_flow_factory/demo.exs
mix run examples/06_factory/06_04_flow_factory/demo.exs --live "Design CSV export"
```

The local demonstration needs no key. The live option loads `.env` and calls
ReqLLM. The Flow joins Research and Design, maps work to API, UI, and Test
Agents, integrates their artifacts, and requests Quality and optional Security
reviews. Iterate allows two repairs before the Flow fails. Handoff runs only
after acceptance. A Mission Agent remains available for inspection and
cancellation while the Flow runs in its Plugin.

This example produces a software proposal. It does not change a repository or
run software tests. See its [guide, graph, and IEx API](06_04_flow_factory/README.md)
and [verification report](../../docs/examples/flow-factory-results.md).

## Run without IEx

```sh
mix run examples/06_factory/chat.exs conversation
mix run examples/06_factory/chat.exs workshop
mix run examples/06_factory/chat.exs departments
```

The script stops its session when the prompt ends. To leave the factory running
and return to a shell inside the same VM, use IEx and `/back`.

## Boundaries and limits

The following limits apply to the first three examples. The Flow factory has
its own [execution limits](06_04_flow_factory/README.md#agent-and-execution-boundaries).

- The first conversation example waits inside one Agent turn. System examples
  start model tasks after commit, so the conversation can receive events.
- Model loops permit at most five requests and four tools per response. Agent
  execution limits the basic and department calls to 50 seconds in the demo
  launcher. Managed tasks have a two-minute deadline. HTTP receive timeout is
  30 seconds. ReqLLM's separate total-timeout task is disabled to keep local
  request execution within the Jido task lifecycle.
- The orchestrator admits one active goal, at most two plan steps at a time,
  and retains at most 20 jobs. Cancelled department calls can still be finishing
  when another goal is admitted. Events retain the latest 100 entries. Text
  history grows for the session; context compaction is future work.
- Pause lets active department calls finish. Cancel stops waiting for their
  results and starts no further steps. Already running department calls can
  finish within their execution deadline. Stopping the owner stops the tree.
  Cancellation cannot undo provider work or charges that already occurred.
- A successful command reply confirms the state commit. It does not confirm
  all post-commit Directives. The launcher follows startup with another turn
  before it returns a ready session.
- Model tools can commit factory work before the conversation has an answer.
  A later model failure does not undo that work. Repeated submit IDs return
  the same job for the same goal; a changed goal with that ID is rejected.
  Batch jobs use IDs such as `request-id/1` and `request-id/2`. One batch per
  conversation request is allowed. Changed goals under the same batch ID are
  rejected. The batch tool is available only in workshop mode.
- Tools validate arguments with Zoi before sending a factory Signal. Invalid
  arguments return a clear tool error so the model can correct the call.
- State checkpoints are not a durable work queue. These examples do not enable
  disk persistence, delivery acknowledgements, or automatic replay after loss.
  Internal asynchronous result delivery is best effort under overload. Runtime
  context is released when a mission ends and is lost if its Plugin restarts.
  Restart the demo after a lost active attempt. The plan describes recovery work.

## Tests

```sh
mix test --include example test/examples/06_factory
```

For a live OpenAI or other configured provider check:

```sh
mix run examples/06_factory/workshop_probe.exs
```

This probe makes live model requests. It sends `add 3 jobs to the factory` and
checks three distinct demo jobs, processing order, result feedback, and worker
cleanup. It stops its session when the probe ends.

Tests use real Agents, Plugins, child processes, timers, and ReqLLM request
encoding and decoding. A local HTTP adapter supplies fixed provider responses
and timing barriers. Streaming tests use a local HTTP server with SSE chunks
through the real Finch transport. No live key or external network request is required. These tests
verify control flow; they do not verify a live provider account or model quality.

See the [verification report](../../docs/examples/factory-results.md).
