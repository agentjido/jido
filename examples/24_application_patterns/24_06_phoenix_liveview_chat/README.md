# 24_06 Phoenix LiveView Chat

This Phoenix Playground runs a complete offline chat with one durable,
Session-backed Jido Agent and one transient LiveView client.

## What you will learn

- How a stable `Jido.Agent.Address` survives LiveView and Agent process replacement.
- How a supervised task keeps model work outside the LiveView event callback.
- How a portable PubSub target carries ordered model stream Signals.
- How to accept one bounded image attachment as multimodal input.
- How to rebuild public chat history from the committed Agent-owned Session.

## Read the code

Read the [framework-neutral chat application](chat_application.ex), then the
[LiveView](chat_live.ex), and then the [Playground script](playground.exs).

## Run it

Run the normal offline integration proof:

`mix test.examples examples/24_application_patterns/24_06_phoenix_liveview_chat --warnings-as-errors`

Run the real LiveView check with cached Hex packages and no network access:

`HEX_OFFLINE=1 MIX_ENV=test mix run examples/24_application_patterns/24_06_phoenix_liveview_chat/playground_check.exs`

Start the interactive Playground:

`HEX_OFFLINE=1 mix run examples/24_application_patterns/24_06_phoenix_liveview_chat/playground.exs`

Expected result: a normal exchange renders ordered start, chunk, and completion
Signals. A new LiveView process rebuilds the same committed conversation. The
failure switch renders a failed stream without adding an assistant message.

The repository lock file controls all packages. Normal project dependency
setup must be complete. The application makes no network or model provider
call.

## Important behavior

The LiveView stores the stable Agent Address, not the AgentServer PID. Model
work runs under a `Task.Supervisor`. The durable Turn context contains a
portable PubSub server name and topic. A PID dispatch target is not portable
and AgentServer correctly rejects it.

Only final successful assistant output enters the Agent-owned Session. Stream
chunks are transient UI data. A socket loss can lose chunks, but reconnect
rebuilds the final committed conversation. The UI lists waiting, failed,
cancelled, timed-out, uncertain, and committed operation states.

A conversation ID selects a record. It is not an authorization credential.
The host application must authenticate the user and authorize access before it
resolves the Agent Address.

## Limits

The local inference client is deterministic and does not measure provider
latency. The image limit is one megabyte, but the demo stores the data URL in
the Session. Production systems should store media in an authorized object
store and put only a durable Address in the Session. PubSub stream chunks are
ephemeral and are not replayed after a socket loss.

## Core Fit and Gaps

Stable Agent Addresses, durable Session state, normal `jido.ai.request`
Signals, portable dispatch targets, and public Session projection compose into
a Phoenix application without a Phoenix-specific Jido API. The first attempt
used PID dispatch and produced a clear `:non_portable_term` failure. The public
`:pubsub` adapter is the correct durable boundary. The
[ReAct streaming guide](../../../guides/ai/react-reasoning.livemd#stream-the-answer)
now recommends PubSub for hosted web clients and limits PID dispatch to pure or
transient local runs.

- Logical owner: conversation Agent Address.
- Process owner: current AgentServer activation; LiveView owns only its socket.
- Canonical state owner: Agent-owned Session.
- Commit point: successful Agent Turn state commit.
- Persisted data: complete Session, request outcomes, and model attempt data.
- Retry boundary: one bounded AI request; this example sets retries to zero.
- Idempotency rule: the demo does not retry user submissions automatically.
- Injected failure: deterministic model error and Agent process replacement.
- Recovery result: committed history survives both client and Agent process
  replacement; failed output does not enter public history.
- Limits and non-guarantees: stream chunks are not durable or replayable, and a
  conversation ID does not grant access.

## Files

- [Chat application](chat_application.ex)
- [LiveView](chat_live.ex)
- [Offline integration tests](chat_application_test.exs)
- [Phoenix Playground](playground.exs)
- [LiveView check](playground_check.exs)

[Previous: Compensation](../24_05_compensation/README.md)

[Next: Recoverable External Delivery](../24_07_recoverable_external_delivery/README.md)
