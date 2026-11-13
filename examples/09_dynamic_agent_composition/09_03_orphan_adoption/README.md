# 09_03 Process replacement

A stable Agent Ref resolves a replacement process after abnormal process loss.

Read [the stable replacement client](orphan_adoption.ex) and
[the tests](orphan_adoption_test.exs).

The Jido instance restarts the activation from its durable record. The logical
Agent Ref and activation ID stay stable while the worker PID changes.

```sh
mix test.examples examples/09_dynamic_agent_composition/09_03_orphan_adoption
```

This is process replacement, not adoption or ownership transfer. Jido core has
no current public API for dynamic child adoption or runtime ownership transfer.

Previous: [Correlated Requests](../09_02_correlated_requests/README.md) | Next: [Independent Agents](../09_04_independent_agents/README.md)
