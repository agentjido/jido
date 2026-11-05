# Post-Commit Work

This guide covers the two Plugin callbacks that act on committed results across every Turn: `after_commit/3` and `prepare_outbound/4`. For Directive-specific work, see [Custom Directives](plugin-custom-directives.livemd).

Both callbacks run only in `Jido.AgentServer`. `Jido.Agent.cmd/3` does not call them.

## Observe each commit

`after_commit/3` runs after every successful Turn, including one that left state unchanged, and before Directives run. It takes the Plugin's runtime process or `nil`, a `Jido.Plugin.Context.Commit`, and the options. It returns `:ok` or `{:error, reason}`.

This Plugin projects its owned value to a search index, played here by a named process.

```elixir
{:ok, _index} = Agent.start(fn -> [] end, name: PostCommitGuide.SearchIndex)

defmodule PostCommitGuide.Indexer do
  use Jido.Plugin, option_keys: [agent_server: [:index, :fail]]

  alias Jido.Plugin.Context.Commit

  @impl true
  def state_spec(_opts), do: {:indexed_title, Jido.Joi.string() |> Jido.Joi.default("")}

  @impl true
  def reduce(reduction, _opts), do: {:ok, reduction.candidate_state.title}

  @impl true
  def after_commit(_runtime, %Commit{} = commit, opts) do
    if opts[:fail] do
      {:error, :index_unavailable}
    else
      entry = {commit.agent_id, commit.state_version, commit.plugin_state}
      Agent.update(opts[:index], &[entry | &1])
    end
  end
end

defmodule PostCommitGuide.Article do
  use Jido.Agent,
    name: "article",
    plugins: [{PostCommitGuide.Indexer, %{index: PostCommitGuide.SearchIndex}}]

  state do
    schema Jido.Joi.object(%{title: Jido.Joi.string() |> Jido.Joi.default("")})
  end

  routes do
    signal_source "/content/article"

    route "article.rename", as: :rename do
      action %{title: title},
        schema: Jido.Joi.object(%{title: Jido.Joi.string()}),
        context: context do
        {:ok, %{context.agent_state | title: title}}
      end
    end
  end
end

{:ok, _instance} = Jido.start(name: PostCommitGuide.Jido)
{:ok, article} = Jido.start_agent(PostCommitGuide.Jido, PostCommitGuide.Article, id: "a-1")
:ok = Jido.AgentServer.await_ready(article)

wait_for_idle = fn server ->
  Enum.find(1..200, fn _attempt ->
    Process.sleep(10)
    Jido.AgentServer.status(server).phase == :idle
  end)
end

{:ok, %{state: %{title: "Refunds"}}, []} =
  Jido.AgentServer.call(article, PostCommitGuide.Article.rename_signal!(%{title: "Refunds"}))

wait_for_idle.(article)
[{"a-1", 1, "Refunds"}] = Agent.get(PostCommitGuide.SearchIndex, & &1)
```

`Jido.AgentServer.call/3` replies when the Turn commits. The hook may still be running at that point, which is why the example waits for `:idle`. The next Turn waits in the queue until post-commit work finishes.

`Jido.Plugin.Context.Commit` holds the Plugin's committed value and the revision of the same commit, plus identity:

| Field | Value |
|---|---|
| `:plugin` | The Plugin module. |
| `:turn_id`, `:agent_id`, `:agent_module` | Identity of this Turn and Agent. |
| `:plugin_state` | The committed value of this Plugin's field, or `nil`. |
| `:state_version` | The committed revision. |
| `:jido`, `:partition` | The instance and partition, or `nil`. |

It has no complete Agent, no caller context, and no way to change the commit. A hook cannot return Directives. To change state, send a new Signal with `Jido.AgentServer.cast/2`. A synchronous call to its own server returns `{:error, :reentrant_turn}`.

Use a hook when the work follows every commit and reads only the Plugin's own field. Use a Directive when a handler decides, per Turn, that some work should happen.

## What happens on failure

A commit is final. A failure after commit stops the remaining post-commit work and leaves the commit and the caller's result in place.

```elixir
{:ok, failing} =
  Jido.start_agent(PostCommitGuide.Jido, PostCommitGuide.Article,
    id: "a-2",
    plugin_runtime_options: [{PostCommitGuide.Indexer, [fail: true]}]
  )

:ok = Jido.AgentServer.await_ready(failing)

{:ok, %{state: %{title: "Refunds"}}, []} =
  Jido.AgentServer.call(failing, PostCommitGuide.Article.rename_signal!(%{title: "Refunds"}))

wait_for_idle.(failing)

%{last_outcome: %{status: :succeeded}, last_effect_outcome: %{status: :failed, stage: :after_commit}} =
  Jido.AgentServer.status(failing)

:ok = Jido.stop_agent(PostCommitGuide.Jido, failing)
```

