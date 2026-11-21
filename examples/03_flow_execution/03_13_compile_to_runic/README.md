# 03_13 Compile to Runic

`Jido.Exec.compile/2` lowers one validated Jido Flow to a `Runic.Workflow`
that produces the same result.

## What you will learn

- How the Jido execution boundary compiles a Flow to Runic nodes and links.
- Why direct Runic execution is an advanced escape path, not a second Jido
  authoring model.

## Read the code

Read [the Flow](compile_to_runic.ex), then [the runner](run.exs), and then
[the test](compile_to_runic_test.exs).

## Run it

```sh
mix test.examples examples/03_flow_execution/03_13_compile_to_runic --warnings-as-errors
mix run examples/03_flow_execution/03_13_compile_to_runic/run.exs
```

Expected result: both paths return `%{value: 18}`. The runner also prints the
compiled Runic components and connections.

## Important behavior

Jido validates the Flow before it exposes the compiled workflow. Application
code that executes Runic directly owns that lower-level runtime boundary.

## Limits

This lesson does not teach Runic authoring, persistence, or recovery. Those
contracts stay behind the Jido execution and durable-runtime APIs.

## Core Fit and Gaps

The public compile operation exposes the lower-level workflow without private
runtime access. No core gap was found.

## Files

- [Flow](compile_to_runic.ex)
- [Runner](run.exs)
- [Tests](compile_to_runic_test.exs)

[Previous: Wait and Signal](../03_12_wait_and_signal/README.md)

[Next: Runic Runner](../03_14_runic_runner/README.md)
