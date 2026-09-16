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

  def validate(%__MODULE__{} = directive) do
    case Zoi.parse(@schema, Map.from_struct(directive)) do
      {:ok, validated} -> {:ok, validated}
      {:error, errors} -> {:error, Jido.Error.validation_error("invalid record", details: errors)}
    end
  end
end

defmodule Jido.Examples.DirectiveAgent.Effects do
  @moduledoc "A real Plugin runtime that records post-commit dispatch observations."

  use Jido.Plugin, agent: __MODULE__.Agent, agent_server: __MODULE__.Server

  def records(server) do
    %{pid: runtime} = Jido.AgentServer.children(server)[{:plugin, __MODULE__}]
    GenServer.call(runtime, :records)
  end
end

defmodule Jido.Examples.DirectiveAgent.Effects.Agent do
  use Jido.Agent.Plugin
  alias Jido.Examples.DirectiveAgent.Record

  @impl true
  def directives(_opts), do: [Record]
end

defmodule Jido.Examples.DirectiveAgent.Effects.Server do
  use Jido.AgentServer.Plugin
  alias Jido.Examples.DirectiveAgent.EffectRuntime

  @impl true
  def dispatch(runtime, directive, context, _opts),
    do: GenServer.call(runtime, {:record, directive, context})

  def child_spec(init),
    do: Supervisor.child_spec({EffectRuntime, init}, id: Jido.Examples.DirectiveAgent.Effects)
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
