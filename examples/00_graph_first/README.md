# Live graph-first ReAct Agent

This is the end-to-end Jido AI check. It starts a Jido instance and a live
AgentServer, runs the canonical ReAct Flow, calls a real LLM, runs two Action
tools in one parallel round, and checks the committed Session.

Run it from the `jido/` package root:

```sh
mix run examples/00_graph_first/live_react.exs
```

ReqLLM loads provider credentials from `jido/.env`. The default model is
`openai:gpt-4o-mini`. Set `JIDO_LIVE_MODEL` to use a different ReqLLM model:

```sh
JIDO_LIVE_MODEL=anthropic:claude-haiku-4-5 \
  mix run examples/00_graph_first/live_react.exs
```

Set `JIDO_LIVE_PROMPT` to replace the default arithmetic request. The script
expects the request to use exactly two tools in one tool round, so a custom
prompt must keep that contract.

This example makes paid network calls. It is not part of the normal test
suite.
