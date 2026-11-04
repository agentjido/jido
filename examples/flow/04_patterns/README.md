# Flow pattern examples

| ID | Lesson |
| --- | --- |
| `flow/04_01_human_approval` | Address one approval event. |
| `flow/04_02_batch_processing` | Bound concurrent Map work and Reduce it. |
| `flow/04_04_compensation` | Resume explicit idempotent compensation. |

Lesson `04_03` has an executable deferred probe for its durable nested ReAct
audit contract.

Run the supported group with:

```sh
mix test.examples test/examples/flow/04_patterns
```
