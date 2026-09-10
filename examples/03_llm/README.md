# LLM examples

These examples add model and tool effects to the Jido Agent and Flow contracts.
They use deterministic local adapters, so the complete section needs no network
access or credentials.

`Jido.Examples.LLM.Adapter` is an example-owned service contract. It is not a
new Jido model API. Each example passes `{module, client}` values through Turn
context and keeps them out of Agent state, Signals, and Directives.

## Learning order

1. [Model Response](03_01_model_response/README.md) makes one typed model call
   and applies explicit fallback policy.
2. [Conversation History](03_02_conversation_history/README.md) builds each
   model request from committed Agent state.
3. [Tool Call](03_03_tool_call/README.md) validates one approved typed tool.
4. [Tool Loop](03_04_tool_loop/README.md) uses Flow continuations for bounded
   model and tool rounds.
5. [Parallel Tools](03_05_parallel_tools/README.md) runs a finite tool plan with
   bounded Map concurrency.
6. [Output Repair](03_06_output_repair/README.md) uses bounded Iterate state for
   schema repair.

## Run the section

```sh
mix test test/examples/03_llm --include example --seed 0
```

Expected result: the section passes without provider credentials. Successful
Turns commit validated state. Failed or cancelled Turns preserve the prior
commit.

## Shared support

- [LLM adapter contract](support/adapter.ex) normalizes example client errors
  and validates model data.
- [Tool support](support/tooling.ex) contains the typed search Action, complete
  plan validator, and final answer Action used by `03_03` and `03_05`.

The tests use process barriers only in test support. The example Actions and
Flows use normal client contracts and public Jido APIs.

## Limits

Fixed local replies do not prove factual accuracy, model quality, provider
compatibility, image understanding, or provider-specific token limits.

Grounding, history compaction, delegation, and recursive analysis are useful
application policies. They belong in later application or multi-Agent examples
when they use a distinct Jido contract. They do not need separate LLM examples.
