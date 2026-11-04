# Local system checks

These checks use local processes and temporary File persistence. They prove
cleanup under pressure, recovery from a checkpoint, corrupt-record handling,
public execution cleanup, and telemetry behavior. Namespace owners live under
`jido_agent_server`, `jido_exec`, `jido_persistence`, and `jido_telemetry`.

Run them with:

```console
mix test.system test/system
```

No external service is required.
