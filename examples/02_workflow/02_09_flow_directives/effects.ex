defmodule Jido.Examples.FlowDirectives.Effects.Record do
  @moduledoc "One post-commit Flow observation."
  use Jido.Agent.Directive

  defstruct [:label]

  @impl true
  def validate(%__MODULE__{label: label} = directive)
      when is_binary(label) and byte_size(label) > 0,
      do: {:ok, directive}

  def validate(_directive),
    do: {:error, Jido.Error.validation_error("Flow Directive label must not be empty")}
end

defmodule Jido.Examples.FlowDirectives.Effects do
  @moduledoc "Records ordered Flow Directives after the Agent commit."
  use Jido.Plugin

  alias Jido.Examples.FlowDirectives.Effects.{Record, Runtime}

  @impl true
  def directives(_opts), do: [Record]

  @impl true
  def child_spec(init), do: Supervisor.child_spec({Runtime, init}, id: __MODULE__)

  @impl true
  def dispatch(runtime, directive, context, _opts),
    do: GenServer.call(runtime, {:record, directive, context})

  @doc "Reads recorded labels and the public snapshots seen during dispatch."
  def records(server) do
    %{pid: runtime} = Jido.AgentServer.children(server)[{:plugin, __MODULE__}]
    GenServer.call(runtime, :records)
  end
end

defmodule Jido.Examples.FlowDirectives.Effects.Runtime do
  @moduledoc false
  use GenServer

  def start_link(init), do: GenServer.start_link(__MODULE__, init)

  @impl true
  def init(init), do: {:ok, %{server: init.agent_server, records: []}}

  @impl true
  def handle_call(:records, _from, state), do: {:reply, state.records, state}

  def handle_call({:record, directive, context}, _from, state) do
    record = %{
      label: directive.label,
      snapshot: Jido.AgentServer.snapshot(state.server),
      turn_id: context.turn_id
    }

    {:reply, :ok, %{state | records: state.records ++ [record]}}
  end
end
