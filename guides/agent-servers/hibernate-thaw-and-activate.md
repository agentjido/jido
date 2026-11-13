# Hibernate and Thaw

Hibernation saves an Agent, then stops its processes. Thawing starts a new process from that save. This guide shows how to use both to keep Agents out of memory between uses, and how to handle a save that fails.

The Agent needs a store and an instance with a namespace. The examples use `Jido.Persistence.ETS`, which keeps data in memory and suits development and tests. See [Make an Agent Durable](../durability/make-an-agent-durable.livemd) for stores and setup.

```elixir
defmodule HibernateGuide.Cart do
  use Jido.Agent, name: "cart"

  state do
    schema Jido.Joi.object(%{items: Jido.Joi.list(Jido.Joi.string()) |> Jido.Joi.default([])})
  end

  routes do
    signal_source "/carts"

    route "cart.add", as: :add do
      action %{sku: sku},
        schema: Jido.Joi.object(%{sku: Jido.Joi.string()}),
        context: context do
        {:ok, %{context.agent_state | items: context.agent_state.items ++ [sku]}}
      end
    end
  end
end

{:ok, _instance} =
  Jido.start(
    name: HibernateGuide.Jido,
    namespace: "guides/carts",
    persistence: {Jido.Persistence.ETS, table: :hibernate_guide}
  )
```

## Hibernate an Agent

Start the Agent in the persistent instance. It automatically uses the
instance's one Store and codec, and each commit saves.

```elixir
{:ok, cart} = Jido.start_agent(HibernateGuide.Jido, HibernateGuide.Cart, id: "cart-1")
:ok = Jido.AgentServer.await_ready(cart)

{:ok, _agent, []} = Jido.AgentServer.call(cart, HibernateGuide.Cart.add_signal!(%{sku: "tea"}))

:ok = Jido.hibernate(HibernateGuide.Jido, cart)

{Process.alive?(cart), Jido.whereis_agent(HibernateGuide.Jido, "cart-1")}
```

`:ok` confirms that the save succeeded and the whole activation has exited.

`Jido.hibernate/3` first runs the same drain as `Jido.AgentServer.quiesce/2`: it closes admission, rejects queued Turns with `:quiesced`, and waits for the active Turn and its effects. It takes the same options:

- `:active` is `:finish` by default. `:cancel` cancels pre-commit work.
- `:timeout` is the finite drain budget, with a default of 5,000 ms. Cleanup has a further wait of the same length. `:persistence_timeout` bounds the save itself.

Use `Jido.AgentServer.hibernate/2` with a PID or name, and `Jido.hibernate_ref/3` with a `Jido.Agent.Ref`. With `Jido.hibernate/3`, pass `:partition` for an Agent in a partition. A wrong partition returns `{:error, :not_found}`.

A durable Flow Turn suspended on a wait can hibernate with its progress saved. See [Durable Turns and Flows](../durability/durable-turns-and-flows.livemd).

## Thaw an Agent

`Jido.thaw/4` starts a new process from the saved Agent. It uses the instance
profile. In a partition, pass `:partition`.

```elixir
{:ok, thawed} = Jido.thaw(HibernateGuide.Jido, HibernateGuide.Cart, "cart-1")
:ok = Jido.AgentServer.await_ready(thawed)

%{agent: %{state: %{items: ["tea"]}}, state_version: 1} = Jido.AgentServer.snapshot(thawed)
```

The revision continues from the save. A thawed Agent uses the definition in its save, not the current source of the module. See [Upgrade Live Agents](upgrade-live-agents.md) when the two differ.

Restoring happens after `thaw` returns, so check the result with `Jido.AgentServer.await_ready/2`. When the Agent has no save, the new worker stops with `{:shutdown, :not_found}`, and `await_ready/2` returns `{:error, :not_found}`. The worker can also stop before `thaw` returns. Then `thaw` itself returns `{:error, :not_found}`. Handle both results with one `with`:

```elixir
thaw_cart = fn id ->
  with {:ok, pid} <- Jido.thaw(HibernateGuide.Jido, HibernateGuide.Cart, id),
       :ok <- Jido.AgentServer.await_ready(pid),
       do: {:ok, pid}
end

{:error, :not_found} = thaw_cart.("cart-404")
```

## Choose a start mode

`:persistence_mode` decides what a new worker does with existing data. Each mode has a function that sets it.

| Function | Mode | No save exists | A save exists |
| --- | --- | --- | --- |
| `Jido.create_agent/4` | strict create | Creates the Agent record. | Returns `{:error, :conflict}`. |
| `Jido.start_agent/3` with `:persistence` | `:create` | Creates the Agent. | The worker stops with `{:shutdown, :conflict}`. |
| `Jido.thaw/4` | `:restore` | The worker stops with `{:shutdown, :not_found}`. | Restores the save. |
| `Jido.activate_agent/4` | `:restore` | The worker stops with `{:shutdown, :not_found}`. | Restores the save. |

