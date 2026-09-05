# PERSIST-02: checkpoint portability

Status: **enabled regression; fixed in migration preparation**.

The store supplies a valid record with a PID nested in Agent state. The loader
rejects that process handle. It checks portable data on load and save. A valid
domain schema alone does not prove portability.

Run the local example:

```sh
mix run lib/examples/99_research/99_07_checkpoint_portability/demo.exs
```

The example inserts the PID through the byte adapter so the save validator
cannot hide the load gap. Controls prove that portable nested data round trips
and that normal save rejects a PID before it reaches storage. This first probe
covers a nested PID. The recursive check also rejects references, ports, and
functions.
There is no database or VM restart.

[Probe Agent](checkpoint_portability_probe.ex) ·
[Acceptance notes](../../../../test/examples/99_research/99_07_checkpoint_portability/README.md) ·
[Results](../../../../docs/examples/persistence-boundary-results.md)
