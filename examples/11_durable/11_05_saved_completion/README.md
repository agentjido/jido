# 11_05 Saved Completion

Status: **Proposed outline. No executable source or tests yet.**

Show the failure window between the final storage write and the caller reply.

## Planned code

Keep the Flow as the current Turn. Save the candidate Agent state and terminal
Turn receipt together. If that write succeeds and its reply is lost, restore the
completed Agent without executing or applying the Flow again.

```text
confirmed graph → final Agent + completion in one write → caller reply
                                      CRASH ↑
restore → completed Agent; no second Flow execution
```

## Current evidence and lesson gap

Core implements this contract. The lost-completion-reply test in
[durable Turn tests](../../../test/jido/agent_server/durable_turn_test.exs) proves it.
The dedicated example remains an outline until it can teach this boundary through
an application-shaped adapter without copying the Core fault matrix.

## Acceptance tests for the lesson

- Lose the final commit reply and restore the completed Turn.
- Prove that completed Actions do not repeat.
- Prove that the next state-changing Turn starts after completion.
- Distinguish a local Pending handle from the saved terminal Turn receipt.

## Limits

There is no background result delivery or reducer against newer Agent state.
Other state-changing Turns wait while the Flow runs. A repeated Signal creates
a new Turn. Exactly-once caller delivery and external I/O remain separate concerns.

## Run status

There is no run command for this outline. Do not add passing placeholders or
skipped tests. Add source and a focused behavior test when this stage is built.

Previous: [Accepted Work](../11_04_accepted_work/README.md) | Next: [Durable Wait — proposed](../11_06_durable_wait/README.md)
