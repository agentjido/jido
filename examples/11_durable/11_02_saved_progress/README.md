# 11_02 Saved Progress

AgentServer saves a ten-step Flow and resumes its interrupted step after a crash.

## What you will learn

- Enable Flow recovery with persistence; one Flow is the current Turn.
- Restore step 6 without repeating confirmed steps 1–5.
- Keep uncommitted Flow output outside Agent state until the Turn completes.

## Read the code

Read [the Flow and Agent](saved_progress.ex), then [Advance](advance.ex).

```elixir
{:ok, server} = Jido.start_agent(MyJido, Jido.Examples.Durable.SavedProgress.Agent,
  id: "ten-steps", persistence: Jido.Persistence.ETS)
:ok = Jido.AgentServer.await_ready(server)
{:ok, signal} = Jido.Examples.Durable.SavedProgress.Agent.run_signal(%{value: 0})
{:ok, agent, []} = Jido.AgentServer.call(server, signal)
agent.state # %{value: 10}
```

## Run it

```sh
mix test test/examples/11_durable/11_02_saved_progress --include example --seed 0
```

Expected result: steps 1–5 run once; step 6 starts twice after the crash; final
Agent state is `%{value: 10}`. The saved Turn ID remains the same.

## Important behavior

AgentServer confirms graph checkpoints before dispatching more work. The test
uses a [barrier Action](../../../test/examples/support/durable_step_probe.ex)
in a test copy of the Flow. Production Actions contain no crash controls.
The Server owns recovery; callers do not start, resume, or step a separate Runner.
Process monitors confirm that interrupted work stops.

## Limits

ETS survives Agent process loss, but not BEAM loss. Interrupted Actions can repeat
external effects. This lesson covers a sequential Flow, not parallel branches.
Caller Pending handles do not survive the Server crash.

## Files

- [Source](saved_progress.ex)
- [Action](advance.ex)
- [Tests](../../../test/examples/11_durable/11_02_saved_progress/saved_progress_test.exs)
- [Test support](../../../test/examples/support/durable_step_probe.ex)

Previous: [Saved Agent State](../11_01_saved_agent/README.md) | Next: [VM Recovery](../11_03_vm_recovery/README.md)
