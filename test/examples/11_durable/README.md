# Durable example tests

Run `mix test test/examples/11_durable --include example --seed 0 --warnings-as-errors`.

The [source overview](../../../examples/11_durable/README.md) defines ownership and limits.

- `11_01`: restore committed Agent state after SIGKILL.
- `11_02`: restore the current AgentServer Turn at step 6; confirmed steps do not repeat.
- `11_03`: restore the same Turn in a fresh BEAM with the DETS byte adapter.
- `11_04`: restore a topology member and its completed report Turn.

The other folders contain proposed lessons, with no skipped or placeholder tests.
Crash controls and barriers remain in test support. Child BEAM tests need local
sockets and `kill`, but no external service or credentials.
