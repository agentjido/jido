# Plugin Persistence

Your Plugin's owned state has to survive a save and restore, and you need to
add, reconfigure, or remove the Plugin on an Agent that's already running.
This guide covers both: converting owned state at the storage boundary with
`dump/3` and `load/3`, and changing Plugins live with Directives.

It assumes you've read [Stateful Plugins](write-a-stateful-plugin.livemd) and
[Supervised Resources](plugin-supervised-resources.livemd).

## At a Glance

| You want to | Use |
| --- | --- |
| Store owned state in a different shape | `dump/3` and `load/3` |
| Version the Plugin's contract | `use Jido.Plugin, vsn: 2` |
| Reject bad runtime options | `validate_options/1` |
| Add a Plugin to a live Agent | `Jido.Agent.Directive.plugin_add/3` |
| Change a Plugin's options | `Jido.Agent.Directive.plugin_configure/3` |
| Remove a Plugin | `Jido.Agent.Directive.plugin_remove/2` |
| Change a Plugin that has a runtime | `quiesce/2` and `resume/2` |

Only committed state is saved. Runtime processes are never saved. Jido
rebuilds them from committed state.

## Convert Owned State

By default, Jido saves the owned field as-is. Implement `dump/3` and `load/3`
when the value isn't portable or when you want a different stored shape.
Jido calls `dump/3` when it builds a snapshot and `load/3` when it restores
one.

```elixir
defmodule MyApp.Tags do
  use Jido.Plugin

  @impl true
  def state_spec(_opts), do: {:tags, Zoi.list(Zoi.string()) |> Zoi.default([])}

  @impl true
  def dump(tags, _context, _opts), do: {:ok, Enum.join(tags, ",")}

  @impl true
  def load("", _context, _opts), do: {:ok, []}
  def load(joined, _context, _opts) when is_binary(joined), do: {:ok, String.split(joined, ",")}
  def load(_value, _context, _opts), do: {:error, :invalid_tags}
end

defmodule MyApp.Tagged do
  use Jido.Agent,
    name: "tagged",
    plugins: [MyApp.Tags]

  state do
    schema(Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)}))
  end

end

agent = MyApp.Tagged.instantiate!(id: "a-1", state: %{count: 1, tags: ["red", "blue"]})

{:ok, snapshot} = Jido.Persistence.snapshot(agent)
snapshot.agent.state
# => %{count: 1, tags: "red,blue"}

{:ok, restored} = Jido.Persistence.restore(snapshot)
restored.state
# => %{count: 1, tags: ["red", "blue"]}
```

Your Actions and reducers always see the live shape, a list here.

Both callbacks receive a `Jido.Persistence.Plugin.Context`:

| Field | Value |
| --- | --- |
| `plugin` | The Plugin module. |
| `plugin_vsn` | The Plugin version that owns the record. |
| `record_format` | The persistence record format version. |
| `direction` | `:dump` or `:load`. |
| `reason` | Why the conversion runs, such as `:snapshot`. |

The context has no storage adapter, record key, revision, or complete Agent.
A Plugin converts only its own value. Jido still checks that the full stored
representation is portable, and validates the restored state against the
schema.

- `dump/3` and `load/3` come as a pair and require an owned state field.
- An Agent with its own `checkpoint/2` callback skips Plugin conversion. That
  callback owns the whole format.

## Versions and Restore

`use Jido.Plugin, vsn: 2` sets the Plugin version. The default is `1`. Jido
stores it with the contribution and passes it to `dump/3` and `load/3` as
`plugin_vsn`, so `load/3` knows which shape it's reading. Bump it when the
meaning of the owned value or contribution data changes.

Restore also checks code, not only the version. A snapshot records a
fingerprint of every module it references. If the Plugin's code changed after
the snapshot, restore fails, even with the same `vsn`:

```elixir
{:error, error} = Jido.Persistence.restore(snapshot)
{error.code, Exception.message(error)}
# => {:changed_reference, "Snapshot code changed; use an explicit upgrade Action"}
```

Move saved data forward with `Jido.Persistence.upgrade/3`. The Checkpoints
and Upgrades guide covers it.

## Validate Options

Jido calls `validate_options/1` every time it normalizes the Plugin: at
definition time, at startup, and before every live change. It receives the
Agent Server options and returns `:ok` or `{:error, reason}`. Keep it pure.

With `option_keys:`, it sees only the Agent Server keys:

```elixir
use Jido.Plugin, option_keys: [agent: [:label], agent_server: [:capacity]]
```

See [Agent Plugins](agent-plugins.md).

## Change Plugins Live

An Action adds, reconfigures, or removes a Plugin by returning a Directive.
This cache Plugin has a runtime, so it also implements `quiesce/2` and
`resume/2`:

