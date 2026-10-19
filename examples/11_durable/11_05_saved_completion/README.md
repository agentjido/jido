# 11_05 Saved Completion

A report and its completed Turn survive a lost storage reply.

## What you will learn

- AgentServer saves candidate state and the terminal receipt together.
- A completed Flow does not run again after restore.
- A caller Pending handle is local; it does not survive Server loss.

## Read the code

Read [the Agent and report Flow](saved_completion.ex). The Flow returns a report
and completion count. It has no recovery code. AgentServer owns recovery.

## Important behavior

The test adapter saves the final record, then holds the storage reply. The test
kills the Server at that boundary. The replacement loads the completed Agent
with a count of one. Execution hooks confirm that completed work did not repeat.
A later request starts a new Turn and increases the count to two.

The barrier adapter and execution counter are
[test support](../../../test/examples/support/durable_completion_probe.ex), not
application code. Storage uses the existing File adapter.

## Limits

This proves process-loss recovery after a successful save. It does not provide
request deduplication, caller reply replay, or replay of post-commit effects.

## Run it

```sh
mix test test/examples/11_durable/11_05_saved_completion --include example --seed 0 --warnings-as-errors
```

Expected result: the success, recovery, and rejection assertions pass. Tests stop
the Agents and release all held test calls. No external service is required.

## Files

- [Source](saved_completion.ex)
- [Tests](../../../test/examples/11_durable/11_05_saved_completion/saved_completion_test.exs)

Previous: [Accepted Work](../11_04_accepted_work/README.md) | Next: [Durable Wait](../11_06_durable_wait/README.md)
