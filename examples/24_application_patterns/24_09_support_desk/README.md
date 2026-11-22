# 24_09 Support Desk

Build a ticket assistant that checks a request before it starts a model Turn,
uses a tool for troubleshooting, and checks the reply before release.

## Try it

In the [Example Explorer](../../README.md), open **Browse**, search for
**Support Desk**, and select this lesson. Send the sample printer question.
The scripted model calls one tool and replies with the verified next step.
Select **Claim the ticket is resolved** and send the question again while the
ticket is open. The guard blocks the claim. **Mark resolved** and **Request
human support** send separate ticket-control Signals.

## Read the code

Read the [custom reasoning Flow](reasoning.ex), then the [ticket Agent and its
Actions](support_desk.ex) and [scripted inference client](scripted_client.ex).
Start with [ticket policy for stock ReAct](../../16_guardrail_flows/16_04_support_desk/README.md)
and [custom reasoning input](../../17_ai_reasoning_flows/17_05_custom_reasoning_flow/README.md)
for the individual contracts.

## Run it

```sh
mix test.examples examples/24_application_patterns/24_09_support_desk --warnings-as-errors
```

The [test](support_desk_test.exs) checks off-topic rejection before Session
creation, excerpt selection, one tool call in two model calls, blocked output,
and restoration of the ticket and approved conversation at the same Address.

## Limits

Admission recognizes a small support vocabulary and an explicit mixed-message
separator. The output guard checks specific claims. Both are local examples of
policy boundaries. The tool provides advice. The escalation status has no
external queue or notification. The Explorer keeps the demo ticket in memory.

## Core Fit and Gaps

The custom Flow uses Invoke to choose a blocked result or continue into the
public ReAct Flow. The ReAct output guard checks the answer before the Session
commits. The application disables provider streaming and uses one tool round,
at most two model calls, and zero retries. The ticket Agent owns both the
conversation and status. The first approved answer and each ticket control
commit in separate Turns. The integration test uses ETS to preserve both
across Agent process replacement. Production admission, policy and delivery
remain application responsibilities.

Previous: [Controlled Agent Upgrade](../24_08_controlled_agent_upgrade/README.md)
