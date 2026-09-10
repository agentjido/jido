# 06_02 Three-Agent System

A system owner starts a conversation Agent and a workshop Agent that runs a
bounded FIFO queue through temporary worker Agents.

## What you will learn

- How one Agent owns stable service Agents and relays committed events.
- How Scheduler Signals, child Directives, request IDs, and generations control queued work.

## Read the code

Read [the system owner](system.ex), [the workshop](workshop.ex),
[the conversation](conversation.ex), and [the work item](work_item.ex). Then read
the shared [asynchronous Plugin](../support/async.ex), [tools](../support/tools.ex),
and [protocol](../support/protocol.ex).

## Run it

```sh
mix test test/examples/06_factory/06_02_three_agent_system --include example --seed 0
```

Expected result: jobs enter FIFO order, only one worker is active, progress is
correlated to its generation, and completion frees the next queue slot.

## Important behavior

Pause, resume, cancel, failure, and parent shutdown stop or replace owned work
explicitly. Old worker progress cannot change a newer attempt.

## Limits

Workers perform three timed demonstration steps. This is an application queue
policy, not a general Jido worker-pool API.

## Files

- [System Agent](system.ex)
- [Workshop Agent](workshop.ex)
- [Conversation Agent](conversation.ex)
- [Worker Agent](work_item.ex)
- [Tests](../../../test/examples/06_factory/06_02_three_agent_system/system_test.exs)
- [Section support](../support/)

Previous: [Live Conversation](../06_01_live_conversation/README.md) | Next: [Department Factory](../06_03_department_factory/README.md)
