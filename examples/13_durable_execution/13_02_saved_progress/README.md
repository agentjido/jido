# 13_02 Saved Progress

AgentServer saves a ten-step Flow and resumes its interrupted step after a crash.

## What you will learn

- Enable Flow recovery with persistence; one Flow is the current Turn.
- Restore step 6 without repeating confirmed steps 1–5.
- Keep uncommitted Flow output outside Agent state until the Turn completes.

## Read the code

Read the shared [Flow and Agent](../support/saved_progress_agent.ex), then
[Advance](../support/saved_progress_advance.ex). VM Recovery uses the same
stable building blocks in the next lesson.

```elixir
{:ok, _instance} =
  Jido.start_link(name: MyJido, namespace: "saved-progress", persistence: Jido.Persistence.ETS)

{:ok, server} = Jido.start_agent(MyJido, Jido.Examples.Durable.SavedProgress.Agent,
  id: "ten-steps")
:ok = Jido.AgentServer.await_ready(server)
{:ok, signal} = Jido.Examples.Durable.SavedProgress.Agent.run_signal(%{value: 0})
{:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
  Jido.AgentServer.call(server, signal)

Jido.AgentServer.snapshot(server).agent.state # %{value: 10}
```

## Run it

```sh
mix test.examples examples/13_durable_execution/13_02_saved_progress --warnings-as-errors
```

Expected result: steps 1–5 run once; step 6 starts twice after the crash; final
Agent state is `%{value: 10}`. The saved Turn ID remains the same.

## Important behavior

AgentServer confirms graph checkpoints before dispatching more work. The test
uses a [barrier Action](../support/durable_step_probe.exs)
in a test copy of the Flow. Production Actions contain no crash controls.
The Server owns recovery; callers do not start, resume, or step a separate Runner.
Process monitors confirm that interrupted work stops.

## Limits

ETS survives Agent process loss, but not BEAM loss. Interrupted Actions can repeat
external effects. This lesson covers a sequential Flow, not parallel branches.
Caller Pending handles do not survive the Server crash.

## Files

- [Shared Flow and Agent](../support/saved_progress_agent.ex)
- [Shared Action](../support/saved_progress_advance.ex)
- [Tests](saved_progress_test.exs)
- [Test support](../support/durable_step_probe.exs)

Previous: [Saved Agent State](../13_01_saved_agent/README.md) | Next: [VM Recovery](../13_03_vm_recovery/README.md)
