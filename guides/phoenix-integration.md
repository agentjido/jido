# Phoenix Integration

**After:** You can run Jido agents inside a Phoenix application with LiveView updates.

This guide shows how to integrate Jido agents with Phoenix controllers, LiveView, and PubSub for real-time UI updates.

## Adding Jido to Your Supervision Tree

Create a Jido instance module in your Phoenix app:

```elixir
# lib/my_app/jido.ex
defmodule MyApp.Jido do
  use Jido, otp_app: :my_app
end
```

Add it to your application supervision tree *before* the Endpoint:

```elixir
# lib/my_app/application.ex
defmodule MyApp.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      MyApp.Repo,
      MyApp.Jido,
      {Phoenix.PubSub, name: MyApp.PubSub},
      MyAppWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

Optional config in `config/config.exs`:

```elixir
config :my_app, MyApp.Jido,
  max_tasks: 1000,
  agent_pools: []
```

## Sending Signals from Controllers

Start an agent and send signals from a Phoenix controller:

```elixir
# lib/my_app_web/controllers/counter_controller.ex
defmodule MyAppWeb.CounterController do
  use MyAppWeb, :controller

  alias Jido.Signal

  def show(conn, %{"id" => id}) do
    case MyApp.Jido.whereis(id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "Agent not found"})

      pid ->
        {:ok, state} = Jido.AgentServer.state(pid)
        json(conn, %{id: id, count: state.agent.state.count})
    end
  end

  def create(conn, %{"id" => id}) do
    case MyApp.Jido.start_agent(MyApp.CounterAgent, id: id) do
      {:ok, _pid} ->
        conn |> put_status(:created) |> json(%{id: id, count: 0})

      {:error, {:already_started, _pid}} ->
        conn |> put_status(:conflict) |> json(%{error: "Agent already exists"})
    end
  end

  def increment(conn, %{"id" => id, "amount" => amount}) do
    signal = Signal.new!("counter.increment", %{amount: amount}, source: "/api")

    case MyApp.Jido.whereis(id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "Agent not found"})

      pid ->
        {:ok, agent} = Jido.AgentServer.call(pid, signal)
        json(conn, %{id: id, count: agent.state.count})
    end
  end
end
```

## Broadcasting State Changes

Use PubSub to broadcast agent state changes. Define an action that emits to PubSub:

```elixir
# lib/my_app/actions/increment.ex
defmodule MyApp.Actions.Increment do
  use Jido.Action,
    name: "increment",
    schema: [amount: [type: :integer, default: 1]]

  alias Jido.Agent.Directive

  def run(%{amount: amount}, context) do
    current = context.state[:count] || 0
    new_count = current + amount

    broadcast_signal =
      Jido.Signal.new!("counter.updated", %{count: new_count}, source: "/agent")

    {:ok, %{count: new_count}, [
      Directive.emit(broadcast_signal, {:pubsub, pubsub: MyApp.PubSub, topic: "counter:updates"})
    ]}
  end
end
```

Or broadcast from the controller after the call returns:

```elixir
def increment(conn, %{"id" => id, "amount" => amount}) do
  signal = Signal.new!("counter.increment", %{amount: amount}, source: "/api")

  with pid when is_pid(pid) <- MyApp.Jido.whereis(id),
       {:ok, agent} <- Jido.AgentServer.call(pid, signal) do
    Phoenix.PubSub.broadcast(MyApp.PubSub, "counter:#{id}", {:counter_updated, agent.state})
    json(conn, %{id: id, count: agent.state.count})
  else
    nil -> conn |> put_status(:not_found) |> json(%{error: "Agent not found"})
    {:error, reason} -> conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(reason)})
  end
