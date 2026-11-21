# 09_04 Independent Agents

Run two Agents in one instance without creating an ownership relation between
them.

## What you will learn

- A Jido instance is the process owner for both resident activations.
- Independent Agents have separate identity, state, and stop behavior.
- Stopping one Agent does not stop or change the other.

## Read the code

Read [the independent startup client](independent_agents.ex) first.

## Run it

`mix test.examples examples/09_dynamic_agent_composition/09_04_independent_agents --warnings-as-errors`

Expected result: the first Agent stops, and the second still commits result 6.

## Important behavior

There is no parent-child runtime relation in this lesson. The application owns
the decision to start and stop each Agent.

## Limits

The example does not provide adoption, transfer, or automatic shutdown
propagation between the Agents.

## Core Fit and Gaps

Independent Agent startup and shutdown use public Jido APIs. Cross-Agent
ownership policy remains explicit application state in the next lesson.

## Files

- [Source](independent_agents.ex)
- [Tests](independent_agents_test.exs)

Previous: [Process replacement](../09_03_orphan_adoption/README.md) | Next: [Logical ownership transfer](../09_05_logical_ownership_transfer/README.md)
