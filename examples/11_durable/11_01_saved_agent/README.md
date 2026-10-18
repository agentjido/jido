# 11_01 Saved Agent State

Committed Agent state survives abrupt loss of its entire BEAM process.

This example proves that committed Agent state restores after BEAM loss.
Persistence also enables Flow recovery; the next example interrupts a running Flow.

## What you will learn

- A successful persistent Turn confirms the saved Agent and revision.
- A new BEAM can restore that record with the same namespace, Agent ID, and store.
- Required restore never replaces a missing record with fresh state.

## Read the code

Read [the Agent](saved_agent.ex), then [its Flow](request_report.ex), then [the test](../../../test/examples/11_durable/11_01_saved_agent/saved_agent_test.exs).
The Flow normalizes the topic, rejects an empty topic, and accepts one report
request. The test owns BEAM startup, crash control, and cleanup; those operations
are not part of the Agent.

## Run it

```sh
mix test test/examples/11_durable/11_01_saved_agent --include example --seed 0 --warnings-as-errors
```

Expected result: the last confirmed Agent and revision survive `SIGKILL`
and restore in a fresh BEAM. A failed Flow keeps Agent state unchanged, but saves
its acceptance and failure in new revisions. Missing required state fails readiness.

## Current application API

```elixir
alias Jido.Examples.Durable.SavedAgent
alias Jido.AgentServer, as: Server

{:ok, _instance} = Jido.start_link(name: ReportExample, namespace: "reports")
store = {Jido.Persistence.File, path: "tmp/report-example"}
opts = [id: "report-agent", persistence: store]

{:ok, server} = Jido.start_agent(ReportExample, SavedAgent,
  Keyword.put(opts, :persistence_mode, :create))
:ok = Server.await_ready(server)
{:ok, signal} = SavedAgent.request_signal(%{report_id: "report-42", topic: "OTP"})
{:ok, agent, []} = Server.call(server, signal)
# agent.state.status == :requested
```

In a fresh BEAM, load the same code, start the same instance namespace, and use
`persistence_mode: :restore` with the same ID and store. Wait for readiness
before reading the restored Agent. The behavior test executes both BEAM lifetimes.
Use a new path or ID for another `:create` run.

## Store ownership

The application selects `Jido.Persistence.File` and its directory. This adapter
uses files directly and has no Store process to supervise. AgentServer writes
the committed Agent record. The test starts the reader only after the writer
BEAM has exited, so one BEAM owns the directory at a time. AgentServer uses the
same adapter for Flow progress records.

## Important behavior

```text
writer BEAM: create → run request Flow → commit → reject invalid Flow → SIGKILL
reader BEAM: restore → compare complete snapshot → reject repeated request → stop
```

The test waits for the writer BEAM to exit before opening its store in the
reader. It does not hibernate, save at shutdown, or copy state between nodes.
Both the accepted Agent and its revision must match. The repeated request is
rejected by a domain-state guard; this is not a durable command receipt API.
Cleanup monitors BEAM exit and confirms that the restored Agent stops.

## Limits

Storage remains on the same host and code stays compatible. The File adapter
uses atomic rename and one BEAM writer at a time. This test proves process-loss
recovery, not power-loss, host-loss, or storage-loss durability.

The request Flow runs as one persistent Agent Turn. AgentServer saves acceptance,
step progress, and completion. This test kills the BEAM after completion, so it
does not prove recovery during a step. [Saved Progress](../11_02_saved_progress/README.md)
proves the five-completed, sixth-interrupted recovery rule. The saved request is
a domain fact; later report work needs its own Turn. There is no external I/O
or exactly-once delivery claim.

Previous: [Durable overview](../README.md) | Next: [Saved Progress](../11_02_saved_progress/README.md)
