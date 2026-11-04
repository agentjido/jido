# Offline AI benchmark smoke checks

Run the smoke checks with:

```console
mix test.bench test/bench/ai
```

The tests validate completed model and tool work before they accept any metric.
They also run both manual scripts with two requests and validate their JSON
reports. Timing and memory values are recorded, not used as pass thresholds.
