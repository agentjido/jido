# PERSIST-01: checkpoint identity

Status: **enabled regression; fixed in migration preparation**.

The store holds a valid record for `requested-agent`. The record envelope and
lookup key agree, but the nested checkpoint contains `different-agent`.
The loader rejects the record when the restored identity differs from the
requested identity.

Run the local example:

```sh
mix run lib/examples/99_research/99_06_checkpoint_identity/demo.exs
```

The example prints the actual load result. The acceptance tests require an
error for the mismatch. Controls prove valid identity/state/revision restore
and rejection of a wrong outer identity. No Server, database, or VM restart
is needed for this boundary.

[Probe Agent](checkpoint_identity_probe.ex) ·
[Acceptance notes](../../../../test/examples/99_research/99_06_checkpoint_identity/README.md) ·
[Results](../../../../docs/examples/persistence-boundary-results.md)
