# Consumer build tests

This folder contains isolated Mix applications that test Jido as a dependency.
They check compilation and release behavior in separate BEAM VMs.

## Run the tests

Run this command from the `jido/` repository root:

```sh
mix test test/jido/action/inline_host_build_test.exs
```

The [ExUnit tests](../jido/action/inline_host_build_test.exs) use the
[build helper](../support/jido_action/inline_build.ex) to copy the consumer into
each test's temporary directory. The helper supplies the current test VM's
compiled dependency paths and a separate build directory. The consumer's
`mix.exs` therefore has no dependency declarations. Run it through the tests
above, rather than as a standalone project.

## What `inline_consumer` checks

- Generated inline Actions and inline Flows are included in the consumer's
  application manifest and compiled artifacts.
- These targets load before their owner modules. Catalog lookup can resolve
  both target types before the owners load.
- A release can execute the targets after the complete consumer source project
  is removed. This includes an inline Flow with a nested inline Action.
- A normal Action without `run/2` fails compilation.
- A body macro change rebuilds dependent owners without changes to their source
  or timestamps. Compilation recovers after an invalid macro is corrected.
- Equivalent Step syntax keeps the same semantic identity and generated module
  names. Renamed or removed Steps leave no stale BEAM files or public lookups.

The recompilation and Step cleanup tests exercise inline Actions. The inline
Flow has release, discovery, lookup, and execution coverage here. Its separate
[unit tests](../jido/flow/inline_test.exs) cover other inline Flow contracts.

## Fixture files

- `inline_consumer/lib/` contains the consumer DSL host, Action owners, normal
  Flows, an embedded inline Flow, and a body macro.
- `inline_consumer/variants/` contains replacement source files. Tests copy these
  into the temporary consumer to test edits and compilation failures.
- `inline_consumer/scripts/probe.exs` loads and executes compiled targets. It
  prints one `INLINE_RESULT=` JSON record. ExUnit checks the returned results,
  identities, artifact names, and lookup checks.
- `inline_consumer/scripts/guard.exs` controls child VM lifetime.

The helper moves the scripts outside the temporary consumer source directory.
The release test can then remove that source directory and still run the probe.

## Why the guard calls `System.halt/1`

Each build or probe runs in a child OS process through an Erlang port. The guard
starts two processes inside that child VM:

- The first waits for standard input to close. Port closure also closes standard
  input. It then calls `System.halt(125)` to stop the child if the parent test
  process exits.
- The second calls `System.halt(124)` after 45 seconds. This is a fallback lifetime
  limit if normal cleanup fails.

These calls stop the entire child VM, not the parent ExUnit VM. They prevent
abandoned test VMs from continuing to run.

The parent helper has a shorter 40-second timeout for each child command. It
normally kills that child and reports its captured output first. The guard's
45-second limit runs later so it does not hide the parent's timeout diagnostic.
The enclosing ExUnit test has a 180-second timeout because it can run several
child commands.
