# 99_03 DSL and Data Topology Members

Status: core fix implemented for review. The examples first failed for
[issue 394](https://github.com/agentjido/jido/issues/394) in the first examples commit in this PR.

## Public contract

DSL, data, and JSON Topologies use the same planning and runtime contract.
An Agent or group selects a compiled `module` or a neutral `definition`.
Exactly one selector is required. A neutral definition can come from an Agent
DSL module, direct data, or Agent Codec JSON. The Controller preserves its
schema, routes, metadata, and Plugins.

## Approaches and executable evidence

| Approach | Source | Tests | Required result |
| --- | --- | --- | --- |
| Initial members | [startup.ex](startup.ex) | [Startup tests](../../../test/examples/99_research/99_03_data_defined_topology/startup_test.exs) | DSL and data Topologies start module members, DSL-produced Agent values, direct Agent values, or JSON-decoded Agent values. |
| Mixed members | [startup.ex](startup.ex) | [Startup tests](../../../test/examples/99_research/99_03_data_defined_topology/startup_test.exs) | One target starts compiled and stored members together. |
| Live addition | [topology.ex](topology.ex), [target builders](data_defined_topology.ex) | [Single addition](../../../test/examples/99_research/99_03_data_defined_topology/data_defined_topology_test.exs), [three additions](../../../test/examples/99_research/99_03_data_defined_topology/additions_test.exs) | Add stored members to a ready DSL or data Topology. Existing members keep their PID and committed state. |
| Groups | [groups.ex](groups.ex) | [Group tests](../../../test/examples/99_research/99_03_data_defined_topology/groups_test.exs) | Counted and keyed groups use one selected definition for each member. Key order does not change identity. |
| Static composition | [composition.ex](composition.ex) | [Composition tests](../../../test/examples/99_research/99_03_data_defined_topology/composition_test.exs) | DSL or data parents include DSL or data children, retain exact member definitions, and resolve exports. |
| JSON transport | [transport.ex](transport.ex) | [Transport tests](../../../test/examples/99_research/99_03_data_defined_topology/transport_test.exs) | The Topology Codec retains definitions and plans. Decoded targets start and execute the selected routes. |
| Recovery | [recovery.ex](recovery.ex) | [Recovery tests](../../../test/examples/99_research/99_03_data_defined_topology/recovery_test.exs) | Member restart, Bus repair, and Jido plus Controller restart retain the selected definition and committed state. |
| DSL definition selector | [DSL fixture](fixtures/direct_dsl.exs) | [DSL argument test](../../../test/examples/99_research/99_03_data_defined_topology/startup_test.exs) | Use `agent :alice, definition: stored` and validate it through the common constructor. |

Each data approach has a compiled module control. Direct and JSON Agent
values also execute alone. Alice, Bob, and Charlie share [Worker](worker.ex)
behavior but have different schemas, routes, metadata, and Plugin selections.
Bob has no [RecordCount Plugin](record_count.ex). The tests check these values,
command results, topology metadata, and process cleanup.

Invalid initial state must fail planning before a member starts. This check
also has module controls for single members and resolved group state.

## Read the code

Start with [definitions.ex](definitions.ex). It defines the three data Agents
and a trusted Registry with stable identifiers. Then read [Worker](worker.ex),
the shared [Record Action](record.ex), and [RecordCount](record_count.ex).
Select an approach from the table. For the original live addition, read
[topology.ex](topology.ex), [Observer](observer.ex), and [demo.exs](demo.exs).

## Run it

Run from the local `jido` V3 repository:

```sh
mix test test/examples/99_research/99_03_data_defined_topology --include example --seed 0
```

To run one approach, use its test file from the table:

```sh
mix test test/examples/99_research/99_03_data_defined_topology/groups_test.exs --include example --seed 0
```

Expected result: all 58 tests pass. They check exact selected definitions,
resolved state, command results, recovery, and process cleanup.

Run the original demonstration:

```sh
mix run examples/99_research/99_03_data_defined_topology/demo.exs
```

It starts the DSL Topology, commits Observer total 7, decodes Alice from JSON,
and adds Alice through `Controller.update/3`. Existing Observer state and PID
stay unchanged. Cleanup stops the Controller and Jido. The command exits with
status 0.

## Contract for review

`Definitions.entry/3` selects `module` or `definition`. The direct DSL fixture
uses `definition:`. The existing module argument remains exclusive to compiled
modules. The fixture is compiled by the tests, outside normal source compilation.

See the [API review note](../API_REVIEW.md) for the DSL change, JSON versions,
and restore policy. The supplied definition is a snapshot. Additive updates
cannot replace an existing member definition or fetch a changed stored document.

## Limits and promotion

These are local examples. They use in-memory JSON documents, trusted Registry
entries, and ETS persistence. They do not prove database storage, remote
placement, distributed ownership, or recovery after machine loss. Static
`include` composes one Controller target; it does not create a child runtime.

Keep these examples in research for PR review. Promote them after the DSL and
version contracts are accepted.

Test support: [definition and execution assertions](../../../test/examples/support/data_topology_assertions.ex),
[process cleanup](../../../test/examples/support/topology_assertions.ex).

Return to the [research catalog](../README.md).
