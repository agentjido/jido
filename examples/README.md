# Jido offline examples

The examples are a progressive learning path and an offline integration suite.
The folder tree is the inventory source of truth. Each numbered chapter has a
README, and each supported lesson has reader-facing source and a colocated
integration test.

The target learning order and planned coverage are in
[the table of contents](table_of_contents.md). The current SDK findings are in
[the gap and friction register](core_gaps.md).

## Start here

Follow the [six expense-approval lessons](00_start_here/README.md) in order,
or start the Example Explorer from the repository root:

```sh
JIDO_PLAYGROUND=1 mix deps.get
JIDO_PLAYGROUND=1 mix run examples/playground/playground.exs
```

Open [the Example Explorer](http://localhost:4011). Use **Learn** for the six
onboarding lessons or **Browse** to search the full catalog by task or chapter.
Open a lesson to read its highlighted source and tests. Select **Run test** to
see the result and output in the lesson pane. The first test run can take
time to compile dependencies. Open **Hosted Agent** to try an expense
submission. Submit 12,500 cents to commit a Turn, then zero to see a failed
Turn leave the committed state at the same revision.

The flag enables Phoenix Playground, MDEx, and Lumis. Normal Core setup and
the offline example suite run without these dependencies.

## Find an example by task

- Build a support desk. Start with [stock ReAct policy](16_guardrail_flows/16_04_support_desk/README.md),
  then [custom reasoning input](17_ai_reasoning_flows/17_05_custom_reasoning_flow/README.md)
  and the [complete Support Desk](24_application_patterns/24_09_support_desk/README.md).
- [Build a chat UI](24_application_patterns/24_06_phoenix_liveview_chat/README.md).
- [Resume an approval](13_durable_execution/13_06_durable_wait/README.md).
- [Recover an external delivery](24_application_patterns/24_07_recoverable_external_delivery/README.md).
- [Upgrade a running Agent](24_application_patterns/24_08_controlled_agent_upgrade/README.md).
- Understand recovery after [process loss](13_durable_execution/13_02_saved_progress/README.md)
  or [BEAM loss](13_durable_execution/13_03_vm_recovery/README.md).
- [Run a durable Agent fleet](13_durable_execution/13_08_waterpark/README.md)
  or [measure it](25_operations_and_integrations/25_05_passive_fleet_measurement/README.md).

## Run the examples

Run all examples:

```sh
mix test.examples --warnings-as-errors
```

Run one chapter or lesson with its path:

```sh
mix test.examples examples/00_start_here --warnings-as-errors
mix test.examples examples/03_flow_execution/03_03_choice --warnings-as-errors
```

All supported examples run without network access, credentials, paid APIs, or
live providers. Deterministic local adapters preserve external application
boundaries.

Chapters `00` through `25` now follow the table-of-contents structure. Some
chapters combine closely related bullets into one comparison or application
lesson. The chapter README states that mapping and the limits of each proof.
