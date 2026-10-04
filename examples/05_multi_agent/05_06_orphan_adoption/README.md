# 05_06 Orphan Adoption

A child can survive parent exit and later attach to one new parent.

## What you will learn

- How direct child option `on_parent_death: :continue` leaves a surviving
  unattached child.
- How `:emit_orphan` also sends `jido.agent.orphaned` to the child.
- How `AgentServer.adopt_child/4` establishes a new tracked relationship.
- How the new parent routes work to the adopted child.
- How duplicate or invalid adoption fails without changing ownership.

## Read the code

Read [the child and parent Agents](orphan_adoption.ex). The spawn route selects
the parent-death policy. The forward route uses an `EmitToChild` Directive only
after the child has been adopted with the `:adopted` tag.

## Run it

```sh
mix test test/examples/05_multi_agent/05_06_orphan_adoption --include example --seed 0
```

Expected result: both policy forms leave a live child. The orphan-emitting
child records its former relationship, accepts one new parent, and receives
forwarded work.

## Important behavior

`:continue` clears the former parent without a domain Signal. `:emit_orphan`
clears it and casts a normal orphan Signal into the child. Adoption requires a
live, unattached Agent and an unused tag on the new parent.

The direct Agent Server option is named `on_parent_death`. Topology ownership
declares the same policy with `on_parent_exit`.

The final cleanup stops the adopted child through its current parent before it
stops that parent. This removes the complete relationship tree.

## Limits

Adoption is a local ownership contract. It is not an election, a distributed
lease, or proof that a remote parent is dead.

## Files

- [Source](orphan_adoption.ex)
- [Tests](../../../test/examples/05_multi_agent/05_06_orphan_adoption/orphan_adoption_test.exs)

Previous: [Remote Lifecycle](../05_05_remote_lifecycle/README.md) | Next: [Factory examples](../../06_factory/README.md)
