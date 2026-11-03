# Quality source manifest

`source_manifest.yml` is the source ledger for imported quality assets. Each record identifies the source repository,
full source commit, source path, planned or current target path, quality surface, Covenant owner, disposition, and reason.

Allowed dispositions are:

- `ported`: The target path exists and contains the adapted check.
- `superseded`: A current check owns the same quality obligation.
- `deferred`: A later ticket or product change is required.
- `excluded`: The source asset is outside the supported quality surface.

Target paths must be unique. A `ported` record must point to an existing file or directory. Source paths are records only.
Never edit a source repository while updating this manifest.

## Focused commands

Each command uses seed `0`. A command exits successfully with a clear message when its default target path does not exist.

```text
mix test.authoring
mix test.examples
mix test.property
mix test.fuzz
mix test.system
mix test.load
mix test.peer
mix test.bench
mix test.live
mix test.services
```

`mix test.ci` runs the default suite and every offline quality surface that is available. Live and service checks stay
explicit and opt-in.
