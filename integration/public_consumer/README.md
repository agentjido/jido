# Public package consumer

This small Mix project compiles and runs against an unpacked Jido Hex
candidate. It uses only documented public modules. It checks the four Plugin
owner facets, Signal creation, Agent Ref addressing, Agent persistence, the
instance facade, and static Topology planning.

Set `JIDO_CANDIDATE_PATH` to the unpacked candidate directory. Then run:

```sh
mix deps.get
mix test --seed 0
```