## Activate on demand

`Jido.activate_agent/4` is the call to make when a request arrives for an existing durable Agent that may not be in memory. It takes a Ref and returns the running PID when the Agent is already live.

```elixir
:ok = Jido.stop_agent(HibernateGuide.Jido, thawed)

{:ok, ref} = Jido.agent_ref(HibernateGuide.Jido, "cart-1")
{:ok, activated} = Jido.activate_agent(HibernateGuide.Jido, ref, HibernateGuide.Cart)
:ok = Jido.AgentServer.await_ready(activated)

{:ok, ^activated} = Jido.activate_agent(HibernateGuide.Jido, ref, HibernateGuide.Cart)

{:ok, %{state: %{items: ["tea", "scone"]}}, []} =
  Jido.call(HibernateGuide.Jido, ref, HibernateGuide.Cart.add_signal!(%{sku: "scone"}))

{:ok, new_ref} = Jido.agent_ref(HibernateGuide.Jido, "cart-2")
{:ok, ^new_ref} = Jido.create_agent(HibernateGuide.Jido, new_ref, HibernateGuide.Cart)
{:ok, created} = Jido.activate_agent(HibernateGuide.Jido, new_ref, HibernateGuide.Cart)
:ok = Jido.AgentServer.await_ready(created)

%{agent: %{state: %{items: []}}, state_version: 0} = Jido.AgentServer.snapshot(created)
```

## Hibernate when idle

Set `idle_policy: :hibernate` to save and stop an Agent after its idle budget
runs out. The instance must have persistence.

```elixir
{:ok, idle_cart} =
  Jido.start_agent(HibernateGuide.Jido, HibernateGuide.Cart,
    id: "cart-3",
    idle_timeout: 50,
    idle_policy: :hibernate
  )

monitor = Process.monitor(idle_cart)

receive do
  {:DOWN, ^monitor, :process, ^idle_cart, {:shutdown, :hibernate}} -> :saved_and_stopped
after
  1_000 -> raise "the Agent did not hibernate"
end
```

Attached owners and `Jido.AgentServer.touch/1` hold the timer off, as they do for `idle_policy: :stop`. See [Control Activations](inspect-and-control-activations.livemd). A failed automatic save closes admission and does not retry, so watch `admission.mode` in status for an idle Agent that stops answering.

## Handle a failed hibernation

A failure returns `{:error, %{reason: reason, resumable?: boolean}}`. The Agent stays alive in every case. `resumable?` tells you whether the live Agent can safely continue.

```elixir
{:ok, plain_cart} = Jido.start_agent(HibernateGuide.Jido, HibernateGuide.Cart, id: "cart-4")

{:error, %{reason: :persistence_not_configured, resumable?: true}} =
  Jido.AgentServer.hibernate(plain_cart)
```

| `reason` | `resumable?` | State afterward | Next step |
| --- | --- | --- | --- |
| `:persistence_not_configured` | `true` | Unchanged. | Start the Agent with persistence. |
| `:activation_required` | `true` | Unchanged. The server is a bare worker. | Start the Agent through an instance. |
| `:quiesce_timeout` | `true` | Admission stays closed until the server settles. | Call `Jido.AgentServer.resume/2` after that, or hibernate again. |
| A known store rejection | `true` | Admission returns to its earlier mode. | Fix the store and retry. |
| `:conflict` | `false` | Admission is `:blocked`. | Stop the Agent and thaw it. |
| `:indeterminate` or `{:indeterminate, detail}` | `false` | Admission is `:blocked`. | Stop the Agent and thaw it. |

`:blocked` protects you from a split outcome. After an uncertain save, the store may hold a newer value than the live Agent, or the same value. New Turns get `:quiesced`, `Jido.AgentServer.resume/2` returns `{:error, :unsafe_resume}`, and a worker restart keeps the block. Reads still work. `Jido.AgentServer.stop/3` and a new `thaw` load whatever the store holds.

Control problems keep the plain form: `{:error, :reentrant_turn}`, `{:error, :not_ready}`, `{:error, :control_in_progress}`, and `{:error, :unsafe_resume}`.

A save that is part of a Turn follows a separate rule: it stops the activation when it fails. See [Revisions and Conflicts](../durability/durable-revisions-and-conflicts.md).

## Related

- [Durable Agent Activation](../durability/durable-agent-activation.livemd) follows activation across restarts.
- [Deletion and Tombstones](../durability/deletion-and-tombstones.md) removes a saved Agent with `Jido.delete_agent/4`.
