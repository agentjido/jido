# 19_06 Concurrent request modes

This lesson runs one offline AI Agent through AgentServer call, submit, and cast.

## What you will learn

- `call` and `submit` have a reply owner and return a committed Turn result.
- `cast` has no reply owner, so its AI Turn can commit Session state but cannot
  return its Reply to the caller.

## Read the code

Read [the hosted Agent](request_modes.ex) first.

## Run it

`mix test.examples examples/19_sessions_and_conversations/19_06_request_modes --warnings-as-errors`

Expected result: all three modes advance the Session. Call and submit return
their replies, while cast returns only `:ok`. The test stops the Agent.

## Important behavior

AgentServer serializes accepted Turns. Submit returns a pending handle that the
caller can await.

## Limits

This lesson does not prove multi-node ordering or durable pending handles.

## Core Fit and Gaps

The public request modes make reply ownership explicit. A browser application
must keep its own request correlation and reconnect policy.

## Files

- [Source](request_modes.ex)
- [Tests](request_modes_test.exs)
- [Offline client](../../support/offline_inference_client.ex)

[Previous: Failed and incomplete exchanges](../19_05_request_modes/README.md)

[Next: Persistence and restoration](../19_07_persistence_and_restoration/README.md)
