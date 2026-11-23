# 11_11 Share an inventory count

One counter records 12 items in bin A. Another counter reads 12 from the
warehouse desk's board.

## What you will learn

- Start a board from the topology root and read it from a member.
- Use a snapshot revision for a conditional patch after the turn commits.
- Use the result Signal to control a Statechart transition.

## Read the code

Start with the topology in [the source](example.ex). Then read [the behavior
tests](example_test.exs).

## Run it

`mix test.examples examples/11_built_in_capabilities/11_11_shared_blackboard --warnings-as-errors`

The second counter reads 12. When two counters write from the same revision,
one write succeeds and the other reports a conflict.

## Important behavior

The chart checks the result's request ID. On conflict it lets the counter
read the current board before deciding again. A restarted counter reads the
same board. Stopping the desk stops the board. A new desk starts from the
initial count of zero and rejects a revision from the old desk.

## Limits

The board uses memory on one BEAM node. Patch result Signals use best-effort
delivery. If a result is missing, read the board before choosing the next
action.

## Core Fit and Gaps

The owner, snapshot input, and patch Directive compose through existing
topology, Plugin, and Statechart contracts. The application owns request IDs
and reconciliation. A read can show current board values after a missed
result. It might be insufficient to tell which request changed a value.

Previous [Cancel a Statechart deadline](../11_10_statechart_deadline/README.md).