```elixir
defmodule MyApp.CacheRuntime do
  use GenServer

  def start_link(init), do: GenServer.start_link(__MODULE__, init)

  @impl true
  def init(init),
    do: {:ok, %{paused: false, commits: 0, capacity: init.options[:capacity]}}

  @impl true
  def handle_call(:quiesce, _from, state), do: {:reply, :ok, %{state | paused: true}}
  def handle_call(:resume, _from, state), do: {:reply, :ok, %{state | paused: false}}
  def handle_call({:commit, _commit}, _from, state),
    do: {:reply, :ok, %{state | commits: state.commits + 1}}
end

defmodule MyApp.Cache do
  use Jido.Plugin

  @impl true
  def validate_options(opts) do
    if is_integer(opts[:capacity]) and opts[:capacity] > 0,
      do: :ok,
      else: {:error, :invalid_capacity}
  end

  @impl true
  def state_spec(_opts), do: {:cache, Zoi.integer() |> Zoi.default(5)}

  @impl true
  def child_spec(init), do: Supervisor.child_spec({MyApp.CacheRuntime, init}, id: __MODULE__)

  @impl true
  def quiesce(runtime, _opts), do: GenServer.call(runtime, :quiesce)

  @impl true
  def resume(runtime, _opts), do: GenServer.call(runtime, :resume)

  @impl true
  def after_commit(runtime, commit, _opts), do: GenServer.call(runtime, {:commit, commit})
end

defmodule MyApp.Cached do
  use Jido.Agent, name: "cached"
  alias Jido.Agent.Directive, as: D

  state do
    schema(Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)}))
  end

  routes do
    signal_source("/my_app/cached")

    route "cache.install", as: :install do
      action %{capacity: capacity}, schema: Zoi.object(%{capacity: Zoi.integer()}), context: ctx do
        {:ok, ctx.agent_state, [D.plugin_add(MyApp.Cache, capacity: capacity)]}
      end
    end

    route "cache.configure", as: :configure do
      action %{capacity: capacity}, schema: Zoi.object(%{capacity: Zoi.integer()}), context: ctx do
        {:ok, ctx.agent_state, [D.plugin_configure(MyApp.Cache, capacity: capacity)]}
      end
    end

    route "cache.remove", as: :remove do
      action _input, context: ctx do
        {:ok, ctx.agent_state, [D.plugin_remove(MyApp.Cache, state: :discard)]}
      end
    end
  end
end

{:ok, _jido} = Jido.start()
{:ok, server} = Jido.start_agent(MyApp.Cached, id: "cached-1")
```

These Directives aren't effects. They edit the candidate Agent before
commit. The Plugin change and the rest of the Turn commit together as one
revision, or not at all.

### Add

`plugin_add(module, options, initial: value)` appends the Plugin and sets its
owned field from the schema default, or from `initial:`:

```elixir
install = MyApp.Cached.install_signal!(%{capacity: 2})
{:ok, agent, _directives} = Jido.AgentServer.call(server, install)

agent.state
# => %{count: 0, cache: 5}
```

`capacity: 2` is an option, not state, so `cache` gets its default of `5`.

| Error | Cause |
| --- | --- |
| `:plugin_exists` | The Plugin is already declared. |
| `:plugin_state_conflict` | Another owner already uses its state key. |

### Configure

`plugin_configure(module, options, migrate: {m, f, args})` replaces the
Plugin's options. The owned value carries over. If the new options change
the state key, pass `migrate:`. Jido calls `m.f(value, ...args)` and expects
`{:ok, next}`. Without it, a key change fails with
`:plugin_migration_required`.

Invalid options fail before the runtime is touched:

```elixir
bad = MyApp.Cached.configure_signal!(%{capacity: 0})
Jido.AgentServer.call(server, bad)
# => {:error, :invalid_capacity}
```

### Remove

`plugin_remove(module, state: :discard)` removes the Plugin and its owned
field:

```elixir
remove = MyApp.Cached.remove_signal!()
{:ok, agent, _directives} = Jido.AgentServer.call(server, remove)

agent.state
# => %{count: 0}
```

For a Plugin that owns state, `state: :discard` is required. Without it, the
Turn fails with `:plugin_state_discard_required`.

## Runtimes Must Pause

A runtime can be mid-write when its options change. Before Jido accepts any
live change to a Plugin with a runtime, the Plugin must implement both
`quiesce/2` and `resume/2`. Otherwise the Turn fails with
`:plugin_quiescence_required`.

The sequence:

1. **Quiesce.** Before commit, Jido calls `quiesce/2` on the current runtime.
   It must stop autonomous work and drain in-flight work before returning.
2. **Save.** The old runtime stays paused through the commit and any
   required storage write.
3. **Reconcile.** After the save, the activation replaces the runtime. The
   new one starts from `Jido.Plugin.Init` with the accepted state, revision,
   and options. No other Turn starts until this finishes.
4. **Resume on rejection.** If the change is rejected or cancelled before
   commit, Jido calls `resume/2` and the old runtime continues.

Make both callbacks idempotent. `resume/2` must be safe even if `quiesce/2`
didn't finish. A storage failure during the change stops the activation.

The commit reply can arrive before reconciliation finishes. Call
`Jido.AgentServer.await_ready/2` when your next step needs the new runtime.

## Hooks and Changes

A Plugin that is added, removed, or reconfigured doesn't receive
`after_commit/3` for that commit. Its new runtime starts from that commit
through `Jido.Plugin.Init`. Unchanged Plugins on the same Agent keep their
hooks.

With the cache above, the runtime's commit count reads:

| After | `commits` |
| --- | --- |
| The install Turn | `0` |
| An ordinary Turn, once its hook runs | `1` |
| A configure Turn (new runtime) | `0` |

Hooks run after the reply, so read runtime state after the hook finishes,
not right after `call/3` returns.

## Other Rules

- A Turn can't change a Plugin and also return a Directive owned by that
  Plugin. Jido rejects the batch.
- Live changes need an activation. `Jido.start_agent/2` provides one.
- `cmd/3` applies the same edits to the candidate and starts or stops
  nothing.

## Next

Continue with the built-in Plugins, starting with
[Signal Bus](signal-bus-plugin.livemd). The Checkpoints and Upgrades guide
covers saved-data upgrades.
