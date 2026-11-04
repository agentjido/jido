# Live provider check

The live AI check is not part of `mix test` or any offline quality command. It
uses a separate test credential:

```console
JIDO_LIVE_OPENAI_API_KEY=... mix test.live
```

The test copies this value to `OPENAI_API_KEY` only for the test process and
restores the previous value when it ends. It writes an allow-listed JSON trace
to `tmp/live/ai_reasoning.json`. The trace contains status, counts, token usage,
and correlation identifiers. It does not contain prompts, model output, raw
errors, request payloads, response payloads, or credentials.

Selecting the live suite without `JIDO_LIVE_OPENAI_API_KEY` fails with a clear
message. Use only an approved test key. Do not use a production credential.