end
```

## LiveView Integration

Subscribe to agent updates and render state in real-time:

```elixir
# lib/my_app_web/live/counter_live.ex
defmodule MyAppWeb.CounterLive do
  use MyAppWeb, :live_view

  alias Jido.Signal

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(MyApp.PubSub, "counter:#{id}")
    end

    socket =
      socket
      |> assign(:id, id)
      |> assign_agent_state(id)

    {:ok, socket}
  end

  defp assign_agent_state(socket, id) do
    case MyApp.Jido.whereis(id) do
      nil ->
        assign(socket, count: nil, error: "Agent not found")

      pid ->
        {:ok, state} = Jido.AgentServer.state(pid)
        assign(socket, count: state.agent.state.count, error: nil)
    end
  end

  @impl true
  def handle_event("increment", %{"amount" => amount}, socket) do
    amount = String.to_integer(amount)
    send_signal(socket.assigns.id, "counter.increment", %{amount: amount})
    {:noreply, socket}
  end

  def handle_event("decrement", _params, socket) do
    send_signal(socket.assigns.id, "counter.decrement", %{amount: 1})
    {:noreply, socket}
  end

  def handle_event("reset", _params, socket) do
    send_signal(socket.assigns.id, "counter.reset", %{})
    {:noreply, socket}
  end

  defp send_signal(id, type, data) do
    signal = Signal.new!(type, data, source: "/liveview")

    case MyApp.Jido.whereis(id) do
      nil -> :ok
      pid -> Jido.AgentServer.cast(pid, signal)
    end
  end

  @impl true
  def handle_info({:counter_updated, state}, socket) do
    {:noreply, assign(socket, count: state.count)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="counter">
      <h1>Counter: <%= @id %></h1>

      <%= if @error do %>
        <p class="error"><%= @error %></p>
      <% else %>
        <p class="count"><%= @count %></p>

        <div class="controls">
          <button phx-click="decrement">-</button>
          <button phx-click="increment" phx-value-amount="1">+1</button>
          <button phx-click="increment" phx-value-amount="10">+10</button>
          <button phx-click="reset">Reset</button>
        </div>
      <% end %>
    </div>
    """
  end
end
```

Add the route:

```elixir
# lib/my_app_web/router.ex
live "/counter/:id", CounterLive
```

## JSON API Responses

Extract agent state for API responses:

```elixir
defmodule MyAppWeb.AgentJSON do
  def show(%{agent: agent}) do
    %{
      id: agent.id,
      state: sanitize_state(agent.state),
      dirty_state: agent.dirty_state
    }
  end

  defp sanitize_state(state) when is_map(state) do
    state
    |> Map.drop([:__internal__, :children])
    |> Map.new(fn {k, v} -> {k, serialize_value(v)} end)
  end

  defp serialize_value(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp serialize_value(value), do: value
end
```

Use in controllers:

```elixir
def show(conn, %{"id" => id}) do
  with pid when is_pid(pid) <- MyApp.Jido.whereis(id),
       {:ok, state} <- Jido.AgentServer.state(pid) do
    render(conn, :show, agent: state.agent)
  else
    nil -> conn |> put_status(:not_found) |> json(%{error: "not_found"})
  end
end
```

## Complete Example: Counter with LiveView

Here's a complete working example you can copy into a Phoenix app.

### The Agent

```elixir
# lib/my_app/agents/counter_agent.ex
defmodule MyApp.CounterAgent do
  use Jido.Agent,
    name: "counter",
    description: "A counter with PubSub broadcasting",
    schema: [
      count: [type: :integer, default: 0]
    ]

  def signal_routes do
    [
      {"counter.increment", MyApp.Actions.Increment},
      {"counter.decrement", MyApp.Actions.Decrement},
      {"counter.reset", MyApp.Actions.Reset}
    ]
  end
end
```

### The Actions

```elixir
# lib/my_app/actions/counter_actions.ex
defmodule MyApp.Actions.Increment do
  use Jido.Action,
    name: "increment",
    schema: [amount: [type: :integer, default: 1]]

  def run(%{amount: amount}, context) do
    {:ok, %{count: (context.state[:count] || 0) + amount}}
  end
end

defmodule MyApp.Actions.Decrement do
  use Jido.Action,
    name: "decrement",
    schema: [amount: [type: :integer, default: 1]]

  def run(%{amount: amount}, context) do
    {:ok, %{count: (context.state[:count] || 0) - amount}}
  end
end

defmodule MyApp.Actions.Reset do
  use Jido.Action,
    name: "reset",
    schema: []

  def run(_params, _context) do
    {:ok, %{count: 0}}
  end
end
```

### The LiveView with Inline Broadcast

```elixir
# lib/my_app_web/live/counter_live.ex
defmodule MyAppWeb.CounterLive do
  use MyAppWeb, :live_view

  alias Jido.Signal

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(MyApp.PubSub, "counter:#{id}")
      ensure_agent_started(id)
    end

    {:ok, socket |> assign(:id, id) |> load_count(id)}
  end

  defp ensure_agent_started(id) do
    case MyApp.Jido.whereis(id) do
      nil -> MyApp.Jido.start_agent(MyApp.CounterAgent, id: id)
      _pid -> :ok
    end
  end

  defp load_count(socket, id) do
    case MyApp.Jido.whereis(id) do
      nil -> assign(socket, count: 0)
      pid ->
        {:ok, state} = Jido.AgentServer.state(pid)
        assign(socket, count: state.agent.state.count)
    end
  end

  @impl true
  def handle_event("increment", %{"amount" => amount}, socket) do
    {:noreply, send_and_broadcast(socket, "counter.increment", %{amount: String.to_integer(amount)})}
  end

  def handle_event("decrement", _params, socket) do
    {:noreply, send_and_broadcast(socket, "counter.decrement", %{amount: 1})}
  end

  def handle_event("reset", _params, socket) do
    {:noreply, send_and_broadcast(socket, "counter.reset", %{})}
  end

  defp send_and_broadcast(socket, type, data) do
    id = socket.assigns.id
    signal = Signal.new!(type, data, source: "/liveview")

    case MyApp.Jido.whereis(id) do
      nil ->
        socket

      pid ->
        {:ok, agent} = Jido.AgentServer.call(pid, signal)
        Phoenix.PubSub.broadcast(MyApp.PubSub, "counter:#{id}", {:counter_updated, agent.state})
        assign(socket, count: agent.state.count)
    end
  end

  @impl true
  def handle_info({:counter_updated, state}, socket) do
    {:noreply, assign(socket, count: state.count)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-8">
      <h1 class="text-2xl font-bold mb-4">Counter: <%= @id %></h1>
      <p class="text-6xl font-mono mb-8"><%= @count %></p>

      <div class="flex gap-2">
        <button phx-click="decrement" class="px-4 py-2 bg-red-500 text-white rounded">-1</button>
        <button phx-click="increment" phx-value-amount="1" class="px-4 py-2 bg-green-500 text-white rounded">+1</button>
        <button phx-click="increment" phx-value-amount="10" class="px-4 py-2 bg-green-700 text-white rounded">+10</button>
        <button phx-click="reset" class="px-4 py-2 bg-gray-500 text-white rounded">Reset</button>
      </div>

      <p class="mt-4 text-gray-500">Open this page in multiple tabs to see real-time sync.</p>
    </div>
    """
  end
end
```

### Router

```elixir
# lib/my_app_web/router.ex
scope "/", MyAppWeb do
  pipe_through :browser

  live "/counter/:id", CounterLive
end
```

Visit `/counter/my-counter` in multiple browser tabs. Changes sync in real-time.

## Next Steps

- [Signals](signals.md) — Signal routing and creation
- [Persistence & Storage](storage.md) — Hibernate/thaw and InstanceManager for session agents
- [Worker Pools](worker-pools.md) — Pre-warmed agent pools for high-throughput APIs
- [Runtime](runtime.md) — AgentServer lifecycle and parent-child hierarchies
- [Await & Coordination](await.md) — Wait for agent completion
