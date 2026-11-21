# 16_02 Tool boundary policy

This Flow checks a requested tool call, runs one local tool, and checks its
result before any model can reuse it.

## What you will learn

- How to allow tools and arguments before execution.
- How to reject unsafe tool results before model reuse.
- How separate boundaries produce separate errors and audit decisions.

## Read the code

Read [the Flow and its three Actions](tool_boundary_policy.ex) first.

## Run it

`mix test.examples examples/16_guardrail_flows/16_02_tool_boundary_policy --warnings-as-errors`

Expected result: three tests pass. The allowed lookup returns a checked local
result. A denied call and a credential-bearing result stop at different
boundaries.

## Important behavior

The call check runs before the tool Action. The result check runs after the
tool Action and before the result leaves the Flow. The local tool has no
external effect.

## Limits

The allowlist and result detector are small application rules. This example
does not prove tool sandboxing, authorization, or safe handling by a later
model call.

## Core Fit and Gaps

Normal Action validation and Flow ordering make both tool boundaries explicit.
The application owns the tool policy and audit record. Jido core does not need
a new guardrail, middleware, or tool-policy API for this composition. A larger
application can move the rule set to a shared policy package.

## Files

- [Source](tool_boundary_policy.ex)
- [Tests](tool_boundary_policy_test.exs)

[Previous: Input and output policy](../16_01_input_output_policy/README.md)

[Next: Human review](../16_03_human_review/README.md)
