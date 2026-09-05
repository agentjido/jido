# Input Deduplication

Feature ID: `04_07_input_deduplication`. Status: implemented within the tested scope.

## Added feature

A stable input ID rejects duplicate work before a new commit; invalid input consumes no ID. Read this after the Basic and Workflow groups.

## Use

```elixir
alias Jido.Examples.DeduplicatingInbox

{:ok, server} = Jido.start_agent(jido, DeduplicatingInbox)
DeduplicatingInbox.receive_event(server, input: %{event_id: "event-1", item: %{value: 3}})
```

## Evidence

2 enabled tests:

- a duplicate stable event ID does not commit twice.
- invalid input does not consume an event ID and a later valid event works.

Run:

```shell
mix test --include integration test/examples/04_runtime/04_07_input_deduplication --seed 0
```

[Source](../../../../lib/examples/04_runtime/04_07_input_deduplication/deduplicating_inbox.ex) ·
[Tests](../../../../test/examples/04_runtime/04_07_input_deduplication/deduplicating_inbox_test.exs)

## Boundary and next question

This Agent rejects duplicates. A durable Bus consumer must instead accept already committed deliveries so its cursor can advance. Ledger retention is application policy.

See the [gap register](../../runtime-multi-agent-gaps.md) and
[verification report](../../runtime-multi-agent-results.md).
