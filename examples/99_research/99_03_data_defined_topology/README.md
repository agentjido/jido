# 99_03 DSL and Data Topology Members

Status: enabled failing examples for [issue 394](https://github.com/agentjido/jido/issues/394).
These examples define the required behavior before the core fix.

## Current public contract

`Jido.Agent.new/1` and `Jido.Agent.Codec` produce neutral Agent definitions.
`Jido.start_agent/3` can start these values. Topology Agent and group entries
accept compiled Agent modules only. DSL, data, and JSON Topology definitions
already use the same planning contract for module members.

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
| Direct DSL argument | [DSL fixture](fixtures/direct_dsl.exs) | [DSL argument test](../../../test/examples/99_research/99_03_data_defined_topology/startup_test.exs) | Probe a neutral value in the existing positional Agent argument. This is a syntax proposal for review. |

Every blocked behavior has a passing module control. Direct and JSON Agent
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

Expected result: module controls and standalone data Agent execution pass.
Neutral Topology members fail at construction with `Expected an Agent module`.
The direct DSL argument fails at compile time because Spark requires an atom.
The tests stay enabled. The command exits with status 2 until the contract is
implemented. Assertions after those failures describe the required behavior;
they have not yet run for neutral members.

Run the original demonstration:

```sh
mix run examples/99_research/99_03_data_defined_topology/demo.exs
```

It starts the DSL Topology, commits Observer total 7, decodes Alice from JSON,
then fails before `Controller.update/3`. Cleanup stops the Controller and Jido.
The command exits with status 1.

## Contract for review

The examples use the current `module` data field to expose its restriction.
The shared `Definitions.entry/3` builder keeps that choice in one place.
The DSL-based targets start from `.topology()` and replace member entries in
the returned value. They do not change the compiled DSL definition.

The `.exs` fixture probes existing DSL syntax. It is not part of normal source
compilation. These examples do not approve overloading `module`, adding a
separate `definition` field, or changing DSL syntax. Any DSL change requires
user review before implementation.

Recovery uses the same supplied definition and persistence store. The examples
do not choose a policy for loading a changed stored document, version upgrades,
or replacement of an existing live member.

## Limits and promotion

These are local examples. They use in-memory JSON documents, trusted Registry
entries, and ETS persistence. They do not prove database storage, remote
placement, distributed ownership, or recovery after machine loss. Static
`include` composes one Controller target; it does not create a child runtime.

Promote the examples after the core contract is implemented, the required
tests pass, and the DSL and version contracts have been reviewed.

Test support: [definition and execution assertions](../../../test/examples/support/data_topology_assertions.ex),
[process cleanup](../../../test/examples/support/topology_assertions.ex).

Return to the [research catalog](../README.md).
