# 20_05 Long-running ReAct Agent

Run one durable Agent across a long conversation. Keep the full committed
transcript in a local DETS database. Send ReAct only a bounded Session, with an
optional summary of older Turns. The final Turn reads Turn 1 with a tool.

## What you will learn

- Store each reply's `session_entries` in a database by Turn number and ID.
- Keep recent messages and request outcomes together. Keep attempt and review
  records in the archive.
- Use deterministic trimming or add a model-generated summary with a source
  range. Give ReAct a tool that can page through old messages, including tool
  calls and results.
- Recover a committed reply when its caller stops before writing the archive
  or acknowledging the result.

## Read the code

1. [Agent and application](long_running.ex) builds the bounded Session,
   submits the Turn, and reconciles the reply.
2. [Transcript](transcript.ex) saves the full Turn entries, pending Turn ID,
   and summary in a local database.
3. [Recall tool](recall_turn.ex) reads archived message pages from the same
   database. [Offline client](support/offline_client.ex) scripts the model
   calls and summary.

## Run it

From the repository root, run the integration tests.

```sh
mix test.examples examples/20_context_and_memory_flows/20_05_long_running_agent --warnings-as-errors
```

Run deterministic trimming with a short conversation.

```sh
mix run examples/20_context_and_memory_flows/20_05_long_running_agent/demo.exs --turns 8
```

Run 1,000 Turns with model-assisted compaction. Give `--directory` a new
directory to keep the database and Agent checkpoint after the run.

```sh
mix run examples/20_context_and_memory_flows/20_05_long_running_agent/demo.exs --turns 1000 --compaction model
```

The runner reports progress every 100 Turns. At the end, it checks the
archive count, the Agent revision, and the recall tool result. It also checks
that the original Turn 1 message has left the recent window. Without
`--directory`, the runner removes the temporary database and checkpoint.

## Important behavior

- **Deterministic compaction.** Select up to four recent complete Turns under
  a 12 KB encoded window budget. Keep each selected Turn's messages and
  outcomes as a group. If a group does not fit, leave it in the archive.
- **Model compaction.** Between Turns, send the previous summary and up to
  four newly expired Turns to a separate inference call. Cap its input and
  output. Store the replacement summary with the last source Turn number.
  A failed call keeps the last saved summary. Core ReAct still uses the
  deterministic window. The summary is conversation data. To use a real
  model in your application, set the model and inference client in
  `app.compaction`. The included runner uses the offline client in both modes.
- **Recall.** `recall_turn` accepts a Turn number, message number, and byte
  offset. Follow `next_offset` to read the next page and `next_message` to
  move to the next message. The archive API returns the complete Turn
  entries with their original IDs and payloads. Use the archived Turn number
  for recall. A rebuilt window assigns its own sequence numbers.
- **Recovery.** The application saves the pending Turn ID before submission.
  It writes the terminal reply to the archive before acknowledging it. A
  repeat archive write for the same data is safe. If the Turn's outcome is
  unknown, recovery reports the pending ID for reconciliation.

## Limits

This local example uses one archive writer and one durable Agent address.
DETS stands in for an application database. The offline model measures local
execution and storage. Provider latency, summary quality, and provider token
counts require separate checks. The 12 KB budget bounds the supplied history
and summary. New input, tool output, and the rest of the Flow payload need
their own budgets.

The fixture does one model call per ordinary Turn. The final Turn also runs
the recall tool and a second model call. Tool work with side effects needs
its own idempotency and reconciliation. The demo leaves failed or unresolved
Turns pending for inspection.

## Core Fit and Gaps

- **Application code.** The transcript, size budget, compaction policy, and
  recall authorization belong to the application. A shared database needs
  transactional reservation and an Agent or tenant key.
- **Candidate Jido core change.** A caller can retain an exact terminal
  result and acknowledge it after persistence. Acknowledgement currently
  stops and restores a resident Agent. This cost applies to every Turn in
  this example.
- **Candidate Jido core change.** A prompt limit applies at projection.
  Application code currently builds the smaller Session before the Turn
  enters the graph.

## Files

- [Runner](demo.exs)
- [Integration tests](long_running_test.exs)

[Previous example](../20_04_session_rollover/README.md)
