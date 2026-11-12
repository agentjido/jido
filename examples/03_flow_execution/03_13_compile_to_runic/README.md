# Compile to Runic

`Jido.Exec.compile/2` lowers a Jido Flow to a `Runic.Workflow`. This script
prints the authored Flow, the Runic component and connection shape, and the
result after direct Runic execution.

Run it from the `jido` package:

```sh
mix run examples/03_flow_execution/03_13_compile_to_runic/run.exs
```

See [the ExUnit proof](compile_to_runic_test.exs).
