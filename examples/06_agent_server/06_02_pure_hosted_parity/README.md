# 06_02 Pure and Hosted Execution Parity

The same Signal produces the same candidate Agent state through `Agent.cmd/3`
and AgentServer hosting.

## What you will learn

- How pure evaluation returns immutable candidate state and Directives.
- How AgentServer commits the candidate and performs the correlated Reply.

## Read the code

Read [the Agent](pure_hosted_parity.ex), then read
[the parity proof](pure_hosted_parity_test.exs).

## Run it

`mix test.examples examples/06_agent_server/06_02_pure_hosted_parity --warnings-as-errors`

Expected result: pure and hosted state both contain `count: 7`, and hosted
execution returns the same reply data with request causation.

## Important behavior

`Agent.cmd/3` does not mutate the source Agent or start a process. AgentServer
owns serialization, commit, reply preparation, and process lifecycle.

## Limits

Parity applies to the Jido evaluation boundary. An Action can still perform
application I/O during evaluation. Pure execution does not provide hosted
lifecycle behavior.

## Core Fit and Gaps

The route, state selector, reply selector, validation, and Agent evaluation
contracts are identical in both modes. Hosted execution adds commit and effect
work without changing the domain result. A route that selects nested output
must declare those fields in the target Action output schema so the Agent
compiler can validate each path.

## Files

- [Agent](pure_hosted_parity.ex)
- [Parity proof](pure_hosted_parity_test.exs)
