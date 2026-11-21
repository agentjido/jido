# 18 Model Resilience

These examples make ReAct retry, fallback, output repair, budget, tool-error,
and telemetry behavior explicit with a deterministic offline inference client.

## Examples

1. [Retry and fallback](18_01_retry_and_fallback/README.md).
2. [Repair and budgets](18_02_repair_and_budgets/README.md).
3. [Failure matrix](18_03_failure_matrix/README.md).

The examples do not contact a live model provider. Retry, fallback, and output
repair in this chapter are ReAct behavior. Do not assume that another reasoning
strategy has the same behavior.
