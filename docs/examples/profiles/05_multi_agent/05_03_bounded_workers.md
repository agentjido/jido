# Bounded Workers

Feature ID: `05_03_bounded_workers`. Status: implemented within the tested scope.

## Added feature

At most eight live children reuse fixed slots; each result admits one queued item and results retain input order. Read this after the Runtime group and the previous Multi-agent example.

## Use

```elixir
alias Jido.Examples.BoundedWorkers

{:ok, server} = Jido.start_agent(jido, BoundedWorkers)
BoundedWorkers.process_values(server, "batch-1", [2, 3, 4, 5], 2)
```

## Evidence

5 enabled tests:

- two live workers overlap, reuse their slots, and preserve input result order.
- stale replies cannot consume a slot or advance the queue.
- cancellation stops all child execution and discards queued work.
- one child crash fails the request and stops the sibling.
- empty input starts no child and invalid limits make no commit.

Run:

```shell
mix test --include integration test/examples/05_multi_agent/05_03_bounded_workers --seed 0
```

[Source](../../../../lib/examples/05_multi_agent/05_03_bounded_workers/bounded_workers.ex) ·
[Tests](../../../../test/examples/05_multi_agent/05_03_bounded_workers/bounded_workers_test.exs)

## Boundary and next question

The example fails the request on child loss and stops siblings. It does not reclaim leases, retry work, persist a queue, or undo completed child commits.

See the [gap register](../../runtime-multi-agent-gaps.md) and
[verification report](../../runtime-multi-agent-results.md).
