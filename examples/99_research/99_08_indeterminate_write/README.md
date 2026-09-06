# PERSIST-03: indeterminate write

Status: **enabled regression; fixed in migration preparation**.

The in-memory adapter writes the candidate bytes, then returns
`{:error, :indeterminate}`. The stored count becomes `1`, but the live count
stays uncommitted. The Server stops before a second Action can run. It does
not dispatch the unconfirmed Directive or save stale state during shutdown.

Run the local example:

```sh
mix run examples/99_research/99_08_indeterminate_write/demo.exs
```

The admission test requires no further Action evaluation or Directive dispatch
until authoritative state is loaded. It permits the Server to stop or reject
the next command. It does not prescribe a shutdown reason or automatic reload.
It uses the default error policy so an application policy cannot hide the gap.

Controls prove that a confirmed write permits output, and that an uncertain
reply can follow a stored write without dispatching its Directive. Observer
callbacks and the output PID stay in caller context. The store process is
owned by the caller. Database durability, Postgres integration, and VM restart
are outside this proof.

[Probe Agent](indeterminate_write_probe.ex) ·
[Fault adapter](../persistence_probe_store.ex) ·
[Acceptance notes](../../../test/examples/99_research/99_08_indeterminate_write/README.md) ·
[Results](../../../docs/examples/persistence-boundary-results.md)
