# 05_06 Orphan Adoption

An independent Agent can survive its owner's supervisor and later accept a new owner.

Read [the Agents and startup helper](orphan_adoption.ex) and
[the tests](../../../test/examples/05_multi_agent/05_06_orphan_adoption/orphan_adoption_test.exs).

```elixir
Parent.start_worker(server, :continue)
Parent.start_worker(server, :emit_orphan,
  orphan_dispatch: {:pid, target: observer})

Jido.AgentServer.adopt_child(new_owner, worker, :adopted)
```

The helper uses `spawn_child/4` with `placement: :independent` and
`on_parent_exit:`. The `:emit_orphan` policy requires an explicit destination.
It sends `jido.agent_server.orphaned` there after the old owner stops.
The new owner sends work with `agent_send/2`.

```sh
mix test test/examples/05_multi_agent/05_06_orphan_adoption --include example --seed 0
```

Adoption is local. It does not provide a distributed lease.

Previous: [Correlated Requests](../05_02_correlated_requests/README.md) | Next: [Topology](../../07_topology/README.md)
