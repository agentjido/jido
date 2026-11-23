---
title: Route and recover a Jido namespace on two BEAM nodes
status: current
last-reviewed: 2026-11-23
---

# Route and recover a Jido namespace on two BEAM nodes

Use fixed-home clustering to let either node send Signals to a durable Agent.
One configured node owns all Agent activations and wake delivery in the
namespace. The other node can accept requests while the home starts.
Jido uses native OTP distribution and requires no additional package.

## Set up both nodes

Give each BEAM a distinct node name and use the same secret cookie. Connect the
nodes over a trusted private network. On Fly, use each Machine's stable private
hostname and enable IPv6 distribution where the deployment requires it. Include
OTP Mnesia in the host release if you use the native store profile below.
Keep the home and the store running while deadlines are pending.
[Fly private networking](https://docs.fly.io/networking/private-networking)

Use the same Jido instance name, namespace, and cluster settings on both
Machines. The deployment supplies the node atom. A client must not supply it.

```elixir
config :my_app, MyApp.Tickets,
  namespace: "support/tickets",
  persistence: {Jido.Persistence.Mnesia, table: :ticket_records, sync_writes: true},
  cluster: [home: :"tickets@a-host", generation: "deployment-1", rpc_timeout: 5_000]
```

Configure persistence at runtime for a clustered `use Jido` module. Use
`cluster: false` for the default local instance. A nonpersistent fixed home
needs only `home:` and an explicit `namespace:`.

For native recovery from A to B, put the only `disc_copies` replica of
`:ticket_records` on B. It must be a `:set` with attributes `[:key, :value]`
and `local_content: false`. B owns the schema and durable volume. A uses a
RAM-only schema and joins B with `:mnesia.change_config(:extra_db_nodes, [node_b])`.
A holds no replica of the ticket table. Check the table placement and confirm
both BEAMs see B before you start the home. The store becomes unavailable
to A when B or the link fails. Loss of B's disk requires a separate restore.
[OTP Mnesia](https://www.erlang.org/docs/27/apps/mnesia/mnesia.html)

Provision the home record offline when the namespace is new:

```elixir
profile = {Jido.Persistence.Mnesia, table: :ticket_records, sync_writes: true}
:ok = Jido.change_cluster_home(profile, "support/tickets", :not_found, {node_a, "deployment-1"})
```

Keep an existing home record on restart. A durable home must match its stored
node and generation before it can open the namespace. Availability of the
canonical store is a condition for home startup.

## Send work to one Address

Create the Agent on the home. Send work through either instance. Keep the Turn
ID in your application if you need to retrieve a terminal result after a lost
reply.

```elixir
{:ok, address} = Jido.agent_address(MyApp.Tickets, "ticket-42")
Jido.call(MyApp.Tickets, address, signal, turn_id: turn_id, result_handoff: true)
Jido.turn_result(MyApp.Tickets, address, turn_id)
```

Use `Jido.status/3` for runtime status and `Jido.fetch_state/3` for the
Agent's state. For an Ecto-backed Agent, the home queries its Repo.
Use `Jido.cast/3` for best-effort dispatch.
A verified unavailable endpoint returns `:cluster_unavailable`. A mutating
request that may have reached the home can return `{:cluster_outcome_unknown, reason}`.
The router makes one attempt. The home limits the wait for activation before
it sends the Signal. A transport failure can occur before or after admission.
A caller timeout leaves accepted work running. Look up or reconcile the
outcome before resending. A retained result remains readable
until you acknowledge it on the home. An absent result can mean work is still
running. A repeated Turn ID does not deduplicate submissions.

Use the home for creation, activation, lifecycle controls, writes through the
instance's persistence selector, and result acknowledgement. `Jido.submit/4`
and worker PIDs have local scope. Run managed activations under the home
instance.

## Move the home after a verified stop

1. Quiesce the application producers. Let work that is already running settle
   if possible. Stop the old supervised instance, including its Wake and Agent
   children. A parent can restart a permanent child, so remove or disable its
   child specification. For a crash, confirm the old BEAM stopped through the
   host control plane and prevent it from restarting with the old settings.
   A distribution disconnect is insufficient evidence.
2. On B, verify the canonical store and resolve interrupted writes. Check the
   saved state and its wait or retained result through the last acknowledged
   Turn. Keep B as ingress until the old home is fenced.
3. Change the home record with the exact prior tuple and a fresh generation.
   After an uncertain write, use `Jido.check_cluster_home/3` before starting
   an instance on the new configuration. Keep B's Mnesia store running.

   ```elixir
   old_home = {node_a, "deployment-1"}
   new_home = {node_b, "deployment-2"}
   :ok = Jido.change_cluster_home(profile, "support/tickets", old_home, new_home)
   :ok = Jido.check_cluster_home(profile, "support/tickets", new_home)
   ```

4. Restart B's Jido child with B as the home. Jido reloads the wake index and
   resumes overdue work by Address. Return A as ingress with the new settings.
   If A must rejoin B's Mnesia schema, restart the RAM-only client and confirm
   the authoritative table first. Resolve any Mnesia inconsistency before
   reopening traffic. [Mnesia partition recovery](https://www.erlang.org/docs/27/apps/mnesia/mnesia_chap7.html)
5. Read the terminal result by its original Turn ID. Record it in your
   application and acknowledge it on B. Use a stable effect key with
   destination deduplication for external ticket updates.

The home record refuses a stale startup. The verified stop prevents work
that the old home admitted earlier from continuing across the move. Keep old
binaries, unclustered instances, and direct maintenance writers away from that
namespace during the move. To move back, repeat the procedure from the latest
canonical data with a fresh generation.

## Migrate a v2 cluster consumer

Map each legacy manager to a namespace. For a pair such as
`{SupportManager, "ticket-42"}`, use namespace `"support/tickets"` and ID
`"ticket-42"`. For other key types, use a stable encoding that gives each
supported key its own ID. Replace PID lookup and get-or-start with durable
creation on the home and Address-based calls on either node.

Rehearse data export and import on a copy. Verify every Address, saved state,
waiting Turn and retained result. Stop the legacy writer before final export.
Keep a consumer on v2 if it needs standby acknowledgements, live placement,
automatic takeover or a workflow that has no verified state translation.
Retire `jido_cluster` after affected consumers have an accepted migration.

## Verify the setup locally

```sh
mix test.examples examples/26_distributed_agents --warnings-as-errors
```

Read [fixed-home routing](../../examples/26_distributed_agents/26_06_native_fixed_home/README.md)
and [native ticket recovery](../../examples/26_distributed_agents/26_07_native_ticket_recovery/README.md)
for runnable examples. Test the stop and recovery procedure on the target
deployment before depending on deadline recovery there.
