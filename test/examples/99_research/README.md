# Research example tests

See [the research catalog](../../../examples/99_research/README.md).
Remote startup has one current rejection test. Remote lifecycle success is
unsupported. Distributed authority uses explicit external fencing.

```sh
mix test test/examples/99_research --include example --seed 0
```
