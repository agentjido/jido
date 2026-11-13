defmodule Jido.Examples.StartHere.ExpenseNotification do
  @moduledoc "Requests one notification after an expense commit."

  use Jido.Agent.Directive

  defstruct [:report_id, :status]

  @impl true
  def validate(%__MODULE__{report_id: report_id, status: status} = directive)
      when is_binary(report_id) and byte_size(report_id) > 0 and
             status in [:approved, :rejected, :expired],
      do: {:ok, directive}

  def validate(_directive),
    do: {:error, Jido.Error.validation_error("invalid expense notification")}
end

defmodule Jido.Examples.StartHere.ExpenseNotifications do
  @moduledoc "Records deterministic notifications after the Agent state commit."

  use Jido.Plugin

  alias Jido.Examples.StartHere.{ExpenseNotification, ExpenseNotificationRuntime}

  @impl true
  def directives(_opts), do: [ExpenseNotification]

  @impl true
  def child_spec(init), do: Supervisor.child_spec({ExpenseNotificationRuntime, init}, id: __MODULE__)

  @impl true
  def dispatch(runtime, directive, context, _opts),
    do: GenServer.call(runtime, {:record, directive, context})

  @doc "Waits for a bounded notification count through the Plugin's public API."
  def await(instance, server, count, timeout \\ 1_000) do
    id = Jido.AgentServer.snapshot(server).agent.id

    case :global.whereis_name({ExpenseNotificationRuntime, instance, id}) do
      :undefined -> {:error, :runtime_not_found}
      runtime -> GenServer.call(runtime, {:await, count}, timeout)
    end
  end

  @doc "Returns the current runtime process for cleanup observation."
  def runtime(instance, server) do
    id = Jido.AgentServer.snapshot(server).agent.id

    case :global.whereis_name({ExpenseNotificationRuntime, instance, id}) do
      :undefined -> nil
      runtime -> runtime
    end
  end
end

defmodule Jido.Examples.StartHere.ExpenseNotificationRuntime do
  @moduledoc false
  use GenServer

  def start_link(init) do
    GenServer.start_link(__MODULE__, init, name: {:global, {__MODULE__, init.jido, init.agent_id}})
  end

  @impl true
  def init(init), do: {:ok, %{server: init.agent_server, records: [], waiters: []}}

  @impl true
  def handle_call({:await, count}, from, state) do
    if length(state.records) >= count do
      {:reply, {:ok, state.records}, state}
    else
      {:noreply, %{state | waiters: [{from, count} | state.waiters]}}
    end
  end

  def handle_call({:record, directive, context}, _from, state) do
    record = %{
      report_id: directive.report_id,
      status: directive.status,
      turn_id: context.turn_id,
      snapshot: Jido.AgentServer.snapshot(state.server)
    }

    state = %{state | records: state.records ++ [record]}
    {ready, waiting} = Enum.split_with(state.waiters, fn {_from, count} -> length(state.records) >= count end)
    Enum.each(ready, fn {from, _count} -> GenServer.reply(from, {:ok, state.records}) end)
    {:reply, :ok, %{state | waiters: waiting}}
  end
end
