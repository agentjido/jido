# Runtime load check

This check starts, commands, and stops 100 AgentServer trees in each cycle. It
uses process monitors and registry queries instead of a time-based sleep.

Run it with:

```console
mix test.load test/perf/jido_agent_server
```
