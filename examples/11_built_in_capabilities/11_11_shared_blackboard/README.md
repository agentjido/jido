# 11_11 Share an inventory count

One counter records 12 items in bin A. Another counter reads 12 from the
warehouse desk's board.

## What you will learn

- Start a board from the topology root and read it from a member.
- Use a snapshot revision for a conditional patch after the turn commits.
- Use the result Signal to control a Statechart transition.
- Start a board for each inventory job and reopen it with the same Agent Address.
- Compare one shared revision with independent revisions for 20 and 100 counters.

## Read the code

Start with the [desk and counters](example.ex). Read the [job board
owner](job_board.ex) to see how to choose a name at runtime. Then read the
[lifecycle tests](example_test.exs) and the [swarm tests](swarm_test.exs).

## Run it

`mix test.examples examples/11_built_in_capabilities/11_11_shared_blackboard --warnings-as-errors`

The second counter reads 12. When two counters write from the same revision,
one write succeeds and the other reports a conflict.

To report the 95th-percentile read Turn latency, conflict count, and elapsed
time for all write results in each swarm:

```sh
JIDO_BLACKBOARD_SAMPLE=1 mix test.examples examples/11_built_in_capabilities/11_11_shared_blackboard/swarm_test.exs --warnings-as-errors
```

One shared board accepts one write. With five counters assigned to each job
board, four boards accept four writes from 20 counters and 20 boards accept
20 writes from 100 counters. The default sample uses ETS. Set
`JIDO_BLACKBOARD_STORE=mnesia` or `JIDO_BLACKBOARD_STORE=ecto` to run the same
sample with Mnesia or Ecto with SQLite. These measurements include Agent
checkpoint writes because the instance uses persistence for all its Agents.

## Choose a Store

The job owner uses `persistence: :inherit`. Change the Jido instance profile
to run the same owner with each Store:

| Host setup | Instance `:persistence` option |
| --- | --- |
| ETS in the current BEAM | `Jido.Persistence.ETS` |
| An existing Mnesia table with `[:key, :value]` | `{Jido.Persistence.Mnesia, table: :jido_records}` |
| An Ecto repo with the Jido migration applied | `{Jido.Persistence.Ecto, repo: Inventory.Repo}` |

Use a stable instance namespace. The offline tests use an isolated Mnesia
RAM table and a temporary SQLite database. Configure Mnesia disk copies if
the board must survive a BEAM restart. See the [Store setup
guides](../../../guides/reference/persistence-adapter-matrix.md).

## Important behavior

The chart checks the result's request ID. On conflict it lets the counter
read the current board before deciding again. A restarted counter reads the
same board. Stopping the desk stops the board. A new desk starts from the
initial count of zero and rejects a revision from the old desk.

For a durable job board, stopping the owner keeps the count. Activating the
same Agent Address again restores the count and rejects old revisions.
The lifecycle test writes 12 and verifies this behavior with ETS, Mnesia, and
Ecto. It then retires the saved board and its owner.

## Limits

The board serves one BEAM node. The swarm measures short bursts with small
boards on the local machine. Patch result Signals use best-effort delivery.
If a result is missing or indeterminate, read the board before choosing the
next action.

## Core Fit and Gaps

The owner, snapshot input, and patch Directive compose through existing
topology, Plugin, and Statechart contracts. The application owns request IDs
and reconciliation. A read can show current board values after a missed
result. It might be insufficient to tell which request changed a value.

Previous [Cancel a Statechart deadline](../11_10_statechart_deadline/README.md).
