# LLM example tests

This folder mirrors the numbered learning path in
[the LLM examples](../../../examples/03_llm/README.md).

Run the section behavior tests:

```sh
mix test test/examples/03_llm --include example --seed 0
```

Each test uses public Jido APIs and deterministic local clients. The six
examples cover model calls, history, typed tools, a tool loop, parallel tools,
and bounded output repair. Worker barriers stay in test support. They prove
overlap, ordering, cancellation, and cleanup without adding test controls to
example Actions or Flows.

Read each numbered example README before its test file. The README states the
claim that the test proves and the behavior that it does not prove.
