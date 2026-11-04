defmodule Jido.Examples.DirectiveAgent.Record do
  @moduledoc false

  @schema Jido.Joi.struct(
            __MODULE__,
            %{
              label: Jido.Joi.string() |> Jido.Joi.min(1),
              fail?: Jido.Joi.boolean() |> Jido.Joi.default(false)
            },
            coerce: true
          )

  @type t :: unquote(Jido.Joi.type_spec(@schema))
  @enforce_keys Jido.Joi.enforce_keys(@schema)
  defstruct Jido.Joi.struct_fields(@schema)

  def schema, do: @schema

  def validate(%__MODULE__{} = directive) do
    case Jido.Joi.parse(@schema, Map.from_struct(directive)) do
      {:ok, validated} -> {:ok, validated}
      {:error, errors} -> {:error, Jido.Error.validation_error("invalid record", details: errors)}
    end
  end
end

defmodule Jido.Examples.DirectiveAgent.Effects do
  @moduledoc "A real Plugin runtime that records post-commit dispatch observations."

  use Jido.Plugin

  @impl true
  def directives(_opts), do: [Jido.Examples.DirectiveAgent.Record]

  @impl true
  def dispatch(runtime, directive, context, _opts),
    do: GenServer.call(runtime, {:record, directive, context})

  @impl true
  def child_spec(init),
    do: Supervisor.child_spec({Jido.Examples.DirectiveAgent.EffectRuntime, init}, id: __MODULE__)

  def runtime(jido, id) do
    case Registry.lookup(Jido.Instance.Names.registry(jido), {__MODULE__, id}) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  def records(jido, id), do: GenServer.call(runtime(jido, id), :records)
end

defmodule Jido.Examples.DirectiveAgent.EffectRuntime do
  @moduledoc false

  use GenServer

  def start_link(init) do
    name =
      {:via, Registry, {Jido.Instance.Names.registry(init.jido), {Jido.Examples.DirectiveAgent.Effects, init.agent_id}}}

    GenServer.start_link(__MODULE__, init, name: name)
  end

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
