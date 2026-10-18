# Local multi-agent tests

See [the local examples](../../../examples/05_multi_agent/README.md).
Local lifecycle, request correlation, and adoption retain their original IDs.
Their API update is still in progress. Nested ownership tests live in group 07;
remote startup rejection lives in research.

```sh
mix test test/examples/05_multi_agent --include example --seed 0
```
