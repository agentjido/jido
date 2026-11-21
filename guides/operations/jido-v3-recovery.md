# Jido v3 recovery gate

Run the focused durable-runtime gate with:

```sh
mix jido_v3.recovery
```

The gate covers stable Agent activation, restart recovery, retained terminal
turn results, acknowledgement, durable deletion tombstones, and Timer recovery.
Run `mix ci` for the complete release gate.
