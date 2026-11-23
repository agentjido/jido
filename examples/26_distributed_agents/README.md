# 26 Distributed Agents

Run the same application on two connected BEAM nodes. Start with one Agent
that both nodes can call. Then move it and see what happens when both nodes
try to host the same Address.

1. [One pinned Agent for two nodes](26_01_pinned_singleton/README.md). Route two callers to one activation. Drop the connection before and during a call.
2. [Move a durable Agent](26_02_move_a_durable_agent/README.md). Stop the old host, open the same state on the new host, and resume the same waiting Turn.
3. [Shared storage and Agent ownership](26_03_shared_store_ownership/README.md). Reproduce two live activations for one Address against a shared store.
4. [Recover a ticket deadline after a crash](26_04_recover_a_ticket_deadline/README.md). Kill the BEAM with a waiting ticket and recover the deadline on the survivor.
5. [Split the BEAM link with SQL still available](26_05_partition_without_ownership/README.md). Observe two live activations and a new commit on the original host during a partition.

6. [Route to one fixed home](26_06_native_fixed_home/README.md). Route both callers through the opted-in instance and prove ingress cannot activate.
7. [Recover a ticket with native OTP](26_07_native_ticket_recovery/README.md). Move a durable home after a verified stop and recover its overdue Turn.

```sh
mix test.examples examples/26_distributed_agents --warnings-as-errors
```

The default suite starts real BEAM peers on loopback TCP and uses temporary
local stores. Examples 26_04 and 26_05 use local SQLite by default. The fixed-home recovery example uses native OTP Mnesia.

If you use the v2 Cluster API, map each logical `{manager, key}` to an Agent
Address. Use the namespace to identify the manager's group and encode the
key as a stable string for the Address ID. Follow the [migration guide](../../docs/guides/fixed-home-clustering.md#migrate-a-v2-cluster-consumer) to preserve saved state and recoverable Turns.

## Run with PostgreSQL

Set `JIDO_EXAMPLE_POSTGRES_URL` to a disposable PostgreSQL database. The
database role must be able to create schemas in that database. The test
creates a schema with a unique name for each case and drops it on cleanup.
The deadline test waits up to ten seconds for recovery after it starts the
surviving host. A local PostgreSQL service is sufficient.

```sh
mix test.examples examples/26_distributed_agents/26_04_recover_a_ticket_deadline \
  examples/26_distributed_agents/26_05_partition_without_ownership --warnings-as-errors
```

## Deployment on two Fly Machines

Use the [fixed-home guide](../../docs/guides/fixed-home-clustering.md) for
native OTP setup, restart controls, and recovery. The test peers reproduce
host loss and link loss locally.

## Next core contracts

Automatic takeover requires a decision that remains valid during a partition
and a write fence that rejects the former home's grants. The
[takeover evidence gate](../../docs/plans/2026-11-23-native-otp-clustering-plan.md#u4-prove-one-way-automatic-takeover)
specifies the remaining tests.

[Previous chapter](../25_operations_and_integrations/README.md)
