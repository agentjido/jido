# 09_03 Independent Agent Ownership

An independent Agent can survive its owner's supervisor and later accept a new owner.

Read [the Agents and startup helper](orphan_adoption.ex) and
[the tests](orphan_adoption_test.exs).

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
mix test.examples examples/09_multi_agent/09_03_orphan_adoption
```

Adoption is local. It does not provide a distributed lease.

This transfers local runtime ownership. It does not move a declared topology
member or change an Agent definition. Declared members follow their owning
supervisor lifetime; independent Agents use the explicit policy shown here.

Previous: [Correlated Requests](../09_02_correlated_requests/README.md) | Next: [Topology](../../10_topologies/README.md)
