# 11_07 External Uncertainty

A provider accepts a publication, execution crashes before the step save, and
recovery calls the provider with the same operation ID.

## What you will learn

- Save intent at a Flow step boundary before external work.
- Reuse the operation ID when the interrupted Action runs again.
- Keep unsafe work in an explicit `:needs_attention` outcome.

## Read the code

Read [the Agent and publication Flow](external_uncertainty.ex), then the
[local provider](support/memory_provider.ex).

Supply `operation_id`, `report`, and `policy` in `publish_signal/1`.
For `policy: :idempotent`, pass portable execution context:

```elixir
context: %{publication_provider: {ProviderModule, RegisteredProviderName}}
```

The provider implements `publish(address, operation_id, report)`. It must retain
the operation ID and result, accept the same ID and data again, and reject
conflicting data. The application owns the provider and its retention policy.

## Important behavior

The `intent` step saves the operation ID before `publish` starts. The test holds
the Action after provider acceptance and kills the Server. Recovery makes two
provider calls but creates one publication. Different data with the same ID
fails. Cancellation stops local work; it cannot undo provider acceptance.
`policy: :manual` saves `:needs_attention` and does not call the provider.

Crash barriers remain in
[test support](../../../test/examples/support/durable_publication_probe.ex).
The provider lives outside the killed Agent tree.

## Limits

The local provider keeps data in memory. This test proves Agent process loss,
not provider or BEAM loss. A production provider must retain IDs and results
across its own failures. Core cannot make arbitrary I/O exactly once. Manual
policy prevents dispatch; it does not resolve an operation already sent to an
unsafe provider. Reconciliation and later authorization belong to the application.

## Run it

```sh
mix test test/examples/11_durable/11_07_external_uncertainty --include example --seed 0 --warnings-as-errors
```

Expected result: the success, recovery, and rejection assertions pass. Tests stop
the Agents and release all held test calls. No external service is required.

## Files

- [Source](external_uncertainty.ex)
- [Tests](../../../test/examples/11_durable/11_07_external_uncertainty/external_uncertainty_test.exs)

Previous: [Durable Wait](../11_06_durable_wait/README.md) | [Durable overview](../README.md)
