defmodule Jido.Examples.DirectiveAgent.Record do
  @moduledoc false

  @schema Zoi.struct(
            __MODULE__,
            %{
              label: Zoi.string() |> Zoi.min(1),
              fail?: Zoi.boolean() |> Zoi.default(false)
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  def schema, do: @schema
end

defmodule Jido.Examples.DirectiveAgent.Effects do
  @moduledoc "A real Plugin runtime that records post-commit dispatch observations."

  use Jido.Plugin

  alias Jido.Examples.DirectiveAgent.{Record, EffectRuntime}

  @impl true
  def directives(_opts), do: [Record]

  @impl true
  def validate_directive(%Record{} = directive, _opts) do
    case Zoi.parse(Record.schema(), Map.from_struct(directive)) do
      {:ok, validated} -> {:ok, validated}
      {:error, errors} -> {:error, Jido.Error.validation_error("invalid record", details: errors)}
    end
  end

  @impl true
  def dispatch(runtime, directive, context, _opts) do
    GenServer.call(runtime, {:record, directive, context})
  end

  def child_spec(init), do: Supervisor.child_spec({EffectRuntime, init}, id: __MODULE__)

  def records(server) do
    %{pid: runtime} = Jido.AgentServer.children(server)[{:plugin, __MODULE__}]
    GenServer.call(runtime, :records)
  end
end

defmodule Jido.Examples.DirectiveAgent.StatelessEffects do
  @moduledoc "A typed recording capability without a Plugin process."

  use Jido.Plugin

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.DirectiveAgent.{Effects, Record}

  @impl true
  def directives(_opts), do: [Record]

  @impl true
  defdelegate validate_directive(directive, opts), to: Effects

  @impl true
  def dispatch(nil, directive, context, _opts) do
    server = Jido.whereis_agent(context.jido, context.agent_id, partition: context.partition)
    record = %{label: directive.label, snapshot: Server.snapshot(server), context: context}
    # This is local test observation. Domain results use Signals.
    send(context.turn_context.observer, {:sdk_record, server, record})

    if directive.fail?,
      do: {:error, Jido.Error.execution_error("record dispatch failed")},
      else: :ok
  end
end

defmodule Jido.Examples.DirectiveAgent.EffectRuntime do
  @moduledoc false

  use GenServer

  def start_link(init), do: GenServer.start_link(__MODULE__, init)

  @impl true
  def init(init), do: {:ok, %{server: init.agent_server, records: []}}

  @impl true
  def handle_call(:records, _from, state), do: {:reply, state.records, state}

  def handle_call({:record, directive, context}, _from, state) do
    # Read through the same public API an external capability can use.
    record = %{
      label: directive.label,
      snapshot: Jido.AgentServer.snapshot(state.server),
      context: context
    }

    result =
      if directive.fail?,
        do: {:error, Jido.Error.execution_error("record dispatch failed")},
        else: :ok

    {:reply, result, %{state | records: state.records ++ [record]}}
  end
end
