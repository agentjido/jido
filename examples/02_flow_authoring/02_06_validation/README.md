# Validation

Flow construction rejects an unknown result reference and a control cycle
before execution. The expected messages identify an unknown component and a
dependency cycle.

Read [`validation.ex`](validation.ex) and run its paired offline test.

See [the ExUnit proof](validation_test.exs).
