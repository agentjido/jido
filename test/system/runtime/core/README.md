# Core runtime system checks

These checks use local processes and temporary File persistence. They prove
cleanup under pressure, recovery from a checkpoint, corrupt-record handling,
and public telemetry behavior.

Run them with:

```console
mix test.system test/system/runtime/core
```

No external service is required.
