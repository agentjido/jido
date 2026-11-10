# Runtime load check

This check starts 100 AgentServer trees in each cycle. It then runs 20 commands
on separate Agents. A message barrier confirms that all 20 Actions are running
before any can complete. The test checks each result, then stops the trees with
concurrency 32. Process monitors and registry queries check complete cleanup.

Run it with:

```console
mix test.load test/perf/jido_agent_server
```
