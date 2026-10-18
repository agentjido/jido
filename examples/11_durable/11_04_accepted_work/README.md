# 11_04 Accepted Work

A topology member runs a report Flow as its current durable Turn.

## What you will learn

- Route directly to a Flow without a durability Plugin.
- Save acceptance before execution and commit output before returning success.
- Restore a member identity, Agent state, and terminal Turn receipt.

## Read the code

Read [the Agent, report Flow, and team](accepted_work.ex).

```elixir
{:ok, root} = Jido.start_agent(MyJido, Jido.Examples.Durable.AcceptedWork.Team,
  id: "reports", persistence: :inherit)
:ok = Jido.AgentServer.await_ready(root)
[reports] = Jido.AgentServer.members(root, :reports)
{:ok, request} = Jido.Examples.Durable.AcceptedWork.request_signal(%{topic: "OTP"})
{:ok, agent, []} = Jido.AgentServer.call(reports, request)
agent.state # %{report: "Report: OTP"}
Jido.AgentServer.status(reports).durable_turn # %{id: turn_id, status: :completed}
```

## Run it

```sh
mix test test/examples/11_durable/11_04_accepted_work --include example --seed 0
```

Expected result: the report commits, the team activation is killed, and its
replacement restores the same member ID, report, and completed Turn.

## Important behavior

The call returns after the Flow Turn commits. It does not return an early
background-work acknowledgement. Further state-changing commands wait. Cancellation
uses `AgentServer.cancel/2` or `cancel_turn/3`, not a domain cancellation route.
Core [topology tests](../../../test/jido/agent_server/durable_topology_test.exs)
and [BEAM tests](../../../test/jido/agent_server/durable_topology_peer_test.exs)
cover active member work across wider failures.

## Limits

Repeated Signals start new Turns. There is no request-ID deduplication contract.
The Server retains the latest durable Turn receipt, not a receipt ledger.
Topology members have independent records; the root is not an atomic family save.
External effects and post-commit directives do not gain exactly-once delivery.

## Files

- [Source](accepted_work.ex)
- [Tests](../../../test/examples/11_durable/11_04_accepted_work/accepted_work_test.exs)
- [Core execution](../../../lib/jido/agent_server/durable_turn.ex)

Previous: [VM Recovery](../11_03_vm_recovery/README.md) | Next: [Saved Completion — proposed lesson](../11_05_saved_completion/README.md)
