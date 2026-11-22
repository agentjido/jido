# 15_15 Read a release note with an AI Agent

Give an AI Agent a release-note URL. It reads a permitted page through
`web_fetch` and cites the source in its answer.

## What you will learn

- How the Agent exposes `web_fetch` and declares the URLs it can request.
- How the host narrows that scope before any page transport runs.
- How the tool result supplies the source URL to the model.

## Read the code

Read [the Agent](release_notes.ex) and its browser declaration. Then read
[the host policy and page fixture](support/offline_browser.ex) and
[the scripted model](support/scripted_client.ex).

## Run it

```sh
mix test.examples examples/15_ai_agents/15_15_browser_release_notes --warnings-as-errors
mix run examples/15_ai_agents/15_15_browser_release_notes/demo.exs
```

The public release note yields an answer with its source URL. The host
rejects the internal preview before the transport opens a page.

To try the two requests in the opt-in Explorer, open this lesson in Browse
and select a page in the demo form.

## Important behavior

The Agent allows the `/jido/` path. The host allows only `/jido/releases/`.
Both rules must allow a URL before the tool calls the host transport. The
model has two calls and one tool round. The fixture and the scripted model
run in memory.

## Limits

The fixture covers page reading and policy in memory. Live DNS, HTTP,
search, and model behavior are outside this test.

## Core Fit and Gaps

The same ReAct loop, browser Action, and URL rules apply with a different
page transport. The host owns transport configuration. A deployed app can
use the built-in transport for network requests.

## Files

- [Agent](release_notes.ex)
- [Tests](release_notes_test.exs)
- [Demo](demo.exs)
- [Host fixture](support/offline_browser.ex)
- [Scripted inference client](support/scripted_client.ex)

Previous lesson [Offline testing](../15_14_offline_testing/README.md)
