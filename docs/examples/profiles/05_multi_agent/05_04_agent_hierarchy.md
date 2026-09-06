# Agent Hierarchy

Feature ID: `05_04_agent_hierarchy`. Status: implemented within the tested scope.

## Added feature

Each Agent owns direct children; branch loss is isolated and root shutdown removes the whole subtree. Read this after the Runtime group and the previous Multi-agent example.

## Use

```elixir
alias Jido.Examples.AgentHierarchy

{:ok, server} = Jido.start_agent(jido, AgentHierarchy)
AgentHierarchy.grow(server, 2)
```

## Evidence

4 enabled tests:

- a two-level tree has six real descendants with direct parent bindings.
- a branch crash stops its descendants and preserves its sibling.
- root shutdown removes every descendant from the instance registry.
- depth bounds reject work before a commit or child creation.

Run:

```shell
mix test --include integration test/examples/05_multi_agent/05_04_agent_hierarchy --seed 0
```

[Source](../../../../examples/05_multi_agent/05_04_agent_hierarchy/agent_hierarchy.ex) ·
[Tests](../../../../test/examples/05_multi_agent/05_04_agent_hierarchy/agent_hierarchy_test.exs)

## Boundary and next question

The test proves a local seven-Agent tree. It does not prove distributed placement, live topology recovery, or a 1,500-Agent scale target.

See the [gap register](../../runtime-multi-agent-gaps.md) and
[verification report](../../runtime-multi-agent-results.md).