The rules are:

- Hooks run in declaration order, one at a time, each in a task the server owns.
- A hook that returns an error, returns an invalid value, or raises skips later hooks and all Directives.
- `last_effect_outcome` in `Jido.AgentServer.status/1` reports `:failed` or `:timed_out`, the `:stage` (`:after_commit` or `:directive`), and how many Directives completed.
- The telemetry event `[:jido, :agent_server, :effects, :stop]` reports the same status and stage.
- The server does not pass this failure to its `error_policy`, and it stays ready for the next Turn.
- Hooks are not replayed. A server that restarts or thaws does not call them for past commits.

Because hooks are not replayed, a resource that needs to match committed state must rebuild from `Jido.Plugin.Init` when it starts. See [Supervised Resources](plugin-supervised-resources.livemd).

## Time limits

| Option | Default | Covers |
|---|---|---|
| `commit_timeout` | 5,000 ms | All `after_commit/3` hooks of one Turn, shared. |
| `directive_timeout` | 5,000 ms | All Directives of one Turn, shared. It starts after the hooks finish. |
| `turn_timeout` | 60,000 ms | The Turn up to commit, including `admit/3`. |

Set them as options to `Jido.start_agent/3`, or as `agent_server:` defaults on the instance. `commit_timeout` and `directive_timeout` must be finite. When a budget runs out, the server stops the running task and records `:timed_out`. Keep hooks short, and hand slow work to a runtime process with a cast.

## Prepare outbound Signals

`prepare_outbound/4` sees each Signal that an Emit, Reply, AgentSend, or ParentSend Directive sends, before delivery. It takes the runtime process or `nil`, the Signal, a `Jido.Plugin.Context` with `phase: :signal`, and the options. It returns `{:ok, signal}` to continue or `{:error, reason}` to stop delivery.

Plugins run in reverse declaration order. This lets a Plugin declared first, such as encryption, wrap what later Plugins produce. `context.plugin_state` holds each Plugin's own committed value. `context.target` holds the Emit's dispatch configuration, `{:agent, name}`, `:reply`, or `:parent`.

```elixir
defmodule PostCommitGuide.Stamp do
  use Jido.Plugin, option_keys: [agent_server: [:name]]

  @impl true
  def prepare_outbound(_runtime, signal, %Jido.Plugin.Context{phase: :signal} = context, opts) do
    stamped = [{opts[:name], context.state_version} | Map.get(signal.data, :stamps, [])]
    {:ok, %{signal | data: Map.put(signal.data, :stamps, stamped)}}
  end
end

defmodule PostCommitGuide.StampSecond do
  use Jido.Plugin, option_keys: [agent_server: [:name]]

  @impl true
  def prepare_outbound(runtime, signal, context, opts),
    do: PostCommitGuide.Stamp.prepare_outbound(runtime, signal, context, opts)
end

defmodule PostCommitGuide.Publisher do
  use Jido.Agent,
    name: "publisher",
    plugins: [
      {PostCommitGuide.Stamp, %{name: :declared_first}},
      {PostCommitGuide.StampSecond, %{name: :declared_second}}
    ]

  routes do
    signal_source "/content/publisher"

    route "article.publish", as: :publish do
      action _input, schema: Jido.Joi.object(%{}), context: context do
        notice = Jido.Signal.new!("article.published", %{}, source: "/content/publisher")
        {:ok, context.agent_state, [Jido.Agent.Directive.emit(notice, {:pid, target: context.observer})]}
      end
    end
  end
end

{:ok, publisher} = Jido.start_agent(PostCommitGuide.Jido, PostCommitGuide.Publisher, id: "p-1")
:ok = Jido.AgentServer.await_ready(publisher)

{:ok, _agent, [_emit]} =
  Jido.AgentServer.call(publisher, PostCommitGuide.Publisher.publish_signal!(%{}), context: %{observer: self()})

stamps =
  receive do
    {:signal, %{type: "article.published", data: %{stamps: stamps}}} -> stamps
  after
    1_000 -> :not_delivered
  end

[declared_first: 1, declared_second: 1] = stamps
:ok = Jido.stop_agent(PostCommitGuide.Jido, publisher)
```

`:declared_second` ran first, so `:declared_first` stamped last and sits at the head of the list.

A rejection or an invalid Signal counts as a failed Directive, and the Turn's remaining Directives do not run. A Reply must keep its id, causation, and trace. Changing them fails with `:invalid_reply_correlation`.

## Next steps

- [Custom Directives](plugin-custom-directives.livemd) covers `dispatch/4`.
- [Turns and Effects](../core-concepts/turns-commits-and-effects.md) explains the commit boundary.
- [Status and Turn History](../agent-servers/status-and-history.md) describes `last_effect_outcome`.
